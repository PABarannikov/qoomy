import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { evaluateAnswer } from "./ai_evaluator";

admin.initializeApp();

export const evaluateAnswerWithAI = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated to use this function"
      );
    }

    const { question, expectedAnswer, playerAnswer, roomCode, questionId, playerId } = data;

    if (!question || !expectedAnswer || !playerAnswer) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required fields: question, expectedAnswer, playerAnswer"
      );
    }

    try {
      const result = await evaluateAnswer(question, expectedAnswer, playerAnswer);

      if (roomCode && questionId && playerId) {
        await admin.firestore()
          .collection("games")
          .doc(roomCode)
          .collection("questions")
          .doc(questionId)
          .collection("answers")
          .doc(playerId)
          .update({
            aiSuggestion: result.isCorrect,
          });
      }

      return result;
    } catch (error) {
      console.error("Error evaluating answer:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to evaluate answer with AI"
      );
    }
  }
);

export const cleanupOldRooms = functions.pubsub
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
