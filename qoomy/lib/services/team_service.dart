import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qoomy/models/team_model.dart';
import 'package:qoomy/models/user_model.dart';

class TeamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _teamsCollection =>
      _firestore.collection('teams');

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<String> createTeam({
    required String ownerId,
    required String ownerName,
    required String name,
  }) async {
    String inviteCode;
    bool codeExists = true;

    do {
      inviteCode = _generateInviteCode();
      final query = await _teamsCollection
          .where('inviteCode', isEqualTo: inviteCode)
          .limit(1)
          .get();
      codeExists = query.docs.isNotEmpty;
    } while (codeExists);

    final teamRef = _teamsCollection.doc();
    final team = TeamModel(
      id: teamRef.id,
      name: name,
      ownerId: ownerId,
      ownerName: ownerName,
      inviteCode: inviteCode,
      createdAt: DateTime.now(),
      memberIds: [ownerId],
    );

    await teamRef.set(team.toFirestore());

    final ownerMember = TeamMember(
      id: ownerId,
      name: ownerName,
      role: TeamMemberRole.owner,
      joinedAt: DateTime.now(),
    );
    await teamRef.collection('members').doc(ownerId).set(ownerMember.toFirestore());

    return teamRef.id;
  }

  Future<TeamModel?> getTeam(String teamId) async {
    final doc = await _teamsCollection.doc(teamId).get();
    if (!doc.exists) return null;

    final membersSnapshot = await _teamsCollection
        .doc(teamId)
        .collection('members')
        .orderBy('joinedAt')
        .get();

    final members = membersSnapshot.docs
        .map((doc) => TeamMember.fromFirestore(doc))
        .toList();

    return TeamModel.fromFirestore(doc, members);
  }

  Future<TeamModel?> getTeamByInviteCode(String inviteCode) async {
    final normalizedCode = inviteCode.toUpperCase().trim();

    // Try to find by inviteCode field first
    var query = await _teamsCollection
        .where('inviteCode', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    // If not found, scan all teams (fallback for index issues)
    if (query.docs.isEmpty) {
      final allTeams = await _teamsCollection.get();
      for (final doc in allTeams.docs) {
        final data = doc.data();
        if (data['inviteCode'] == normalizedCode) {
          query = await _teamsCollection
              .where(FieldPath.documentId, isEqualTo: doc.id)
              .get();
          break;
        }
      }
    }

    if (query.docs.isEmpty) {
      return null;
    }

    final doc = query.docs.first;
    final membersSnapshot = await _teamsCollection
        .doc(doc.id)
        .collection('members')
        .orderBy('joinedAt')
        .get();

    final members = membersSnapshot.docs
        .map((doc) => TeamMember.fromFirestore(doc))
        .toList();

    return TeamModel.fromFirestore(doc, members);
  }

  Stream<TeamModel?> teamStream(String teamId) {
    return _teamsCollection.doc(teamId).snapshots().asyncMap((doc) async {
      if (!doc.exists) return null;

      final membersSnapshot = await _teamsCollection
          .doc(teamId)
          .collection('members')
          .orderBy('joinedAt')
          .get();

      final members = membersSnapshot.docs
          .map((doc) => TeamMember.fromFirestore(doc))
          .toList();

      return TeamModel.fromFirestore(doc, members);
    });
  }

  Stream<List<TeamMember>> membersStream(String teamId) {
    return _teamsCollection
        .doc(teamId)
        .collection('members')
        .orderBy('joinedAt')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => TeamMember.fromFirestore(doc)).toList());
  }

  Stream<List<TeamModel>> userTeamsStream(String userId) {
    return _teamsCollection
        .where('memberIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final teams = <TeamModel>[];
      for (final doc in snapshot.docs) {
        final membersSnapshot = await _teamsCollection
            .doc(doc.id)
            .collection('members')
            .orderBy('joinedAt')
            .get();

        final members = membersSnapshot.docs
            .map((doc) => TeamMember.fromFirestore(doc))
            .toList();

        teams.add(TeamModel.fromFirestore(doc, members));
      }
      return teams;
    });
  }

  Future<bool> joinTeam({
    required String teamId,
    required String userId,
    required String userName,
  }) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    if (team.memberIds.contains(userId)) return true;

    final member = TeamMember(
      id: userId,
      name: userName,
      role: TeamMemberRole.member,
      joinedAt: DateTime.now(),
    );

    final batch = _firestore.batch();

    batch.set(
      _teamsCollection.doc(teamId).collection('members').doc(userId),
      member.toFirestore(),
    );

    batch.update(_teamsCollection.doc(teamId), {
      'memberIds': FieldValue.arrayUnion([userId]),
    });

    await batch.commit();
    return true;
  }

  Future<String?> joinTeamByInviteCode({
    required String inviteCode,
    required String userId,
    required String userName,
  }) async {
    final team = await getTeamByInviteCode(inviteCode);
    if (team == null) return null;

    final success = await joinTeam(
      teamId: team.id,
      userId: userId,
      userName: userName,
    );

    return success ? team.id : null;
  }

  Future<void> leaveTeam(String teamId, String userId) async {
    final team = await getTeam(teamId);
    if (team == null) return;

    if (team.ownerId == userId) {
      throw Exception('Owner cannot leave the team. Delete the team instead.');
    }

    final batch = _firestore.batch();

    batch.delete(_teamsCollection.doc(teamId).collection('members').doc(userId));

    batch.update(_teamsCollection.doc(teamId), {
      'memberIds': FieldValue.arrayRemove([userId]),
    });

    await batch.commit();
  }

  Future<void> removeMember(String teamId, String memberId, String requesterId) async {
    final team = await getTeam(teamId);
    if (team == null) return;

    if (team.ownerId != requesterId) {
      throw Exception('Only the team owner can remove members.');
    }

    if (memberId == team.ownerId) {
      throw Exception('Cannot remove the team owner.');
    }

    final batch = _firestore.batch();

    batch.delete(_teamsCollection.doc(teamId).collection('members').doc(memberId));

    batch.update(_teamsCollection.doc(teamId), {
      'memberIds': FieldValue.arrayRemove([memberId]),
    });

    await batch.commit();
  }

  Future<void> updateTeamName(String teamId, String newName) async {
    await _teamsCollection.doc(teamId).update({'name': newName});
  }

  Future<String> regenerateInviteCode(String teamId) async {
    String inviteCode;
    bool codeExists = true;

    do {
      inviteCode = _generateInviteCode();
      final query = await _teamsCollection
          .where('inviteCode', isEqualTo: inviteCode)
          .limit(1)
          .get();
      codeExists = query.docs.isNotEmpty;
    } while (codeExists);

    await _teamsCollection.doc(teamId).update({'inviteCode': inviteCode});
    return inviteCode;
  }

  Future<void> deleteTeam(String teamId) async {
    final membersSnapshot = await _teamsCollection
        .doc(teamId)
        .collection('members')
        .get();

    final batch = _firestore.batch();
    for (final doc in membersSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_teamsCollection.doc(teamId));
    await batch.commit();
  }

  Future<List<TeamMember>> getTeamMembers(String teamId) async {
    final team = await getTeam(teamId);
    return team?.members ?? [];
  }

  /// Search users by email (exact match or prefix)
  Future<List<UserModel>> searchUsersByEmail(String email) async {
    if (email.isEmpty) return [];

    final normalizedEmail = email.toLowerCase().trim();

    // Search for exact match or emails starting with the query
    final query = await _firestore
        .collection('users')
        .where('email', isGreaterThanOrEqualTo: normalizedEmail)
        .where('email', isLessThan: '${normalizedEmail}z')
        .limit(10)
        .get();

    return query.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
  }

  /// Get user by exact email
  Future<UserModel?> getUserByEmail(String email) async {
    final normalizedEmail = email.toLowerCase().trim();

    final query = await _firestore
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return UserModel.fromFirestore(query.docs.first);
  }

  /// Add a member to the team by their user ID (owner only)
  Future<bool> addMemberById({
    required String teamId,
    required String userId,
    required String userName,
    required String requesterId,
  }) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    // Only owner can add members
    if (team.ownerId != requesterId) {
      throw Exception('Only the team owner can add members.');
    }

    // Already a member
    if (team.memberIds.contains(userId)) return true;

    final member = TeamMember(
      id: userId,
      name: userName,
      role: TeamMemberRole.member,
      joinedAt: DateTime.now(),
    );

    final batch = _firestore.batch();

    batch.set(
      _teamsCollection.doc(teamId).collection('members').doc(userId),
      member.toFirestore(),
    );

    batch.update(_teamsCollection.doc(teamId), {
      'memberIds': FieldValue.arrayUnion([userId]),
    });

    await batch.commit();
    return true;
  }
}
