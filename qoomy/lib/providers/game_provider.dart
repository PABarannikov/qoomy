import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qoomy/services/game_service.dart';
import 'package:qoomy/models/game_state_model.dart';

final gameServiceProvider = Provider<GameService>((ref) => GameService());

final gameStateProvider = StreamProvider.family<GameStateModel?, String>((ref, roomCode) {
  return ref.watch(gameServiceProvider).gameStateStream(roomCode);
});

class GameNotifier extends StateNotifier<AsyncValue<void>> {
  final GameService _gameService;

  GameNotifier(this._gameService) : super(const AsyncValue.data(null));

  Future<String?> askQuestion({
    required String roomCode,
    required String questionText,
    String? expectedAnswer,
  }) async {
    state = const AsyncValue.loading();
    try {
      final questionId = await _gameService.askQuestion(
        roomCode: roomCode,
        questionText: questionText,
        expectedAnswer: expectedAnswer,
      );
      state = const AsyncValue.data(null);
      return questionId;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> submitAnswer({
    required String roomCode,
    required String questionId,
    required String playerId,
    required String answer,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _gameService.submitAnswer(
        roomCode: roomCode,
        questionId: questionId,
        playerId: playerId,
        answer: answer,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markAnswer({
    required String roomCode,
    required String questionId,
    required String playerId,
    required bool isCorrect,
    required int points,
  }) async {
    try {
      await _gameService.markAnswer(
        roomCode: roomCode,
        questionId: questionId,
        playerId: playerId,
        isCorrect: isCorrect,
        points: points,
      );
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> revealAnswers(String roomCode) async {
    await _gameService.revealAnswers(roomCode);
  }

  Future<void> showLeaderboard(String roomCode) async {
    await _gameService.showLeaderboard(roomCode);
  }

  Future<void> nextQuestion(String roomCode) async {
    await _gameService.nextQuestion(roomCode);
  }

  int calculatePoints(DateTime questionAskedAt, DateTime answeredAt) {
    return _gameService.calculatePoints(questionAskedAt, answeredAt, 1000);
  }
}

final gameNotifierProvider =
    StateNotifierProvider<GameNotifier, AsyncValue<void>>((ref) {
  return GameNotifier(ref.watch(gameServiceProvider));
});
