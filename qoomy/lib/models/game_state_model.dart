import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qoomy/models/question_model.dart';

enum GameStatus { asking, answering, revealing, leaderboard }

class GameStateModel {
  final String roomCode;
  final int currentQuestion;
  final int totalQuestions;
  final GameStatus status;
  final List<QuestionModel> questions;

  GameStateModel({
    required this.roomCode,
    this.currentQuestion = 0,
    this.totalQuestions = 0,
    this.status = GameStatus.asking,
    this.questions = const [],
  });

  factory GameStateModel.fromFirestore(DocumentSnapshot doc, List<QuestionModel> questions) {
    final data = doc.data() as Map<String, dynamic>;
    return GameStateModel(
      roomCode: doc.id,
      currentQuestion: data['currentQuestion'] ?? 0,
      totalQuestions: data['totalQuestions'] ?? 0,
      status: GameStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => GameStatus.asking,
      ),
      questions: questions,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'currentQuestion': currentQuestion,
      'totalQuestions': totalQuestions,
      'status': status.name,
    };
  }

  QuestionModel? get activeQuestion {
    if (questions.isEmpty || currentQuestion >= questions.length) {
      return null;
    }
    return questions[currentQuestion];
  }

  bool get isFinished => currentQuestion >= totalQuestions && totalQuestions > 0;

  GameStateModel copyWith({
    String? roomCode,
    int? currentQuestion,
    int? totalQuestions,
    GameStatus? status,
    List<QuestionModel>? questions,
  }) {
    return GameStateModel(
      roomCode: roomCode ?? this.roomCode,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      status: status ?? this.status,
      questions: questions ?? this.questions,
    );
  }
}
