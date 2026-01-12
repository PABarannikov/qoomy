import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qoomy/services/team_service.dart';
import 'package:qoomy/models/team_model.dart';

final teamServiceProvider = Provider<TeamService>((ref) => TeamService());

/// Stores a pending team invite code for users who need to register/login first
final pendingTeamInviteProvider = StateProvider<String?>((ref) => null);

final teamProvider = StreamProvider.family<TeamModel?, String>((ref, teamId) {
  return ref.watch(teamServiceProvider).teamStream(teamId);
});

final teamMembersProvider = StreamProvider.family<List<TeamMember>, String>((ref, teamId) {
  return ref.watch(teamServiceProvider).membersStream(teamId);
});

final userTeamsProvider = StreamProvider.family<List<TeamModel>, String>((ref, userId) {
  return ref.watch(teamServiceProvider).userTeamsStream(userId);
});

class TeamNotifier extends StateNotifier<AsyncValue<String?>> {
  final TeamService _teamService;

  TeamNotifier(this._teamService) : super(const AsyncValue.data(null));

  Future<String?> createTeam({
    required String ownerId,
    required String ownerName,
    required String name,
  }) async {
    state = const AsyncValue.loading();
    try {
      final teamId = await _teamService.createTeam(
        ownerId: ownerId,
        ownerName: ownerName,
        name: name,
      );
      state = AsyncValue.data(teamId);
      return teamId;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<String?> joinTeamByInviteCode({
    required String inviteCode,
    required String userId,
    required String userName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final teamId = await _teamService.joinTeamByInviteCode(
        inviteCode: inviteCode.toUpperCase(),
        userId: userId,
        userName: userName,
      );
      if (teamId != null) {
        state = AsyncValue.data(teamId);
      } else {
        state = AsyncValue.error('Team not found', StackTrace.current);
      }
      return teamId;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow; // Re-throw so the UI can display the actual error
    }
  }

  Future<bool> joinTeam({
    required String teamId,
    required String userId,
    required String userName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final success = await _teamService.joinTeam(
        teamId: teamId,
        userId: userId,
        userName: userName,
      );
      state = success ? AsyncValue.data(teamId) : AsyncValue.error('Failed to join', StackTrace.current);
      return success;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> leaveTeam(String teamId, String userId) async {
    state = const AsyncValue.loading();
    try {
      await _teamService.leaveTeam(teamId, userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteTeam(String teamId) async {
    state = const AsyncValue.loading();
    try {
      await _teamService.deleteTeam(teamId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

final teamNotifierProvider =
    StateNotifierProvider<TeamNotifier, AsyncValue<String?>>((ref) {
  return TeamNotifier(ref.watch(teamServiceProvider));
});
