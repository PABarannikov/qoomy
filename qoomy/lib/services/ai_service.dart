import 'package:cloud_functions/cloud_functions.dart';

class AiService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Evaluates a player's answer against the correct answer using AI
  /// Returns a confidence score (0.0 to 1.0) and suggestion (true/false)
  Future<AiEvaluation> evaluateAnswer({
    required String question,
    required String correctAnswer,
    required String playerAnswer,
  }) async {
    try {
      final callable = _functions.httpsCallable('evaluateAnswer');
      final result = await callable.call({
        'question': question,
        'correctAnswer': correctAnswer,
        'playerAnswer': playerAnswer,
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
        reasoning: 'AI evaluation unavailable',
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
