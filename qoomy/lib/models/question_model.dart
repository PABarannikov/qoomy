import 'package:cloud_firestore/cloud_firestore.dart';

class Answer {
  final String playerId;
  final String answer;
  final DateTime answeredAt;
  final bool? isCorrect;
  final bool? aiSuggestion;
  final int points;

  Answer({
    required this.playerId,
    required this.answer,
    required this.answeredAt,
    this.isCorrect,
    this.aiSuggestion,
    this.points = 0,
  });

  factory Answer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Answer(
      playerId: doc.id,
      answer: data['answer'] ?? '',
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isCorrect: data['isCorrect'],
      aiSuggestion: data['aiSuggestion'],
      points: data['points'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'answer': answer,
      'answeredAt': Timestamp.fromDate(answeredAt),
      'isCorrect': isCorrect,
      'aiSuggestion': aiSuggestion,
      'points': points,
    };
  }

  Answer copyWith({
    String? playerId,
    String? answer,
    DateTime? answeredAt,
    bool? isCorrect,
    bool? aiSuggestion,
    int? points,
  }) {
    return Answer(
      playerId: playerId ?? this.playerId,
      answer: answer ?? this.answer,
      answeredAt: answeredAt ?? this.answeredAt,
      isCorrect: isCorrect ?? this.isCorrect,
      aiSuggestion: aiSuggestion ?? this.aiSuggestion,
      points: points ?? this.points,
    );
  }
}

class QuestionModel {
  final String id;
  final String text;
  final String? expectedAnswer;
  final DateTime askedAt;
  final List<Answer> answers;

  QuestionModel({
    required this.id,
    required this.text,
    this.expectedAnswer,
    required this.askedAt,
    this.answers = const [],
  });

  factory QuestionModel.fromFirestore(DocumentSnapshot doc, List<Answer> answers) {
    final data = doc.data() as Map<String, dynamic>;
    return QuestionModel(
      id: doc.id,
      text: data['text'] ?? '',
      expectedAnswer: data['expectedAnswer'],
      askedAt: (data['askedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answers: answers,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'expectedAnswer': expectedAnswer,
      'askedAt': Timestamp.fromDate(askedAt),
    };
  }

  int get answeredCount => answers.length;
  int get correctCount => answers.where((a) => a.isCorrect == true).length;
  int get pendingCount => answers.where((a) => a.isCorrect == null).length;

  QuestionModel copyWith({
    String? id,
    String? text,
    String? expectedAnswer,
    DateTime? askedAt,
    List<Answer>? answers,
  }) {
    return QuestionModel(
      id: id ?? this.id,
      text: text ?? this.text,
      expectedAnswer: expectedAnswer ?? this.expectedAnswer,
      askedAt: askedAt ?? this.askedAt,
      answers: answers ?? this.answers,
    );
  }
}
