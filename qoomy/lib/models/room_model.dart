import 'package:cloud_firestore/cloud_firestore.dart';

enum RoomStatus { waiting, playing, finished }
enum EvaluationMode { manual, ai }

class Player {
  final String id;
  final String name;
  final int score;
  final DateTime joinedAt;
  final String? answer;
  final bool? isCorrect;

  Player({
    required this.id,
    required this.name,
    this.score = 0,
    required this.joinedAt,
    this.answer,
    this.isCorrect,
  });

  factory Player.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Player(
      id: data['id'] ?? doc.id,
      name: data['name'] ?? '',
      score: data['score'] ?? 0,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answer: data['answer'],
      isCorrect: data['isCorrect'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'score': score,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'answer': answer,
      'isCorrect': isCorrect,
    };
  }

  Player copyWith({
    String? id,
    String? name,
    int? score,
    DateTime? joinedAt,
    String? answer,
    bool? isCorrect,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      score: score ?? this.score,
      joinedAt: joinedAt ?? this.joinedAt,
      answer: answer ?? this.answer,
      isCorrect: isCorrect ?? this.isCorrect,
    );
  }
}

class RoomModel {
  final String code;
  final String hostId;
  final String hostName;
  final RoomStatus status;
  final EvaluationMode evaluationMode;
  final String question;
  final String answer;
  final String? comment;
  final String? imageUrl;
  final DateTime createdAt;
  final List<Player> players;

  RoomModel({
    required this.code,
    required this.hostId,
    required this.hostName,
    this.status = RoomStatus.waiting,
    this.evaluationMode = EvaluationMode.manual,
    required this.question,
    required this.answer,
    this.comment,
    this.imageUrl,
    required this.createdAt,
    this.players = const [],
  });

  factory RoomModel.fromFirestore(DocumentSnapshot doc, List<Player> players) {
    final data = doc.data() as Map<String, dynamic>;
    return RoomModel(
      code: doc.id,
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '',
      status: RoomStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => RoomStatus.waiting,
      ),
      evaluationMode: EvaluationMode.values.firstWhere(
        (e) => e.name == data['evaluationMode'],
        orElse: () => EvaluationMode.manual,
      ),
      question: data['question'] ?? '',
      answer: data['answer'] ?? '',
      comment: data['comment'],
      imageUrl: data['imageUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      players: players,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'hostId': hostId,
      'hostName': hostName,
      'status': status.name,
      'evaluationMode': evaluationMode.name,
      'question': question,
      'answer': answer,
      'comment': comment,
      'imageUrl': imageUrl,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  bool get canStart => players.isNotEmpty && status == RoomStatus.waiting;

  RoomModel copyWith({
    String? code,
    String? hostId,
    String? hostName,
    RoomStatus? status,
    EvaluationMode? evaluationMode,
    String? question,
    String? answer,
    String? comment,
    String? imageUrl,
    DateTime? createdAt,
    List<Player>? players,
  }) {
    return RoomModel(
      code: code ?? this.code,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      status: status ?? this.status,
      evaluationMode: evaluationMode ?? this.evaluationMode,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      comment: comment ?? this.comment,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      players: players ?? this.players,
    );
  }
}
