import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qoomy/services/room_service.dart';
import 'package:qoomy/services/ai_service.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/providers/team_provider.dart';

final roomServiceProvider = Provider<RoomService>((ref) => RoomService());
final aiServiceProvider = Provider<AiService>((ref) => AiService());

/// Pagination state for home screen rooms list
class RoomPaginationState {
  final int limit;
  final bool hasMore;
  final bool isLoadingMore;

  const RoomPaginationState({
    this.limit = 25,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  RoomPaginationState copyWith({
    int? limit,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return RoomPaginationState(
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Notifier to manage room pagination
class RoomPaginationNotifier extends StateNotifier<RoomPaginationState> {
  static const int _pageSize = 25;

  RoomPaginationNotifier() : super(const RoomPaginationState());

  void loadMore() {
    if (!state.hasMore || state.isLoadingMore) return;

    final newLimit = state.limit + _pageSize;
    print('[Pagination] Loading more: ${state.limit} -> $newLimit');

    state = state.copyWith(
      isLoadingMore: true,
      limit: newLimit,
    );

    // Reset loading state after a short delay
    // The actual data loading happens through the providers
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        state = state.copyWith(isLoadingMore: false);
      }
    });
  }

  void setHasMore(bool hasMore) {
    if (state.hasMore != hasMore) {
      state = state.copyWith(hasMore: hasMore);
    }
  }

  void reset() {
    state = const RoomPaginationState();
  }
}

final roomPaginationProvider =
    StateNotifierProvider<RoomPaginationNotifier, RoomPaginationState>((ref) {
  return RoomPaginationNotifier();
});

final roomProvider = StreamProvider.family<RoomModel?, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).roomStream(roomCode);
});

final playersProvider = StreamProvider.family<List<Player>, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).playersStream(roomCode);
});

final chatProvider = StreamProvider.family<List<ChatMessage>, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).chatStream(roomCode);
});

/// Provider for rooms hosted by a user (with optional limit for pagination)
final userHostedRoomsProvider = StreamProvider.family<List<RoomModel>, ({String userId, int? limit})>((ref, params) {
  return ref.watch(roomServiceProvider).userHostedRoomsStream(params.userId, limit: params.limit);
});

/// Provider for rooms joined by a user (as player, with optional limit for pagination)
final userJoinedRoomsProvider = StreamProvider.family<List<RoomModel>, ({String userId, int? limit})>((ref, params) {
  return ref.watch(roomServiceProvider).userJoinedRoomsStream(params.userId, limit: params.limit);
});

/// Provider for unread message count of a specific room
final unreadCountProvider = StreamProvider.family<int, ({String roomCode, String userId})>((ref, params) {
  return ref.watch(roomServiceProvider).unreadCountStream(params.roomCode, params.userId);
});

/// Provider for total unread message count across all user's rooms (hosted, joined, AND team rooms)
/// Note: Uses no limit to count ALL rooms for badge accuracy
final totalUnreadCountProvider = StreamProvider.family<int, String>((ref, userId) {
  final hostedRoomsAsync = ref.watch(userHostedRoomsProvider((userId: userId, limit: null)));
  final joinedRoomsAsync = ref.watch(userJoinedRoomsProvider((userId: userId, limit: null)));
  final teamRoomsAsync = ref.watch(userTeamRoomsProvider((userId: userId, limit: null)));
  final roomService = ref.watch(roomServiceProvider);

  // Use valueOrNull to get available data immediately, even during loading
  // This fixes release build issue where nested .when() loading states never update
  final hostedRooms = hostedRoomsAsync.valueOrNull ?? [];
  final joinedRooms = joinedRoomsAsync.valueOrNull ?? [];
  final teamRooms = teamRoomsAsync.valueOrNull ?? [];

  // Deduplicate rooms by code
  final hostedCodes = hostedRooms.map((r) => r.code).toSet();
  final joinedCodes = joinedRooms.map((r) => r.code).toSet();

  // Get unique team rooms (not in hosted or joined)
  final uniqueTeamRooms = teamRooms
      .where((r) => !hostedCodes.contains(r.code) && !joinedCodes.contains(r.code))
      .toList();

  // Combine all unique room codes
  final allRoomCodes = <String>{
    ...hostedCodes,
    ...joinedCodes,
    ...uniqueTeamRooms.map((r) => r.code),
  };

  if (allRoomCodes.isEmpty) {
    return Stream.value(0);
  }

  // Create a stream that combines unread counts from all rooms
  return roomService.combinedUnreadCountStream(userId, allRoomCodes.toList());
});

/// Provider to check if a room has at least one correct answer
final hasCorrectAnswerProvider = StreamProvider.family<bool, String>((ref, roomCode) {
  return ref.watch(roomServiceProvider).hasCorrectAnswerStream(roomCode);
});

/// Provider to check if user has revealed the correct answer for a room
final hasRevealedAnswerProvider = StreamProvider.family<bool, ({String roomCode, String userId})>((ref, params) {
  return ref.watch(roomServiceProvider).hasRevealedAnswerStream(params.roomCode, params.userId);
});

/// Provider to check if user has opened a room (has entry in roomReads)
final hasOpenedRoomProvider = StreamProvider.family<bool, ({String roomCode, String userId})>((ref, params) {
  return ref.watch(roomServiceProvider).hasOpenedRoomStream(params.roomCode, params.userId);
});

/// Provider for count of rooms where user is a player (or team member) but hasn't opened yet
final unseenPlayerRoomsCountProvider = StreamProvider.family<int, String>((ref, userId) {
  final userTeamsAsync = ref.watch(userTeamsProvider(userId));
  final roomService = ref.watch(roomServiceProvider);

  return userTeamsAsync.when(
    data: (teams) {
      final teamIds = teams.map((t) => t.id).toList();
      return roomService.unseenPlayerRoomsCountStream(userId, teamIds);
    },
    loading: () => Stream.value(0),
    error: (_, __) => roomService.unseenPlayerRoomsCountStream(userId, []),
  );
});

/// Provider for rooms from user's teams (includes all rooms where teamId matches any of user's teams)
final userTeamRoomsProvider = StreamProvider.family<List<RoomModel>, ({String userId, int? limit})>((ref, params) {
  final userTeamsAsync = ref.watch(userTeamsProvider(params.userId));

  return userTeamsAsync.when(
    data: (teams) {
      if (teams.isEmpty) {
        return Stream.value([]);
      }
      final teamIds = teams.map((t) => t.id).toList();
      return ref.watch(roomServiceProvider).userTeamRoomsStream(teamIds, limit: params.limit);
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

  /// Sends a message to the room chat. Returns the message document ID.
  Future<String> sendMessage({
    required String roomCode,
    required String playerId,
    required String playerName,
    required String text,
    required MessageType type,
    String? replyToId,
    String? replyToText,
    String? replyToPlayerName,
  }) async {
    return _roomService.sendMessage(
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
