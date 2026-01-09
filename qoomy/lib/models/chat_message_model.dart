import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { comment, answer }

class ChatMessage {
  final String id;
  final String playerId;
  final String playerName;
  final String text;
  final MessageType type;
  final DateTime sentAt;
  final bool? isCorrect; // Only for answers, null means not marked yet
  final bool? aiSuggestion; // AI's suggestion for correctness
  final double? aiConfidence; // AI confidence score (0.0 to 1.0)
  final String? aiReasoning; // AI's reasoning for the suggestion

  ChatMessage({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.text,
    required this.type,
    required this.sentAt,
    this.isCorrect,
    this.aiSuggestion,
    this.aiConfidence,
    this.aiReasoning,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      playerId: data['playerId'] ?? '',
      playerName: data['playerName'] ?? '',
      text: data['text'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MessageType.comment,
      ),
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isCorrect: data['isCorrect'],
      aiSuggestion: data['aiSuggestion'],
      aiConfidence: (data['aiConfidence'] as num?)?.toDouble(),
      aiReasoning: data['aiReasoning'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'playerId': playerId,
      'playerName': playerName,
      'text': text,
      'type': type.name,
      'sentAt': FieldValue.serverTimestamp(),
      'isCorrect': isCorrect,
      'aiSuggestion': aiSuggestion,
      'aiConfidence': aiConfidence,
      'aiReasoning': aiReasoning,
    };
  }

  bool get hasAiSuggestion => aiSuggestion != null;
  bool get isHighConfidence => (aiConfidence ?? 0) >= 0.8;

  ChatMessage copyWith({
    String? id,
    String? playerId,
    String? playerName,
    String? text,
    MessageType? type,
    DateTime? sentAt,
    bool? isCorrect,
    bool? aiSuggestion,
    double? aiConfidence,
    String? aiReasoning,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      text: text ?? this.text,
      type: type ?? this.type,
      sentAt: sentAt ?? this.sentAt,
      isCorrect: isCorrect ?? this.isCorrect,
      aiSuggestion: aiSuggestion ?? this.aiSuggestion,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      aiReasoning: aiReasoning ?? this.aiReasoning,
    );
  }
}
