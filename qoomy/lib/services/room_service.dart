import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/models/team_model.dart';

class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _roomsCollection =>
      _firestore.collection('rooms');

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<String?> _uploadImage(String roomCode, Uint8List imageBytes) async {
    try {
      final ref = _storage.ref().child('rooms/$roomCode/question_image.jpg');
      final uploadTask = ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));

      // Add timeout to prevent hanging indefinitely
      await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          uploadTask.cancel();
          throw Exception('Image upload timed out');
        },
      );

      return await ref.getDownloadURL();
    } catch (e) {
      developer.log('Error uploading image: $e', name: 'RoomService');
      return null;
    }
  }

  Future<String> createRoom({
    required String hostId,
    required String hostName,
    required EvaluationMode evaluationMode,
    required String question,
    required String answer,
    String? comment,
    Uint8List? imageBytes,
    String? teamId,
  }) async {
    String roomCode;
    bool codeExists = true;

    do {
      roomCode = _generateRoomCode();
      final doc = await _roomsCollection.doc(roomCode).get();
      codeExists = doc.exists;
    } while (codeExists);

    // Upload image if provided
    String? imageUrl;
    if (imageBytes != null) {
      imageUrl = await _uploadImage(roomCode, imageBytes);
    }

    final room = RoomModel(
      code: roomCode,
      hostId: hostId,
      hostName: hostName,
      status: RoomStatus.playing,
      evaluationMode: evaluationMode,
      question: question,
      answer: answer,
      comment: comment,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );

    await _roomsCollection.doc(roomCode).set(room.toFirestore());

    // Auto-join team members if team is selected
    if (teamId != null) {
      await _autoJoinTeamMembers(roomCode, hostId, teamId);
    }

    return roomCode;
  }

  Future<void> _autoJoinTeamMembers(String roomCode, String hostId, String teamId) async {
    try {
      // Get team members
      final membersSnapshot = await _firestore
          .collection('teams')
          .doc(teamId)
          .collection('members')
          .get();

      final batch = _firestore.batch();

      for (final memberDoc in membersSnapshot.docs) {
        final member = TeamMember.fromFirestore(memberDoc);

        // Skip the host - they created the room, not a player
        if (member.id == hostId) continue;

        final player = Player(
          id: member.id,
          name: member.name,
          joinedAt: DateTime.now(),
        );

        batch.set(
          _roomsCollection.doc(roomCode).collection('players').doc(member.id),
          player.toFirestore(),
        );
      }

      await batch.commit();
    } catch (e) {
      developer.log('Error auto-joining team members: $e', name: 'RoomService');
    }
  }

  Future<RoomModel?> getRoom(String roomCode) async {
    final doc = await _roomsCollection.doc(roomCode).get();
    if (!doc.exists) return null;

    final playersSnapshot = await _roomsCollection
        .doc(roomCode)
        .collection('players')
        .orderBy('joinedAt')
        .get();

    final players = playersSnapshot.docs
        .map((doc) => Player.fromFirestore(doc))
        .toList();

    return RoomModel.fromFirestore(doc, players);
  }

  Stream<RoomModel?> roomStream(String roomCode) {
    return _roomsCollection.doc(roomCode).snapshots().asyncMap((doc) async {
      if (!doc.exists) return null;

      final playersSnapshot = await _roomsCollection
          .doc(roomCode)
          .collection('players')
          .orderBy('joinedAt')
          .get();

      final players = playersSnapshot.docs
          .map((doc) => Player.fromFirestore(doc))
          .toList();

      return RoomModel.fromFirestore(doc, players);
    });
  }

  Stream<List<Player>> playersStream(String roomCode) {
    return _roomsCollection
        .doc(roomCode)
        .collection('players')
        .orderBy('score', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Player.fromFirestore(doc)).toList());
  }

  Future<bool> joinRoom({
    required String roomCode,
    required String playerId,
    required String playerName,
  }) async {
    final room = await getRoom(roomCode);
    if (room == null) return false;
    // Allow joining rooms that are waiting or playing (game starts immediately)
    if (room.status == RoomStatus.finished) return false;

    final player = Player(
      id: playerId,
      name: playerName,
      joinedAt: DateTime.now(),
    );

    await _roomsCollection
        .doc(roomCode)
        .collection('players')
        .doc(playerId)
        .set(player.toFirestore());

    return true;
  }

  Future<void> leaveRoom(String roomCode, String playerId) async {
    await _roomsCollection
        .doc(roomCode)
        .collection('players')
        .doc(playerId)
        .delete();
  }

  Future<void> startGame(String roomCode) async {
    await _roomsCollection.doc(roomCode).update({
      'status': RoomStatus.playing.name,
    });
  }

  Future<void> endGame(String roomCode) async {
    await _roomsCollection.doc(roomCode).update({
      'status': RoomStatus.finished.name,
    });
  }

  Future<void> markPlayerAnswer(String roomCode, String playerId, bool isCorrect) async {
    await _roomsCollection
        .doc(roomCode)
        .collection('players')
        .doc(playerId)
        .update({
      'isCorrect': isCorrect,
    });
  }

  Future<void> submitPlayerAnswer(String roomCode, String playerId, String answer) async {
    await _roomsCollection
        .doc(roomCode)
        .collection('players')
        .doc(playerId)
        .update({
      'answer': answer,
      'answeredAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteRoom(String roomCode) async {
    final playersSnapshot = await _roomsCollection
        .doc(roomCode)
        .collection('players')
        .get();

    final batch = _firestore.batch();
    for (final doc in playersSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_roomsCollection.doc(roomCode));
    await batch.commit();

    // Delete image from storage if exists
    try {
      await _storage.ref().child('rooms/$roomCode/question_image.jpg').delete();
    } catch (_) {}
  }

  // Chat methods
  Stream<List<ChatMessage>> chatStream(String roomCode) {
    return _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList());
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
    final message = ChatMessage(
      id: '',
      playerId: playerId,
      playerName: playerName,
      text: text,
      type: type,
      sentAt: DateTime.now(),
      replyToId: replyToId,
      replyToText: replyToText,
      replyToPlayerName: replyToPlayerName,
    );

    await _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .add(message.toFirestore());
  }

  Future<void> markMessageAnswer({
    required String roomCode,
    required String messageId,
    required bool isCorrect,
  }) async {
    await _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .doc(messageId)
        .update({'isCorrect': isCorrect});
  }

  /// Get all rooms created by a user (as host)
  Stream<List<RoomModel>> userHostedRoomsStream(String userId) {
    return _roomsCollection
        .where('hostId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RoomModel.fromFirestore(doc, []))
            .toList());
  }

  /// Get all rooms where user is a player
  Stream<List<RoomModel>> userJoinedRoomsStream(String userId) {
    // Query collection group on 'id' field (stored in player document)
    return _firestore
        .collectionGroup('players')
        .where('id', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      final rooms = <RoomModel>[];
      for (final playerDoc in snapshot.docs) {
        // Get parent room code from path: rooms/{roomCode}/players/{playerId}
        final roomCode = playerDoc.reference.parent.parent?.id;
        if (roomCode != null) {
          final roomDoc = await _roomsCollection.doc(roomCode).get();
          if (roomDoc.exists) {
            rooms.add(RoomModel.fromFirestore(roomDoc, []));
          }
        }
      }
      // Sort by createdAt descending
      rooms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rooms;
    });
  }

  /// Update user's last read timestamp for a room
  Future<void> updateLastRead(String roomCode, String userId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReads')
        .doc(roomCode)
        .set({
      'lastReadAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get user's last read timestamp for a room
  Future<DateTime?> getLastRead(String roomCode, String userId) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReads')
        .doc(roomCode)
        .get();

    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return (data['lastReadAt'] as Timestamp?)?.toDate();
  }

  /// Stream of unread message count for a specific room and user
  /// Combines listening to both chat messages and user's lastRead timestamp
  Stream<int> unreadCountStream(String roomCode, String userId) {
    // Create a controller to emit combined results
    final controller = StreamController<int>.broadcast();

    // Cache for latest values
    List<QueryDocumentSnapshot>? latestChatDocs;
    DateTime? latestLastReadAt;

    void recalculateCount() {
      if (latestChatDocs == null) return;

      int count;
      if (latestLastReadAt == null) {
        count = latestChatDocs!.length;
      } else {
        count = 0;
        for (final doc in latestChatDocs!) {
          final data = doc.data() as Map<String, dynamic>;
          final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
          if (sentAt != null && sentAt.isAfter(latestLastReadAt!)) {
            count++;
          }
        }
      }
      controller.add(count);
    }

    // Listen to chat messages
    final chatSubscription = _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .snapshots()
        .listen((chatSnapshot) {
      latestChatDocs = chatSnapshot.docs;
      recalculateCount();
    });

    // Listen to user's lastRead timestamp
    final readSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReads')
        .doc(roomCode)
        .snapshots()
        .listen((readDoc) {
      if (readDoc.exists && readDoc.data() != null) {
        latestLastReadAt = (readDoc.data()!['lastReadAt'] as Timestamp?)?.toDate();
      } else {
        latestLastReadAt = null;
      }
      recalculateCount();
    });

    // Clean up subscriptions when the stream is cancelled
    controller.onCancel = () {
      chatSubscription.cancel();
      readSubscription.cancel();
      controller.close();
    };

    return controller.stream;
  }

  /// Stream to check if a room has at least one correct answer
  Stream<bool> hasCorrectAnswerStream(String roomCode) {
    return _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .where('isCorrect', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }

  /// Get unread counts for multiple rooms at once
  Future<Map<String, int>> getUnreadCountsForRooms(
    List<String> roomCodes,
    String userId,
  ) async {
    final counts = <String, int>{};

    for (final roomCode in roomCodes) {
      final lastReadAt = await getLastRead(roomCode, userId);

      Query query = _roomsCollection.doc(roomCode).collection('chat');
      if (lastReadAt != null) {
        query = query.where('sentAt', isGreaterThan: Timestamp.fromDate(lastReadAt));
      }

      final snapshot = await query.count().get();
      counts[roomCode] = snapshot.count ?? 0;
    }

    return counts;
  }

  /// Mark that a user has revealed the correct answer for a room
  Future<void> revealAnswer(String roomCode, String userId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReveals')
        .doc(roomCode)
        .set({
      'revealedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream to check if user has revealed the correct answer for a room
  Stream<bool> hasRevealedAnswerStream(String roomCode, String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReveals')
        .doc(roomCode)
        .snapshots()
        .map((doc) => doc.exists);
  }
}
