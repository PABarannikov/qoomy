import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qoomy/services/room_service.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/providers/team_provider.dart';

final roomServiceProvider = Provider<RoomService>((ref) => RoomService());

final roomProvider = StreamProvider.family<RoomModel?, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).roomStream(roomCode);
});

final playersProvider = StreamProvider.family<List<Player>, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).playersStream(roomCode);
});

final chatProvider = StreamProvider.family<List<ChatMessage>, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).chatStream(roomCode);
});

/// Provider for rooms hosted by a user
final userHostedRoomsProvider = StreamProvider.family<List<RoomModel>, String>((ref, userId) {
  return ref.watch(roomServiceProvider).userHostedRoomsStream(userId);
});

/// Provider for rooms joined by a user (as player)
final userJoinedRoomsProvider = StreamProvider.family<List<RoomModel>, String>((ref, userId) {
  return ref.watch(roomServiceProvider).userJoinedRoomsStream(userId);
});

/// Provider for unread message count of a specific room
final unreadCountProvider = StreamProvider.family<int, ({String roomCode, String userId})>((ref, params) {
  return ref.watch(roomServiceProvider).unreadCountStream(params.roomCode, params.userId);
});

/// Provider for total unread message count across all user's rooms
final totalUnreadCountProvider = StreamProvider.family<int, String>((ref, userId) {
  return ref.watch(roomServiceProvider).totalUnreadCountStream(userId);
});

/// Provider to check if a room has at least one correct answer
final hasCorrectAnswerProvider = StreamProvider.family<bool, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).hasCorrectAnswerStream(roomCode);
});

/// Provider to check if user has revealed the correct answer for a room
final hasRevealedAnswerProvider = StreamProvider.family<bool, ({String roomCode, String userId})>((ref, params) {
  return ref.watch(roomServiceProvider).hasRevealedAnswerStream(params.roomCode, params.userId);
});

/// Provider for rooms from user's teams (includes all rooms where teamId matches any of user's teams)
final userTeamRoomsProvider = StreamProvider.family<List<RoomModel>, String>((ref, userId) {
  final userTeamsAsync = ref.watch(userTeamsProvider(userId));

  return userTeamsAsync.when(
    data: (teams) {
      if (teams.isEmpty) {
        return Stream.value([]);
      }
      final teamIds = teams.map((t) => t.id).toList();
      return ref.watch(roomServiceProvider).userTeamRoomsStream(teamIds);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

class RoomNotifier extends StateNotifier<AsyncValue<String?>> {
  final RoomService _roomService;

  RoomNotifier(this._roomService) : super(const AsyncValue.data(null));

  Future<String?> createRoom({
    required String hostId,
    required String hostName,
    required EvaluationMode evaluationMode,
    required String question,
    required String answer,
    String? comment,
    Uint8List? imageBytes,
    String? teamId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final roomCode = await _roomService.createRoom(
        hostId: hostId,
        hostName: hostName,
        evaluationMode: evaluationMode,
        question: question,
        answer: answer,
        comment: comment,
        imageBytes: imageBytes,
        teamId: teamId,
      );
      state = AsyncValue.data(roomCode);
      return roomCode;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<bool> joinRoom({
    required String roomCode,
    required String playerId,
    required String playerName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final success = await _roomService.joinRoom(
        roomCode: roomCode.toUpperCase(),
        playerId: playerId,
        playerName: playerName,
      );
      if (success) {
        state = AsyncValue.data(roomCode.toUpperCase());
      } else {
        state = AsyncValue.error('Failed to join room', StackTrace.current);
      }
      return success;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> leaveRoom(String roomCode, String playerId) async {
    await _roomService.leaveRoom(roomCode, playerId);
    state = const AsyncValue.data(null);
  }

  Future<void> startGame(String roomCode) async {
    await _roomService.startGame(roomCode);
  }

  Future<void> endGame(String roomCode) async {
    await _roomService.endGame(roomCode);
  }

  Future<void> markPlayerAnswer(String roomCode, String playerId, bool isCorrect) async {
    await _roomService.markPlayerAnswer(roomCode, playerId, isCorrect);
  }

  Future<void> submitPlayerAnswer(String roomCode, String playerId, String answer) async {
    await _roomService.submitPlayerAnswer(roomCode, playerId, answer);
  }

  Future<void> sendMessage({
    required String roomCode,
    required String playerId,
    required String playerName,
    required String text,
    required MessageType type,
    String? replyToId,
    String? replyToText,
    String? replyToPlayerName,
  }) async {
    await _roomService.sendMessage(
      roomCode: roomCode,
      playerId: playerId,
      playerName: playerName,
      text: text,
      type: type,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToPlayerName: replyToPlayerName,
    );
  }

  Future<void> markMessageAnswer({
    required String roomCode,
    required String messageId,
    required bool isCorrect,
  }) async {
    await _roomService.markMessageAnswer(
      roomCode: roomCode,
      messageId: messageId,
      isCorrect: isCorrect,
    );
  }

  Future<void> revealAnswer({
    required String roomCode,
    required String userId,
  }) async {
    await _roomService.revealAnswer(roomCode, userId);
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

final roomNotifierProvider =
    StateNotifierProvider<RoomNotifier, AsyncValue<String?>>((ref) {
  return RoomNotifier(ref.watch(roomServiceProvider));
});
