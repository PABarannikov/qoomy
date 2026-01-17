const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

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
 * Calculate total unread message count for a user across all their rooms.
 */
async function calculateTotalUnreadCount(userId) {
  let totalUnread = 0;

  try {
    // Get user's last read timestamps
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

    // Get rooms where user is a player
    const playerRoomsSnapshot = await db
      .collectionGroup("players")
      .where("id", "==", userId)
      .get();

    const roomCodes = new Set();

    // Add hosted rooms
    hostedRoomsSnapshot.docs.forEach((doc) => {
      roomCodes.add(doc.id);
    });

    // Add joined rooms
    for (const playerDoc of playerRoomsSnapshot.docs) {
      const roomCode = playerDoc.ref.parent.parent?.id;
      if (roomCode) {
        roomCodes.add(roomCode);
      }
    }

    // Get user's teams for team rooms
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

    // Calculate unread for each room
    for (const roomCode of roomCodes) {
      const lastRead = lastReadMap.get(roomCode);

      let query = db.collection("rooms").doc(roomCode).collection("chat");

      if (lastRead) {
        query = query.where("sentAt", ">", lastRead);
      }

      // Exclude messages sent by this user
      const chatSnapshot = await query.get();
      let unreadInRoom = 0;

      chatSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        if (data.senderId !== userId) {
          unreadInRoom++;
        }
      });

      totalUnread += unreadInRoom;
    }
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
