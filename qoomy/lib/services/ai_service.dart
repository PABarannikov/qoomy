import 'package:cloud_functions/cloud_functions.dart';

class AiService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Evaluates a player's answer against the correct answer using AI.
  /// The Cloud Function will update the message document with the result.
  /// If confidence is >= 0.8, the answer will be auto-marked.
  Future<AiEvaluation> evaluateAnswer({
    required String question,
    required String expectedAnswer,
    required String playerAnswer,
    required String roomCode,
    required String messageId,
    required String playerId,
  }) async {
    try {
      final callable = _functions.httpsCallable('evaluateAnswerWithAI');
      final result = await callable.call({
        'question': question,
        'expectedAnswer': expectedAnswer,
        'playerAnswer': playerAnswer,
        'roomCode': roomCode,
        'messageId': messageId,
        'playerId': playerId,
      });

      final data = result.data as Map<String, dynamic>;
      return AiEvaluation(
        isCorrect: data['isCorrect'] as bool,
        confidence: (data['confidence'] as num).toDouble(),
        reasoning: data['reasoning'] as String?,
      );
    } catch (e) {
      // Return null evaluation on error - host will decide manually
      return AiEvaluation(
        isCorrect: null,
        confidence: 0.0,
        reasoning: 'AI evaluation unavailable: $e',
      );
    }
  }
}

class AiEvaluation {
  final bool? isCorrect;
  final double confidence;
  final String? reasoning;

  AiEvaluation({
    required this.isCorrect,
    required this.confidence,
    this.reasoning,
  });

  bool get isHighConfidence => confidence >= 0.8;
}
