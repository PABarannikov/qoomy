import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qoomy/models/game_state_model.dart';
import 'package:qoomy/models/question_model.dart';

class GameService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _gamesCollection =>
      _firestore.collection('games');

  CollectionReference<Map<String, dynamic>> get _roomsCollection =>
      _firestore.collection('rooms');

  Stream<GameStateModel?> gameStateStream(String roomCode) {
    return _gamesCollection.doc(roomCode).snapshots().asyncMap((doc) async {
      if (!doc.exists) return null;

      final questionsSnapshot = await _gamesCollection
          .doc(roomCode)
          .collection('questions')
          .orderBy('askedAt')
          .get();

      final questions = await Future.wait(
        questionsSnapshot.docs.map((qDoc) async {
          final answersSnapshot = await qDoc.reference
              .collection('answers')
              .orderBy('answeredAt')
              .get();

          final answers = answersSnapshot.docs
              .map((aDoc) => Answer.fromFirestore(aDoc))
              .toList();

          return QuestionModel.fromFirestore(qDoc, answers);
        }),
      );

      return GameStateModel.fromFirestore(doc, questions);
    });
  }

  Future<String> askQuestion({
    required String roomCode,
    required String questionText,
    String? expectedAnswer,
  }) async {
    final question = QuestionModel(
      id: '',
      text: questionText,
      expectedAnswer: expectedAnswer,
      askedAt: DateTime.now(),
    );

    final docRef = await _gamesCollection
        .doc(roomCode)
        .collection('questions')
        .add(question.toFirestore());

    await _gamesCollection.doc(roomCode).update({
      'totalQuestions': FieldValue.increment(1),
      'status': 'answering',
    });

    return docRef.id;
  }

  Future<void> submitAnswer({
    required String roomCode,
    required String questionId,
    required String playerId,
    required String answer,
  }) async {
    final answerModel = Answer(
      playerId: playerId,
      answer: answer,
      answeredAt: DateTime.now(),
    );

    await _gamesCollection
        .doc(roomCode)
        .collection('questions')
        .doc(questionId)
        .collection('answers')
        .doc(playerId)
        .set(answerModel.toFirestore());
  }

  Future<void> markAnswer({
    required String roomCode,
    required String questionId,
    required String playerId,
    required bool isCorrect,
    required int points,
  }) async {
    await _gamesCollection
        .doc(roomCode)
        .collection('questions')
        .doc(questionId)
        .collection('answers')
        .doc(playerId)
        .update({
      'isCorrect': isCorrect,
      'points': points,
    });

    if (isCorrect && points > 0) {
      await _roomsCollection
          .doc(roomCode)
          .collection('players')
          .doc(playerId)
          .update({
        'score': FieldValue.increment(points),
      });
    }
  }

  Future<void> setAiSuggestion({
    required String roomCode,
    required String questionId,
    required String playerId,
    required bool suggestion,
  }) async {
    await _gamesCollection
        .doc(roomCode)
        .collection('questions')
        .doc(questionId)
        .collection('answers')
        .doc(playerId)
        .update({
      'aiSuggestion': suggestion,
    });
  }

  Future<void> revealAnswers(String roomCode) async {
    await _gamesCollection.doc(roomCode).update({
      'status': 'revealing',
    });
  }

  Future<void> showLeaderboard(String roomCode) async {
    await _gamesCollection.doc(roomCode).update({
      'status': 'leaderboard',
    });
  }

  Future<void> nextQuestion(String roomCode) async {
    await _gamesCollection.doc(roomCode).update({
      'currentQuestion': FieldValue.increment(1),
      'status': 'asking',
    });
  }

  int calculatePoints(DateTime questionAskedAt, DateTime answeredAt, int maxPoints) {
    final elapsed = answeredAt.difference(questionAskedAt).inMilliseconds;
    const maxTime = 30000;
    
    if (elapsed >= maxTime) return maxPoints ~/ 4;
    
    final ratio = 1 - (elapsed / maxTime);
    return (maxPoints * (0.25 + 0.75 * ratio)).round();
  }
}
