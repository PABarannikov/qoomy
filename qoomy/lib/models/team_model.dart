import 'package:cloud_firestore/cloud_firestore.dart';

enum TeamMemberRole { owner, member }

class TeamMember {
  final String id;
  final String name;
  final TeamMemberRole role;
  final DateTime joinedAt;

  TeamMember({
    required this.id,
    required this.name,
    required this.role,
    required this.joinedAt,
  });

  factory TeamMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TeamMember(
      id: data['id'] ?? doc.id,
      name: data['name'] ?? '',
      role: TeamMemberRole.values.firstWhere(
        (e) => e.name == data['role'],
        orElse: () => TeamMemberRole.member,
      ),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
    };
  }

  TeamMember copyWith({
    String? id,
    String? name,
    TeamMemberRole? role,
    DateTime? joinedAt,
  }) {
    return TeamMember(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}

class TeamModel {
  final String id;
  final String name;
  final String ownerId;
  final String ownerName;
  final String inviteCode;
  final DateTime createdAt;
  final List<String> memberIds;
  final List<TeamMember> members;

  TeamModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.ownerName,
    required this.inviteCode,
    required this.createdAt,
    this.memberIds = const [],
    this.members = const [],
  });

  factory TeamModel.fromFirestore(DocumentSnapshot doc, List<TeamMember> members) {
    final data = doc.data() as Map<String, dynamic>;
    return TeamModel(
      id: doc.id,
      name: data['name'] ?? '',
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberIds: List<String>.from(data['memberIds'] ?? []),
      members: members,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'inviteCode': inviteCode,
      'createdAt': Timestamp.fromDate(createdAt),
      'memberIds': memberIds,
    };
  }

  bool isOwner(String userId) => ownerId == userId;

  bool isMember(String userId) => memberIds.contains(userId);

  int get memberCount => memberIds.length;

  TeamModel copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? ownerName,
    String? inviteCode,
    DateTime? createdAt,
    List<String>? memberIds,
    List<TeamMember>? members,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      inviteCode: inviteCode ?? this.inviteCode,
      createdAt: createdAt ?? this.createdAt,
      memberIds: memberIds ?? this.memberIds,
      members: members ?? this.members,
    );
  }
}
