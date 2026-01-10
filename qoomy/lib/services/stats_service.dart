import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qoomy/models/player_stats_model.dart';

class StatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PlayerStats> getPlayerStats(String userId) async {
    // Count rooms hosted by user
    final hostedRoomsSnapshot = await _firestore
        .collection('rooms')
        .where('hostId', isEqualTo: userId)
        .count()
        .get();
    final questionsAsHost = hostedRoomsSnapshot.count ?? 0;

    // Count rooms where user is a player (using collection group query)
    final playerDocsSnapshot = await _firestore
        .collectionGroup('players')
        .where('id', isEqualTo: userId)
        .get();
    final questionsAsPlayer = playerDocsSnapshot.docs.length;

    // Get all chat messages by user (single where clause to avoid composite index)
    final allMessagesSnapshot = await _firestore
        .collectionGroup('chat')
        .where('playerId', isEqualTo: userId)
        .get();

    // Filter answers locally
    final answers = allMessagesSnapshot.docs.where((doc) {
      final data = doc.data();
      return data['type'] == 'answer';
    }).toList();

    int wrongAnswers = 0;
    int correctAnswersFirst = 0;
    int correctAnswersNotFirst = 0;
    double totalPoints = 0.0;

    // Process each answer to determine if it was first correct or not
    for (final answerDoc in answers) {
      final data = answerDoc.data();
      final isCorrect = data['isCorrect'] as bool?;

      if (isCorrect == null) {
        // Not yet evaluated, skip
        continue;
      }

      if (!isCorrect) {
        wrongAnswers++;
        continue;
      }

      // It's a correct answer - check if it was first
      // Get the room code from the path: rooms/{roomCode}/chat/{messageId}
      final roomCode = answerDoc.reference.parent.parent?.id;
      if (roomCode == null) continue;

      // Get the timestamp of this answer
      final answerSentAt = (data['sentAt'] as Timestamp?)?.toDate();
      if (answerSentAt == null) continue;

      // Get all messages in this room to check for earlier correct answers
      final roomChatSnapshot = await _firestore
          .collection('rooms')
          .doc(roomCode)
          .collection('chat')
          .get();

      // Count correct answers sent before this one
      int earlierCorrectCount = 0;
      for (final chatDoc in roomChatSnapshot.docs) {
        final chatData = chatDoc.data();
        final chatIsCorrect = chatData['isCorrect'] as bool?;
        if (chatIsCorrect != true) continue;

        final chatSentAt = (chatData['sentAt'] as Timestamp?)?.toDate();
        if (chatSentAt == null) continue;

        if (chatSentAt.isBefore(answerSentAt)) {
          earlierCorrectCount++;
        }
      }

      if (earlierCorrectCount == 0) {
        // This was the first correct answer
        correctAnswersFirst++;
        totalPoints += 1.0;
      } else {
        // Not the first correct answer
        correctAnswersNotFirst++;
        totalPoints += 0.5;
      }
    }

    return PlayerStats(
      questionsAsHost: questionsAsHost,
      questionsAsPlayer: questionsAsPlayer,
      wrongAnswers: wrongAnswers,
      correctAnswersFirst: correctAnswersFirst,
      correctAnswersNotFirst: correctAnswersNotFirst,
      totalPoints: totalPoints,
    );
  }
}
