const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const Anthropic = require("@anthropic-ai/sdk").default;

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// Initialize Anthropic client
const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY || "",
});

/**
 * Triggered when a new chat message is created in any room.
 * Sends push notifications to all players in the room (except the sender).
 */
exports.onNewChatMessage = onDocumentCreated(
  "rooms/{roomCode}/chat/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data in snapshot");
      return null;
    }

    const message = snapshot.data();
    const roomCode = event.params.roomCode;
    const senderId = message.playerId;
    const senderName = message.playerName || "Someone";
    const messageText = message.text || "";

    console.log(`New message in room ${roomCode} from ${senderName}`);

    // Get room info
    const roomDoc = await db.collection("rooms").doc(roomCode).get();
    if (!roomDoc.exists) {
      console.log("Room not found");
      return null;
    }

    const room = roomDoc.data();
    const hostId = room.hostId;

    // Get all players in the room
    const playersSnapshot = await db
      .collection("rooms")
      .doc(roomCode)
      .collection("players")
      .get();

    // Collect all user IDs who should receive notification (host + players, except sender)
    const recipientIds = new Set();

    // Add host if not the sender
    if (hostId && hostId !== senderId) {
      recipientIds.add(hostId);
    }

    // Add all players except sender
    playersSnapshot.docs.forEach((doc) => {
      const playerId = doc.data().id;
      if (playerId && playerId !== senderId) {
        recipientIds.add(playerId);
      }
    });

    if (recipientIds.size === 0) {
      console.log("No recipients to notify");
      return null;
    }

    console.log(`Notifying ${recipientIds.size} users`);

    // Get FCM tokens for all recipients and calculate their unread counts
    const notifications = [];

    for (const userId of recipientIds) {
      try {
        // Get user's FCM tokens from subcollection (iOS only)
        const tokensSnapshot = await db
          .collection("users")
          .doc(userId)
          .collection("fcmTokens")
          .where("platform", "==", "ios")
          .get();

        // Also check legacy fcmToken field directly on user document
        const userDoc = await db.collection("users").doc(userId).get();
        const legacyToken = userDoc.exists ? userDoc.data().fcmToken : null;

        if (tokensSnapshot.empty && !legacyToken) {
          console.log(`No FCM tokens for user ${userId}`);
          continue;
        }

        // Calculate total unread count for this user
        const unreadCount = await calculateTotalUnreadCount(userId);

        // Collect tokens from both sources
        const tokens = new Set();

        // Add tokens from subcollection
        for (const tokenDoc of tokensSnapshot.docs) {
          const token = tokenDoc.data().token;
          if (token) tokens.add(token);
        }

        // Add legacy token if exists
        if (legacyToken) {
          tokens.add(legacyToken);
          console.log(`Using legacy fcmToken for user ${userId}`);
        }

        // Create notifications for all tokens
        for (const token of tokens) {
          notifications.push({
            token,
            userId,
            unreadCount,
          });
        }
      } catch (error) {
        console.error(`Error processing user ${userId}:`, error);
      }
    }

    // Send all notifications
    const sendPromises = notifications.map(async ({ token, userId, unreadCount }) => {
      try {
        const payload = {
          token,
          notification: {
            title: senderName,
            body: messageText.length > 100 ? messageText.substring(0, 100) + "..." : messageText,
          },
          apns: {
            payload: {
              aps: {
                badge: unreadCount,
                sound: "default",
                "content-available": 1,
              },
            },
          },
          data: {
            roomCode,
            type: "chat_message",
          },
        };

        await messaging.send(payload);
        console.log(`Notification sent to user ${userId}`);
      } catch (error) {
        console.error(`Error sending to token:`, error.message);
        // If token is invalid, remove it
        if (
          error.code === "messaging/invalid-registration-token" ||
          error.code === "messaging/registration-token-not-registered"
        ) {
          await removeInvalidToken(token);
        }
      }
    });

    await Promise.all(sendPromises);
    console.log(`Finished sending ${notifications.length} notifications`);
    return null;
  }
);

/**
 * Calculate total unread message count for a user across ALL their rooms.
 * This is used for the iOS app badge to show total unread messages for the recipient.
 */
async function calculateTotalUnreadCount(userId) {
  let totalUnread = 0;

  try {
    // Get user's last read timestamps for all rooms
    const roomReadsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("roomReads")
      .get();

    const lastReadMap = new Map();
    roomReadsSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      if (data.lastReadAt) {
        lastReadMap.set(doc.id, data.lastReadAt.toDate());
      }
    });

    // Get rooms where user is host
    const hostedRoomsSnapshot = await db
      .collection("rooms")
      .where("hostId", "==", userId)
      .get();

    const roomCodes = new Set();

    // Add hosted rooms
    hostedRoomsSnapshot.docs.forEach((doc) => {
      roomCodes.add(doc.id);
    });

    // Get rooms where user is a player (collection group query)
    try {
      const playerRoomsSnapshot = await db
        .collectionGroup("players")
        .where("id", "==", userId)
        .get();

      for (const playerDoc of playerRoomsSnapshot.docs) {
        const roomCode = playerDoc.ref.parent.parent?.id;
        if (roomCode) {
          roomCodes.add(roomCode);
        }
      }
    } catch (err) {
      console.log("Could not query players collection group:", err.message);
    }

    // Get user's teams for team rooms
    try {
      const teamsSnapshot = await db
        .collectionGroup("members")
        .where("id", "==", userId)
        .get();

      const teamIds = new Set();
      teamsSnapshot.docs.forEach((doc) => {
        const teamId = doc.ref.parent.parent?.id;
        if (teamId) {
          teamIds.add(teamId);
        }
      });

      // Get team rooms
      if (teamIds.size > 0) {
        const teamIdsArray = Array.from(teamIds).slice(0, 30); // Firestore limit
        const teamRoomsSnapshot = await db
          .collection("rooms")
          .where("teamId", "in", teamIdsArray)
          .get();

        teamRoomsSnapshot.docs.forEach((doc) => {
          roomCodes.add(doc.id);
        });
      }
    } catch (err) {
      console.log("Could not query members collection group:", err.message);
    }

    console.log(`Calculating unread for user ${userId} across ${roomCodes.size} rooms`);

    // Calculate unread for each room
    for (const roomCode of roomCodes) {
      const lastRead = lastReadMap.get(roomCode);

      // Get all chat messages (or messages after lastRead)
      let query = db.collection("rooms").doc(roomCode).collection("chat");
      if (lastRead) {
        query = query.where("sentAt", ">", lastRead);
      }

      const chatSnapshot = await query.get();
      let unreadInRoom = 0;

      chatSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        // Only count messages NOT sent by this user
        if (data.playerId !== userId) {
          unreadInRoom++;
        }
      });

      totalUnread += unreadInRoom;
    }

    console.log(`Total unread for user ${userId}: ${totalUnread}`);
  } catch (error) {
    console.error("Error calculating unread count:", error);
  }

  return totalUnread;
}

/**
 * Remove an invalid FCM token from all users.
 */
async function removeInvalidToken(token) {
  try {
    const tokensSnapshot = await db
      .collectionGroup("fcmTokens")
      .where("token", "==", token)
      .get();

    const deletePromises = tokensSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(deletePromises);
    console.log(`Removed invalid token: ${token.substring(0, 20)}...`);
  } catch (error) {
    console.error("Error removing invalid token:", error);
  }
}

/**
 * AI-powered answer evaluation using Claude.
 * Called when a player submits an answer in AI evaluation mode.
 */
exports.evaluateAnswerWithAI = onCall(
  {
    secrets: ["ANTHROPIC_API_KEY"],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    // Verify authentication
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated to use this function"
      );
    }

    const { question, expectedAnswer, playerAnswer, roomCode, messageId, playerId } = request.data;

    console.log(`AI Evaluation request: room=${roomCode}, messageId=${messageId}, playerId=${playerId}`);
    console.log(`Question: "${question}", Expected: "${expectedAnswer}", Player: "${playerAnswer}"`);

    if (!question || !expectedAnswer || !playerAnswer) {
      console.error(`Missing fields: question=${!!question}, expectedAnswer=${!!expectedAnswer}, playerAnswer=${!!playerAnswer}`);
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields: question, expectedAnswer, playerAnswer"
      );
    }

    try {
      const result = await evaluateAnswer(question, expectedAnswer, playerAnswer);

      // Update the chat message with AI evaluation result
      if (roomCode && messageId) {
        const messageRef = db
          .collection("rooms")
          .doc(roomCode)
          .collection("chat")
          .doc(messageId);

        const updateData = {
          aiSuggestion: result.isCorrect,
          aiConfidence: result.confidence,
          aiReasoning: result.explanation,
        };

        // Auto-mark if high confidence (>= 0.8)
        if (result.confidence >= 0.8) {
          updateData.isCorrect = result.isCorrect;

          // Award points if marking as correct
          if (result.isCorrect && playerId) {
            // Count existing correct answers in this room
            const correctAnswersSnapshot = await db
              .collection("rooms")
              .doc(roomCode)
              .collection("chat")
              .where("isCorrect", "==", true)
              .get();

            // First correct answer gets 1 point, others get 0.5
            const isFirstCorrect = correctAnswersSnapshot.docs.length === 0;
            const pointsToAdd = isFirstCorrect ? 1.0 : 0.5;

            // Update player's score (use set with merge to handle new players)
            const playerRef = db
              .collection("rooms")
              .doc(roomCode)
              .collection("players")
              .doc(playerId);

            const playerDoc = await playerRef.get();
            if (playerDoc.exists) {
              await playerRef.update({
                score: FieldValue.increment(pointsToAdd),
              });
            } else {
              console.warn(`Player document ${playerId} not found in room ${roomCode}, skipping score update`);
            }
          }
        }

        await messageRef.update(updateData);
      }

      return {
        isCorrect: result.isCorrect,
        confidence: result.confidence,
        reasoning: result.explanation,
      };
    } catch (error) {
      console.error("Error evaluating answer:", error);
      throw new HttpsError(
        "internal",
        "Failed to evaluate answer with AI"
      );
    }
  }
);

/**
 * Evaluate an answer using Claude AI.
 */
async function evaluateAnswer(question, expectedAnswer, playerAnswer) {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn("ANTHROPIC_API_KEY not set, falling back to simple comparison");
    return simpleEvaluation(expectedAnswer, playerAnswer);
  }

  try {
    const message = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 256,
      messages: [
        {
          role: "user",
          content: `You are evaluating quiz answers. Determine if the player's answer is semantically correct, even if not an exact match.

Question: ${question}
Expected Answer: ${expectedAnswer}
Player Answer: ${playerAnswer}

Respond with JSON only in this format:
{"isCorrect": true/false, "confidence": 0.0-1.0, "explanation": "brief reason"}

Be lenient with:
- Spelling variations
- Synonyms
- Different phrasing
- Abbreviations
- Character aliases and alternative names (e.g., "Edmond Dantès" = "Count of Monte Cristo", birth name = title/known name)
- The same person, character, or entity referred to by a different name (maiden name, pen name, stage name, nickname, title, etc.)

Be strict about:
- Fundamentally wrong answers
- Different concepts
- Unrelated responses`,
        },
      ],
    });

    const responseText =
      message.content[0].type === "text" ? message.content[0].text : "";

    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const result = JSON.parse(jsonMatch[0]);
      return {
        isCorrect: Boolean(result.isCorrect),
        confidence: Number(result.confidence) || 0.5,
        explanation: String(result.explanation) || "",
      };
    }

    return simpleEvaluation(expectedAnswer, playerAnswer);
  } catch (error) {
    console.error("AI evaluation error:", error);
    return simpleEvaluation(expectedAnswer, playerAnswer);
  }
}

/**
 * Simple string comparison fallback when AI is unavailable.
 */
function simpleEvaluation(expectedAnswer, playerAnswer) {
  const normalizedExpected = expectedAnswer.toLowerCase().trim();
  const normalizedPlayer = playerAnswer.toLowerCase().trim();

  const isExactMatch = normalizedExpected === normalizedPlayer;
  const containsAnswer =
    normalizedPlayer.includes(normalizedExpected) ||
    normalizedExpected.includes(normalizedPlayer);

  if (isExactMatch) {
    return {
      isCorrect: true,
      confidence: 1.0,
      explanation: "Exact match",
    };
  }

  if (containsAnswer && Math.abs(normalizedExpected.length - normalizedPlayer.length) < 5) {
    return {
      isCorrect: true,
      confidence: 0.8,
      explanation: "Close match",
    };
  }

  return {
    isCorrect: false,
    confidence: 0.9,
    explanation: "Does not match expected answer",
  };
}
