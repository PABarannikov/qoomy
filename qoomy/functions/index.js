const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
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
    const messageType = message.type || "chat";

    // Hide actual answer content in notifications - show "Ответ дан" instead
    const isAnswer = messageType === "answer";
    const messageText = isAnswer ? "Ответ дан" : (message.text || "");

    console.log(`New message in room ${roomCode} from ${senderName} (type: ${messageType})`);

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
        // Get user's FCM tokens from subcollection (iOS and Android)
        const tokensSnapshot = await db
          .collection("users")
          .doc(userId)
          .collection("fcmTokens")
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

        // Add tokens from subcollection with platform info
        const tokenPlatforms = new Map();
        for (const tokenDoc of tokensSnapshot.docs) {
          const data = tokenDoc.data();
          if (data.token) {
            tokens.add(data.token);
            tokenPlatforms.set(data.token, data.platform || "unknown");
          }
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
            platform: tokenPlatforms.get(token) || "ios",
          });
        }
      } catch (error) {
        console.error(`Error processing user ${userId}:`, error);
      }
    }

    // Send all notifications
    const sendPromises = notifications.map(async ({ token, userId, unreadCount, platform }) => {
      try {
        const payload = {
          token,
          notification: {
            title: senderName,
            body: messageText.length > 100 ? messageText.substring(0, 100) + "..." : messageText,
          },
          data: {
            roomCode,
            type: "chat_message",
          },
        };

        // Add platform-specific config
        if (platform === "android") {
          // Android: use "Qoomy" as title so it matches summary notification (same tag will replace)
          const messagePreview = messageText.length > 50 ? messageText.substring(0, 50) + "..." : messageText;
          payload.notification.title = "Qoomy";
          // unreadCount includes this message, so show +N only if there are other unread messages
          const otherUnread = unreadCount - 1;
          payload.notification.body = otherUnread > 0
            ? `${senderName}: ${messagePreview} (+${otherUnread} more)`
            : `${senderName}: ${messagePreview}`;
          payload.android = {
            notification: {
              channelId: "qoomy_messages",
              tag: "qoomy_badge", // Same tag as badge notification - will replace it
              notificationCount: unreadCount,
            },
            priority: "high",
          };
        } else {
          // iOS: use badge in aps payload
          payload.apns = {
            payload: {
              aps: {
                badge: unreadCount,
                sound: "default",
                "content-available": 1,
              },
            },
          };
        }

        await messaging.send(payload);
        console.log(`Notification sent to user ${userId} (${platform})`);
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
 * Triggered when a user's roomReads document is updated (user read messages).
 * Sends a silent notification to update the badge count on the device.
 */
exports.onRoomRead = onDocumentWritten(
  "users/{userId}/roomReads/{roomId}",
  async (event) => {
    const userId = event.params.userId;
    const roomId = event.params.roomId;

    console.log(`Room read updated for user ${userId} in room ${roomId}`);

    // Calculate new total unread count
    const unreadCount = await calculateTotalUnreadCount(userId);
    console.log(`New unread count for user ${userId}: ${unreadCount}`);

    // Get user's FCM tokens
    const tokensSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    if (tokensSnapshot.empty) {
      console.log(`No FCM tokens for user ${userId}`);
      return null;
    }

    // Send silent notification to update badge
    const sendPromises = tokensSnapshot.docs.map(async (tokenDoc) => {
      const data = tokenDoc.data();
      const token = data.token;
      const platform = data.platform || "ios";

      if (!token) return;

      try {
        const payload = {
          token,
          data: {
            type: "badge_update",
            unreadCount: String(unreadCount),
          },
        };

        if (platform === "android") {
          // Android: send data-only message to clear notifications and update badge
          payload.android = {
            priority: "high",
          };
        } else {
          // iOS: update badge silently
          payload.apns = {
            payload: {
              aps: {
                badge: unreadCount,
                "content-available": 1,
              },
            },
          };
        }

        await messaging.send(payload);
        console.log(`Badge update sent to user ${userId} (${platform}): ${unreadCount}`);
      } catch (error) {
        console.error(`Error sending badge update:`, error.message);
        if (
          error.code === "messaging/invalid-registration-token" ||
          error.code === "messaging/registration-token-not-registered"
        ) {
          await removeInvalidToken(token);
        }
      }
    });

    await Promise.all(sendPromises);
    return null;
  }
);

/**
 * Called when app goes to background on Android.
 * Clears FCM notifications and sends a summary notification with unread count.
 */
exports.onAppBackground = onCall(async (request) => {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  console.log(`App went to background for user ${userId}`);

  // Calculate total unread count
  const unreadCount = await calculateTotalUnreadCount(userId);
  console.log(`Unread count for user ${userId}: ${unreadCount}`);

  if (unreadCount === 0) {
    // No unread messages, no notification needed
    return { success: true, unreadCount: 0 };
  }

  // Get user's Android FCM tokens
  const tokensSnapshot = await db
    .collection("users")
    .doc(userId)
    .collection("fcmTokens")
    .where("platform", "==", "android")
    .get();

  if (tokensSnapshot.empty) {
    console.log(`No Android FCM tokens for user ${userId}`);
    return { success: true, unreadCount };
  }

  // Send summary notification to Android devices
  const sendPromises = tokensSnapshot.docs.map(async (tokenDoc) => {
    const token = tokenDoc.data().token;
    if (!token) return;

    try {
      const payload = {
        token,
        notification: {
          title: "Qoomy",
          body: `${unreadCount} unread message${unreadCount > 1 ? "s" : ""}`,
        },
        android: {
          notification: {
            channelId: "qoomy_messages",
            tag: "qoomy_badge", // Same tag as chat notifications - will replace them
            notificationCount: unreadCount,
          },
          priority: "high",
        },
        data: {
          type: "background_summary",
          unreadCount: String(unreadCount),
        },
      };

      await messaging.send(payload);
      console.log(`Summary notification sent to user ${userId}: ${unreadCount} unread`);
    } catch (error) {
      console.error(`Error sending summary notification:`, error.message);
      if (
        error.code === "messaging/invalid-registration-token" ||
        error.code === "messaging/registration-token-not-registered"
      ) {
        await removeInvalidToken(token);
      }
    }
  });

  await Promise.all(sendPromises);
  return { success: true, unreadCount };
});

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

IMPORTANT: Only evaluate whether the answer is factually/semantically correct. Do NOT penalize for format, language, or number of answers provided.

Be lenient with:
- Spelling variations
- Synonyms
- Different phrasing
- Abbreviations
- Character aliases and alternative names (e.g., "Edmond Dantès" = "Count of Monte Cristo", birth name = title/known name)
- The same person, character, or entity referred to by a different name (maiden name, pen name, stage name, nickname, title, etc.)
- Answers in a different language that mean the same thing (e.g., "petri dish" = "чашка Петри", "War and Peace" = "Война и мир")
- Transliterations between scripts (e.g., "билборд" = "billboard", "Москва" = "Moskva")
- Different grammatical forms of the same word: plural/singular, cases, declensions, conjugations, tenses (e.g., "крылья" = "крыло", "крыльях" = "крыло", "dogs" = "dog")

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

/**
 * One-time migration to backfill lastMessageAt for rooms that don't have it.
 * Sets lastMessageAt = createdAt for rooms missing the field.
 * Call this once via: firebase functions:shell -> migrateLastMessageAt()
 */
exports.migrateLastMessageAt = onCall(async (request) => {
  // Verify authentication (optional, remove if you want public access for migration)
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  console.log("Starting lastMessageAt migration...");

  const roomsSnapshot = await db.collection("rooms").get();
  let updated = 0;
  let skipped = 0;

  const batch = db.batch();
  const batchLimit = 500;
  let batchCount = 0;

  for (const doc of roomsSnapshot.docs) {
    const data = doc.data();

    // Skip if already has lastMessageAt
    if (data.lastMessageAt) {
      skipped++;
      continue;
    }

    // Set lastMessageAt to createdAt
    const createdAt = data.createdAt || new Date();
    batch.update(doc.ref, { lastMessageAt: createdAt });
    updated++;
    batchCount++;

    // Commit batch every 500 documents
    if (batchCount >= batchLimit) {
      await batch.commit();
      console.log(`Committed batch of ${batchCount} updates`);
      batchCount = 0;
    }
  }

  // Commit remaining updates
  if (batchCount > 0) {
    await batch.commit();
  }

  console.log(`Migration complete. Updated: ${updated}, Skipped: ${skipped}`);
  return { updated, skipped, total: roomsSnapshot.size };
});
