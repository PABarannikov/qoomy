"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupOldRooms = exports.evaluateAnswerWithAI = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const ai_evaluator_1 = require("./ai_evaluator");
admin.initializeApp();
exports.evaluateAnswerWithAI = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated to use this function");
    }
    const { question, expectedAnswer, playerAnswer, roomCode, messageId, playerId } = data;
    if (!question || !expectedAnswer || !playerAnswer) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields: question, expectedAnswer, playerAnswer");
    }
    try {
        const result = await (0, ai_evaluator_1.evaluateAnswer)(question, expectedAnswer, playerAnswer);
        // Update the chat message with AI evaluation result
        if (roomCode && messageId) {
            const messageRef = admin.firestore()
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
                    const correctAnswersSnapshot = await admin.firestore()
                        .collection("rooms")
                        .doc(roomCode)
                        .collection("chat")
                        .where("isCorrect", "==", true)
                        .get();
                    // First correct answer gets 1 point, others get 0.5
                    const isFirstCorrect = correctAnswersSnapshot.docs.length === 0;
                    const pointsToAdd = isFirstCorrect ? 1.0 : 0.5;
                    // Update player's score
                    await admin.firestore()
                        .collection("rooms")
                        .doc(roomCode)
                        .collection("players")
                        .doc(playerId)
                        .update({
                        score: admin.firestore.FieldValue.increment(pointsToAdd),
                    });
                }
            }
            await messageRef.update(updateData);
        }
        return {
            isCorrect: result.isCorrect,
            confidence: result.confidence,
            reasoning: result.explanation,
        };
    }
    catch (error) {
        console.error("Error evaluating answer:", error);
        throw new functions.https.HttpsError("internal", "Failed to evaluate answer with AI");
    }
});
exports.cleanupOldRooms = functions.pubsub
    .schedule("every 24 hours")
    .onRun(async () => {
    const db = admin.firestore();
    const cutoff = new Date();
    cutoff.setHours(cutoff.getHours() - 24);
    const oldRooms = await db
        .collection("rooms")
        .where("createdAt", "<", cutoff)
        .where("status", "==", "finished")
        .get();
    const batch = db.batch();
    for (const doc of oldRooms.docs) {
        const playersSnapshot = await doc.ref.collection("players").get();
        for (const playerDoc of playersSnapshot.docs) {
            batch.delete(playerDoc.ref);
        }
        batch.delete(doc.ref);
        const gameDoc = db.collection("games").doc(doc.id);
        const questionsSnapshot = await gameDoc.collection("questions").get();
        for (const qDoc of questionsSnapshot.docs) {
            const answersSnapshot = await qDoc.ref.collection("answers").get();
            for (const aDoc of answersSnapshot.docs) {
                batch.delete(aDoc.ref);
            }
            batch.delete(qDoc.ref);
        }
        batch.delete(gameDoc);
    }
    await batch.commit();
    console.log(`Cleaned up ${oldRooms.size} old rooms`);
    return null;
});
//# sourceMappingURL=index.js.map