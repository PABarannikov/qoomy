const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");
const { randomUUID } = require("crypto");
const Anthropic = require("@anthropic-ai/sdk").default;

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// Initialize Anthropic client
const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY || "",
});

/**
 * Creates a custom auth token for a user.
 * Used as fallback re-authentication for devices that lose Firebase Auth sessions
 * (e.g., Samsung S25 with Play Store AAB builds).
 *
 * The client stores the userId in secure storage after sign-in.
 * On startup, if Firebase Auth returns null but secure storage has a userId,
 * the client calls this function to get a custom token and re-authenticate.
 */
exports.createCustomToken = onCall(async (request) => {
  const { userId } = request.data;

  if (!userId) {
    throw new HttpsError("invalid-argument", "userId is required");
  }

  try {
    // Verify the user actually exists in Firebase Auth
    const userRecord = await getAuth().getUser(userId);

    // Create custom token
    const customToken = await getAuth().createCustomToken(userId);

    console.log(`Created custom token for user ${userId} (${userRecord.email})`);

    return { token: customToken };
  } catch (error) {
    console.error(`Error creating custom token for ${userId}:`, error.message);

    if (error.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "User not found");
    }

    throw new HttpsError("internal", "Failed to create custom token");
  }
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

    const { question, expectedAnswer, playerAnswer, roomCode, messageId, playerId, acceptableAnswers } = request.data;

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
      const result = await evaluateAnswer(question, expectedAnswer, playerAnswer, acceptableAnswers);

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
async function evaluateAnswer(question, expectedAnswer, playerAnswer, acceptableAnswers) {
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
Expected Answer: ${expectedAnswer}${acceptableAnswers ? `\nAlso accepted (зачёт): ${acceptableAnswers}` : ""}
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

// ============================================================================
// Daily ЧГК questions: curated bank + gotquestions.online import + scheduler
//
// Model recap: a "question" is a room; a team room is a room with teamId set,
// which auto-surfaces to every team member. Auto-posted rooms use AI evaluation
// so they need no human host (members' answers are graded by evaluateAnswerWithAI).
// ============================================================================

const ADMIN_EMAIL = "pabarannikov@gmail.com";
const ROOM_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // excludes confusing chars
const GQ_BASE = "https://gotquestions.online";

/** Throws unless the caller is the admin (matches firestore.rules isAdmin()). */
function assertAdmin(request) {
  const email = request.auth && request.auth.token && request.auth.token.email;
  if (email !== ADMIN_EMAIL) {
    throw new HttpsError("permission-denied", "Admin only");
  }
}

/** Fetch JSON with a hard timeout (Node 20 global fetch). */
async function fetchJson(url, timeoutMs = 20000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        Accept: "application/json",
        "User-Agent": "QoomyBot/1.0 (+https://qoomy.online)",
      },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/** Extract numeric pack IDs from raw IDs and/or gotquestions URLs. */
function parsePackIds(packIds, packUrls) {
  const ids = new Set();
  (packIds || []).forEach((v) => {
    const m = String(v).match(/(\d+)/);
    if (m) ids.add(Number(m[1]));
  });
  (packUrls || []).forEach((u) => {
    const m = String(u).match(/pack\/(\d+)/);
    if (m) ids.add(Number(m[1]));
  });
  return Array.from(ids);
}

/** A gotquestions question we can't render as a plain text Q&A room. */
function questionHasMedia(q) {
  return Boolean(
    q.razdatkaPic || q.answerPic || q.audio || q.commentAudio || q.commentPic
  );
}

/**
 * Multi-part questions (дуплет / блиц / триплет — two or more sub-answers handed
 * in on one blank) don't fit a single-answer room, so they're never posted.
 * Detected by a leading дуплет/блиц marker or 2+ numbered answers ("1. … 2. …").
 */
function isMultiPartQuestion(text, answer) {
  if (/^\s*[«"(\[]?\s*(дуплет|блиц|триплет|перестрелка)/i.test(text || "")) {
    return true;
  }
  const parts = ((answer || "").match(/(^|[\s;(])\d+[.)]\s/g) || []).length;
  return parts >= 2;
}

/**
 * Strip editorial host-notes like "[Ведущему: …]" / "[Чтецу: …]" from question
 * text — they aren't part of the question and shouldn't be shown to players or
 * confuse the quality judge.
 */
function cleanQuestionText(text) {
  if (!text) return text;
  return text
    .replace(/\[[^\]]*(ведущему|чтецу|читающему|ведущим)[^\]]*\]/gi, " ")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Normalize a gotquestions question into a questionBank document (or null to skip). */
function normalizeGqQuestion(q, pack) {
  if (!q || q.id == null) return null;
  const text = (q.text || "").trim();
  if (!text) return null;
  const answer = (q.answer || "").trim();
  const multiPart = isMultiPartQuestion(text, answer);
  // Question handout image (shown WITH the question) — supportable. Comment
  // image/audio are explanation-only (non-blocking). Question audio / answer
  // image can't be represented, so they block posting.
  const razdatkaPic = (q.razdatkaPic || "").trim();
  const blockingMedia = Boolean((q.audio || "").trim() || (q.answerPic || "").trim());
  const imageUrl = razdatkaPic
    ? (razdatkaPic.startsWith("http") ? razdatkaPic : GQ_BASE + razdatkaPic)
    : "";
  const razdatka = (q.razdatkaText || "").trim();
  const question = cleanQuestionText(razdatka ? `${razdatka}\n\n${text}` : text);
  const authors = Array.isArray(q.authors)
    ? q.authors.map((a) => a && a.name).filter(Boolean).join(", ")
    : "";
  return {
    source: "gotquestions",
    sourceId: String(q.id),
    sourceUrl: `${GQ_BASE}/question/${q.id}`,
    packId: pack && pack.id != null
      ? Number(pack.id)
      : (q.packId != null ? Number(q.packId) : null),
    packTitle: (pack && pack.title) || q.packTitle || "",
    question,
    answer,
    zachet: (q.zachet || "").trim(),
    nezachet: (q.nezachet || "").trim(),
    comment: (q.comment || "").trim(),
    sourceText: (q.source || "").trim(),
    authors,
    hasMedia: questionHasMedia(q),
    hasImage: Boolean(razdatkaPic),
    sourceImageUrl: imageUrl,
    multiPart,
    postable: Boolean(text && answer && !multiPart && !blockingMedia),
    used: false,
    usedAt: null,
    rand: Math.random(),
    createdAt: FieldValue.serverTimestamp(),
  };
}

/** A pack exposes questions either flat or nested under tours. */
function flattenPackQuestions(pack) {
  if (Array.isArray(pack.questions) && pack.questions.length) return pack.questions;
  const out = [];
  (pack.tours || []).forEach((t) => (t.questions || []).forEach((q) => out.push(q)));
  return out;
}

/**
 * Admin-only: import ЧГК questions from gotquestions.online into questionBank.
 * Args: { packIds?: (number|string)[], packUrls?: string[], recentPages?: number, max?: number }
 * Filters out media-bearing questions and dedups by source+sourceId.
 */
exports.importGotQuestions = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    assertAdmin(request);
    const data = request.data || {};
    const maxAdd = Math.min(Number(data.max) || 1000, 5000);

    let packIds = parsePackIds(data.packIds, data.packUrls);
    const recentPages = Math.min(Number(data.recentPages) || 0, 20);
    for (let page = 1; page <= recentPages; page++) {
      try {
        const list = await fetchJson(`${GQ_BASE}/api/packs/?page=${page}`);
        (list.results || []).forEach((p) => packIds.push(Number(p.id)));
      } catch (e) {
        console.error(`packs page ${page} failed: ${e.message}`);
      }
    }
    packIds = Array.from(new Set(packIds)).slice(0, 80);
    if (packIds.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Provide packIds, packUrls, or recentPages"
      );
    }

    // Deterministic doc IDs (gq_<id>) make imports idempotent: create() skips
    // anything already mirrored without clobbering its used/rand state.
    let fetched = 0;
    let added = 0;
    let duplicates = 0;
    let skipped = 0;

    for (const pid of packIds) {
      if (added >= maxAdd) break;
      let pack;
      try {
        pack = await fetchJson(`${GQ_BASE}/api/pack/${pid}/`);
      } catch (e) {
        console.error(`pack ${pid} fetch failed: ${e.message}`);
        continue;
      }
      if (!pack) continue;
      for (const q of flattenPackQuestions(pack)) {
        if (added >= maxAdd) break;
        fetched++;
        const norm = normalizeGqQuestion(q, pack);
        if (!norm) {
          skipped++;
          continue;
        }
        try {
          await db
            .collection("questionBank")
            .doc(`gq_${norm.sourceId}`)
            .create(norm);
          added++;
        } catch (e) {
          if (e.code === 6 || /ALREADY_EXISTS/i.test(e.message || "")) {
            duplicates++;
          } else {
            console.error(`write ${norm.sourceId} failed: ${e.message}`);
            skipped++;
          }
        }
      }
    }

    console.log(
      `importGotQuestions: packs=${packIds.length}, fetched=${fetched}, added=${added}, duplicates=${duplicates}, skipped=${skipped}`
    );
    return { packs: packIds.length, fetched, added, duplicates, skipped };
  }
);

/** Generate a random 6-char room code (mirrors RoomService._generateRoomCode). */
function generateRoomCode() {
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += ROOM_CODE_CHARS[Math.floor(Math.random() * ROOM_CODE_CHARS.length)];
  }
  return code;
}

/** Find an unused room code (collision check, like the client). */
async function uniqueRoomCode() {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = generateRoomCode();
    const doc = await db.collection("rooms").doc(code).get();
    if (!doc.exists) return code;
  }
  return generateRoomCode() + generateRoomCode().slice(0, 2);
}

/**
 * Download an external image (e.g. a gotquestions handout) and store it in
 * Firebase Storage, returning a public tokenized download URL (CORS-friendly,
 * works on web + mobile). Returns null on failure.
 */
async function copyImageToStorage(sourceUrl, destPath) {
  try {
    const resp = await fetch(sourceUrl);
    if (!resp.ok) return null;
    const buf = Buffer.from(await resp.arrayBuffer());
    const contentType = resp.headers.get("content-type") || "image/jpeg";
    const token = randomUUID();
    const file = getStorage().bucket().file(destPath);
    await file.save(buf, {
      metadata: { contentType, metadata: { firebaseStorageDownloadTokens: token } },
    });
    const bucket = file.bucket.name;
    return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(destPath)}?alt=media&token=${token}`;
  } catch (e) {
    console.error(`image copy failed (${sourceUrl}): ${e.message}`);
    return null;
  }
}

/**
 * Create one AI-mode team room for a question and auto-join all team members
 * (mirrors RoomService.createRoom + _autoJoinTeamMembers). Returns the room code.
 */
async function createTeamRoomForQuestion(team, members, q) {
  const code = await uniqueRoomCode();
  const now = Timestamp.now();
  const roomRef = db.collection("rooms").doc(code);
  const batch = db.batch();
  batch.set(roomRef, {
    hostId: "system",
    hostName: team.name || "Qoomy",
    status: "playing",
    evaluationMode: "ai",
    question: q.question,
    answer: q.answer,
    comment: q.comment || null,
    zachet: q.zachet || null,
    imageUrl: q.imageUrl || null,
    teamId: team.id,
    teamName: team.name || null,
    createdAt: now,
    lastMessageAt: now,
  });
  members.forEach((m) => {
    batch.set(roomRef.collection("players").doc(m.id), {
      id: m.id,
      name: m.name || "",
      score: 0,
      joinedAt: now,
      answer: null,
      isCorrect: null,
    });
  });
  await batch.commit();
  return code;
}

const QUALITY_MODEL = "claude-sonnet-4-20250514";

function qualityPrompt(question, answer, comment) {
  return `Ты — судья качества вопросов "Что? Где? Когда?" (ЧГК) для ежедневной командной викторины.
Реши, годится ли вопрос к публикации. Ответь ТОЛЬКО JSON: {"ok": true/false, "reason": "кратко"}

Отклоняй (ok=false), если верно хотя бы одно:
- Это не вопрос: благодарности ("Автор благодарит..."), указания ведущему ("Ведущему:..."), заголовки туров/блицев, служебный текст.
- Нужен материал, которого нет в тексте: ссылка на раздаточный материал/картинку/аудио.
- Сломан, обрезан или непонятен.
- Ответ отсутствует, пустой или не проверяется по вопросу.
- Явно слабый: банальный, чрезмерно узкий/нишевый или безнадёжно неоднозначный.

Принимай (ok=true) нормальный самодостаточный вопрос ЧГК с чётким ответом — он не обязан быть шедевром, достаточно крепкого уровня.

Вопрос: ${question}
Ответ: ${answer}${comment ? `\nКомментарий: ${comment}` : ""}`;
}

/** AI quality gate: is this a good, postable ЧГК question? Fails open on error. */
async function evaluateQuestionQuality(question, answer, comment) {
  if (!process.env.ANTHROPIC_API_KEY) return { ok: true, reason: "no-key" };
  try {
    const message = await anthropic.messages.create({
      model: QUALITY_MODEL,
      max_tokens: 128,
      messages: [{ role: "user", content: qualityPrompt(question, answer, comment) }],
    });
    const text = message.content[0].type === "text" ? message.content[0].text : "";
    const json = text.match(/\{[\s\S]*\}/);
    if (json) {
      const r = JSON.parse(json[0]);
      return { ok: Boolean(r.ok), reason: String(r.reason || "") };
    }
    return { ok: true, reason: "unparseable" };
  } catch (e) {
    console.error("quality eval error:", e.message);
    return { ok: true, reason: "error" }; // fail open — don't block posting on AI hiccups
  }
}

/**
 * Pick `target` postable, unused questions that pass the AI quality gate.
 * Rejected questions are flagged used+qualityOk:false so they're never reconsidered.
 */
async function pickQualityQuestions(target) {
  const good = [];
  const seen = new Set();
  let guard = 0;
  while (good.length < target && guard < 100) {
    guard++;
    // Draw from a fresh random point in the shuffle each iteration → totally
    // random selection (not a fixed walk through rand-order).
    const snap = await db
      .collection("questionBank")
      .where("rand", ">=", Math.random())
      .orderBy("rand")
      .limit(8)
      .get();
    if (snap.empty) continue; // random point landed past the last doc — redraw
    for (const doc of snap.docs) {
      if (good.length >= target) break;
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const data = doc.data();
      if (data.postable !== true || data.used === true || data.status) continue;
      const cleanedQuestion = cleanQuestionText(data.question);
      const v = await evaluateQuestionQuality(cleanedQuestion, data.answer, data.comment);
      if (v.ok) {
        good.push({ id: doc.id, ...data, question: cleanedQuestion });
      } else {
        await doc.ref.update({
          used: true,
          usedAt: FieldValue.serverTimestamp(),
          qualityOk: false,
          status: "unsuitable",
          qualityReason: v.reason,
        });
        console.log(`quality-rejected ${doc.id}: ${v.reason}`);
      }
    }
  }
  return good;
}

/**
 * Core daily-post logic: pick 10 quality-screened bank questions and create them
 * as team rooms for every team. Idempotent per Moscow day unless force=true.
 */
async function runDailyPost({ force }) {
  // Today's date in Moscow time (YYYY-MM-DD); en-CA yields ISO-style dates.
  const today = new Date().toLocaleDateString("en-CA", {
    timeZone: "Europe/Moscow",
  });
  const setRef = db.collection("dailyQuestionSets").doc(today);

  if (!force) {
    const existing = await setRef.get();
    if (existing.exists) {
      console.log(`Daily questions already posted for ${today}`);
      return { skipped: true, date: today };
    }
  }

  const questions = await pickQualityQuestions(10);
  if (questions.length === 0) {
    console.warn("No questions passed the quality gate — nothing to post");
    return { posted: 0, date: today, reason: "empty-bank" };
  }
  if (questions.length < 10) {
    console.warn(`Only ${questions.length} questions passed the quality gate (<10)`);
  }

  // Ensure handout images are in Storage (skip if already copied by the eager
  // scrape — q.imageUrl already set). Copy once per question, reused across teams.
  for (const q of questions) {
    if (q.sourceImageUrl && !q.imageUrl) {
      q.imageUrl = await copyImageToStorage(q.sourceImageUrl, `dailyImages/${q.id}.jpg`);
    }
  }

  const teamsSnap = await db.collection("teams").get();
  let roomsCreated = 0;

  for (const teamDoc of teamsSnap.docs) {
    const team = { id: teamDoc.id, name: teamDoc.data().name };
    try {
      const membersSnap = await db
        .collection("teams")
        .doc(team.id)
        .collection("members")
        .get();
      const members = membersSnap.docs.map((m) => ({
        id: m.get("id") || m.id,
        name: m.get("name"),
      }));
      for (const q of questions) {
        await createTeamRoomForQuestion(team, members, q);
        roomsCreated++;
      }
    } catch (e) {
      console.error(`Failed posting to team ${team.id}: ${e.message}`);
    }
  }

  // Mark the posted questions so they aren't reposted.
  const markBatch = db.batch();
  questions.forEach((q) => {
    markBatch.update(db.collection("questionBank").doc(q.id), {
      used: true,
      usedAt: FieldValue.serverTimestamp(),
      qualityOk: true,
      status: "posted",
    });
  });
  await markBatch.commit();

  await setRef.set(
    {
      date: today,
      questionIds: questions.map((q) => q.id),
      teamsCount: teamsSnap.size,
      roomsCreated,
      postedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  console.log(
    `Daily post ${today}: teams=${teamsSnap.size}, questions=${questions.length}, rooms=${roomsCreated}`
  );
  return { posted: questions.length, teams: teamsSnap.size, roomsCreated, date: today };
}

/** Scheduled: post the daily set to every team at 09:00 Europe/Moscow. */
exports.postDailyTeamQuestions = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "Europe/Moscow",
    timeoutSeconds: 540,
    memory: "512MiB",
    secrets: ["ANTHROPIC_API_KEY"],
  },
  async () => {
    await runDailyPost({ force: false });
  }
);

/**
 * Admin-only manual trigger (for testing from the admin panel).
 * Defaults to force=true so a click always posts a fresh set of 10.
 * Pass { force: false } to respect the once-per-day idempotency guard.
 */
exports.postDailyTeamQuestionsNow = onCall(
  { timeoutSeconds: 540, memory: "512MiB", secrets: ["ANTHROPIC_API_KEY"] },
  async (request) => {
    assertAdmin(request);
    const force = !(request.data && request.data.force === false);
    return await runDailyPost({ force });
  }
);
