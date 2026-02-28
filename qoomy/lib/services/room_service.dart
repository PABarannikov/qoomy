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

    // Get team name if team is selected
    String? teamName;
    if (teamId != null) {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();
      if (teamDoc.exists) {
        teamName = (teamDoc.data() as Map<String, dynamic>)['name'] as String?;
      }
    }

    final now = DateTime.now();
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
      teamId: teamId,
      teamName: teamName,
      createdAt: now,
      lastMessageAt: now, // Initialize for proper sorting
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

      print('[RoomService] Auto-join: team=$teamId, members=${membersSnapshot.docs.length}, hostId=$hostId');

      final batch = _firestore.batch();
      int addedCount = 0;

      for (final memberDoc in membersSnapshot.docs) {
        final member = TeamMember.fromFirestore(memberDoc);
        print('[RoomService] Member: ${member.id} (${member.name})');

        // Skip the host - they created the room, not a player
        if (member.id == hostId) {
          print('[RoomService] Skipping host');
          continue;
        }

        final player = Player(
          id: member.id,
          name: member.name,
          joinedAt: DateTime.now(),
        );

        batch.set(
          _roomsCollection.doc(roomCode).collection('players').doc(member.id),
          player.toFirestore(),
        );
        addedCount++;
      }

      await batch.commit();
      print('[RoomService] Auto-join complete: added $addedCount players to room $roomCode');
    } catch (e) {
      print('[RoomService] Error auto-joining team members: $e');
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

    final docRef = await _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .add(message.toFirestore());

    // Update room's lastMessageAt for sorting
    await _roomsCollection.doc(roomCode).update({
      'lastMessageAt': Timestamp.fromDate(DateTime.now()),
    });

    return docRef.id;
  }

  Future<void> markMessageAnswer({
    required String roomCode,
    required String messageId,
    required bool isCorrect,
  }) async {
    // Get the message to find the player who sent it
    final messageDoc = await _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .doc(messageId)
        .get();

    if (!messageDoc.exists) return;

    final messageData = messageDoc.data()!;
    final playerId = messageData['playerId'] as String?;

    // Update the message's isCorrect status
    await _roomsCollection
        .doc(roomCode)
        .collection('chat')
        .doc(messageId)
        .update({'isCorrect': isCorrect});

    // Award points if marking as correct
    if (isCorrect && playerId != null) {
      // Count existing correct answers in this room
      final correctAnswersSnapshot = await _roomsCollection
          .doc(roomCode)
          .collection('chat')
          .where('isCorrect', isEqualTo: true)
          .get();

      // First correct answer gets 1 point, others get 0.5
      // Note: the current message was just marked correct, so count includes it
      final isFirstCorrect = correctAnswersSnapshot.docs.length <= 1;
      final pointsToAdd = isFirstCorrect ? 1.0 : 0.5;

      // Update player's score
      await _roomsCollection
          .doc(roomCode)
          .collection('players')
          .doc(playerId)
          .update({
        'score': FieldValue.increment(pointsToAdd),
      });
    }
  }

  /// Get all rooms created by a user (as host)
  Stream<List<RoomModel>> userHostedRoomsStream(String userId, {int? limit}) {
    Query<Map<String, dynamic>> query = _roomsCollection
        .where('hostId', isEqualTo: userId)
        .orderBy('lastMessageAt', descending: true);

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => RoomModel.fromFirestore(doc, []))
        .toList());
  }

  /// Get all rooms where user is a player
  Stream<List<RoomModel>> userJoinedRoomsStream(String userId, {int? limit}) {
    // Query collection group on 'id' field (stored in player document)
    return _firestore
        .collectionGroup('players')
        .where('id', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      // Collect unique room codes from player document paths
      final roomCodes = snapshot.docs
          .map((doc) => doc.reference.parent.parent?.id)
          .where((code) => code != null)
          .cast<String>()
          .toSet();

      // Fetch all room documents in parallel
      final roomDocs = await Future.wait(
        roomCodes.map((code) => _roomsCollection.doc(code).get()),
      );

      final rooms = roomDocs
          .where((doc) => doc.exists)
          .map((doc) => RoomModel.fromFirestore(doc, []))
          .toList();
      // Sort by lastActivity (lastMessageAt or createdAt) descending
      rooms.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
      // Apply limit after sorting (since collection group query doesn't support ordering by room fields)
      if (limit != null && rooms.length > limit) {
        return rooms.sublist(0, limit);
      }
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

  /// Stream to check if user has opened a room (has entry in roomReads)
  /// Uses debouncing to prevent flashing during initial load
  Stream<bool> hasOpenedRoomStream(String roomCode, String userId) {
    final controller = StreamController<bool>.broadcast();
    Timer? debounceTimer;
    bool? lastEmittedValue;
    bool hasEmittedFirst = false;

    final subscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReads')
        .doc(roomCode)
        .snapshots()
        .listen((doc) {
      final hasOpened = doc.exists;

      // Debounce - use longer delay for first emission
      debounceTimer?.cancel();
      final delay = hasEmittedFirst ? 100 : 400;
      debounceTimer = Timer(Duration(milliseconds: delay), () {
        if (lastEmittedValue != hasOpened) {
          lastEmittedValue = hasOpened;
          hasEmittedFirst = true;
          controller.add(hasOpened);
        }
      });
    }, onError: (e) => controller.addError(e));

    controller.onCancel = () {
      debounceTimer?.cancel();
      subscription.cancel();
      controller.close();
    };

    return controller.stream;
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

      int count = 0;
      if (latestLastReadAt == null) {
        // Count all messages NOT sent by this user
        for (final doc in latestChatDocs!) {
          final data = doc.data() as Map<String, dynamic>;
          final playerId = data['playerId'] as String?;
          if (playerId != userId) {
            count++;
          }
        }
      } else {
        // Count messages after lastReadAt NOT sent by this user
        for (final doc in latestChatDocs!) {
          final data = doc.data() as Map<String, dynamic>;
          final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
          final playerId = data['playerId'] as String?;
          if (sentAt != null && sentAt.isAfter(latestLastReadAt!) && playerId != userId) {
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

  /// Get all rooms for a specific team (including inactive ones)
  Stream<List<RoomModel>> teamRoomsStream(String teamId) {
    return _roomsCollection
        .where('teamId', isEqualTo: teamId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RoomModel.fromFirestore(doc, []))
            .toList());
  }

  /// Get all rooms for multiple teams at once
  Stream<List<RoomModel>> userTeamRoomsStream(List<String> teamIds, {int? limit}) {
    if (teamIds.isEmpty) {
      return Stream.value([]);
    }

    // Firestore limits 'whereIn' to 30 values, so we need to handle larger lists
    if (teamIds.length <= 30) {
      Query<Map<String, dynamic>> query = _roomsCollection
          .where('teamId', whereIn: teamIds)
          .orderBy('lastMessageAt', descending: true);

      if (limit != null) {
        query = query.limit(limit);
      }

      return query.snapshots().map((snapshot) => snapshot.docs
          .map((doc) => RoomModel.fromFirestore(doc, []))
          .toList());
    }

    // For more than 30 teams, combine multiple queries
    // This is a rare edge case but handled for completeness
    final chunks = <List<String>>[];
    for (var i = 0; i < teamIds.length; i += 30) {
      chunks.add(teamIds.sublist(i, i + 30 > teamIds.length ? teamIds.length : i + 30));
    }

    return Stream.periodic(const Duration(milliseconds: 100))
        .asyncMap((_) async {
      final allRooms = <RoomModel>[];
      for (final chunk in chunks) {
        final snapshot = await _roomsCollection
            .where('teamId', whereIn: chunk)
            .orderBy('lastMessageAt', descending: true)
            .get();
        allRooms.addAll(snapshot.docs
            .map((doc) => RoomModel.fromFirestore(doc, [])));
      }
      // Sort combined results by creation time
      allRooms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // Apply limit after combining all chunks
      if (limit != null && allRooms.length > limit) {
        return allRooms.sublist(0, limit);
      }
      return allRooms;
    }).distinct();
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

  /// Stream of total unread message count across all user's rooms
  Stream<int> totalUnreadCountStream(String userId) {
    final controller = StreamController<int>.broadcast();
    final roomUnreadCounts = <String, int>{};
    final subscriptions = <StreamSubscription>[];
    Set<String> currentRoomCodes = {};

    void emitTotal() {
      final total = roomUnreadCounts.values.fold<int>(0, (sum, count) => sum + count);
      controller.add(total);
    }

    void subscribeToRoom(String roomCode) {
      if (roomUnreadCounts.containsKey(roomCode)) return;

      roomUnreadCounts[roomCode] = 0;
      final sub = unreadCountStream(roomCode, userId).listen((count) {
        roomUnreadCounts[roomCode] = count;
        emitTotal();
      });
      subscriptions.add(sub);
    }

    void updateRooms(List<RoomModel> rooms) {
      final newRoomCodes = rooms.map((r) => r.code).toSet();

      // Remove rooms that no longer exist
      for (final code in currentRoomCodes.difference(newRoomCodes)) {
        roomUnreadCounts.remove(code);
      }

      // Add new rooms
      for (final room in rooms) {
        subscribeToRoom(room.code);
      }

      currentRoomCodes = newRoomCodes;
      emitTotal();
    }

    // Listen to hosted rooms
    final hostedSub = userHostedRoomsStream(userId).listen((rooms) {
      for (final room in rooms) {
        subscribeToRoom(room.code);
      }
    });
    subscriptions.add(hostedSub);

    // Listen to joined rooms
    final joinedSub = userJoinedRoomsStream(userId).listen((rooms) {
      for (final room in rooms) {
        subscribeToRoom(room.code);
      }
    });
    subscriptions.add(joinedSub);

    controller.onCancel = () {
      for (final sub in subscriptions) {
        sub.cancel();
      }
      controller.close();
    };

    return controller.stream;
  }

  /// Stream of combined unread message count for a specific list of room codes
  Stream<int> combinedUnreadCountStream(String userId, List<String> roomCodes) {
    if (roomCodes.isEmpty) {
      return Stream.value(0);
    }

    final controller = StreamController<int>.broadcast();
    final roomUnreadCounts = <String, int>{};
    final roomsReported = <String>{};
    final subscriptions = <StreamSubscription>[];
    Timer? debounceTimer;
    int? lastEmittedTotal;
    bool hasEmittedFirst = false;

    void emitTotal() {
      // Wait until all rooms have reported at least once before emitting
      if (roomsReported.length < roomCodes.length) return;

      // Debounce - use longer delay for first emission to ensure all data is stable
      debounceTimer?.cancel();
      final delay = hasEmittedFirst ? 100 : 400;
      debounceTimer = Timer(Duration(milliseconds: delay), () {
        final total = roomUnreadCounts.values.fold<int>(0, (sum, count) => sum + count);
        // Only emit if total actually changed
        if (lastEmittedTotal != total) {
          lastEmittedTotal = total;
          hasEmittedFirst = true;
          controller.add(total);
        }
      });
    }

    // Subscribe to unread count for each room
    for (final roomCode in roomCodes) {
      roomUnreadCounts[roomCode] = 0;
      final sub = unreadCountStream(roomCode, userId).listen((count) {
        roomUnreadCounts[roomCode] = count;
        roomsReported.add(roomCode);
        emitTotal();
      });
      subscriptions.add(sub);
    }

    controller.onCancel = () {
      debounceTimer?.cancel();
      for (final sub in subscriptions) {
        sub.cancel();
      }
      controller.close();
    };

    return controller.stream;
  }

  /// Get total unread count by directly querying Firestore (not cached)
  /// This is used for periodic badge sync to ensure accuracy
  Future<int> getTotalUnreadCountDirect(String userId, List<String> teamIds) async {
    try {
      // Get all room codes for the user
      final roomCodes = <String>{};

      // 1. Get hosted rooms
      final hostedSnapshot = await _roomsCollection
          .where('hostId', isEqualTo: userId)
          .get();
      for (final doc in hostedSnapshot.docs) {
        roomCodes.add(doc.id);
      }

      // 2. Get joined rooms
      final joinedSnapshot = await _firestore
          .collectionGroup('players')
          .where('id', isEqualTo: userId)
          .get();
      for (final playerDoc in joinedSnapshot.docs) {
        final roomCode = playerDoc.reference.parent.parent?.id;
        if (roomCode != null) {
          roomCodes.add(roomCode);
        }
      }

      // 3. Get team rooms
      if (teamIds.isNotEmpty) {
        // Handle Firestore's 30 item limit for whereIn
        for (var i = 0; i < teamIds.length; i += 30) {
          final chunk = teamIds.sublist(
            i,
            i + 30 > teamIds.length ? teamIds.length : i + 30,
          );
          final teamRoomsSnapshot = await _roomsCollection
              .where('teamId', whereIn: chunk)
              .get();
          for (final doc in teamRoomsSnapshot.docs) {
            roomCodes.add(doc.id);
          }
        }
      }

      if (roomCodes.isEmpty) return 0;

      // Now get unread counts for all rooms
      final counts = await getUnreadCountsForRooms(roomCodes.toList(), userId);
      return counts.values.fold<int>(0, (sum, count) => sum + count);
    } catch (e) {
      developer.log('Error getting total unread count: $e', name: 'RoomService');
      return 0;
    }
  }

  /// Stream of count of rooms where user is a player but hasn't opened yet
  /// A room is "new" if user has no roomReads document for it
  /// Also includes team rooms where user is not the host
  Stream<int> unseenPlayerRoomsCountStream(String userId, List<String> teamIds) {
    // Listen to rooms where user is a player
    final playerRoomsStream = _firestore
        .collectionGroup('players')
        .where('id', isEqualTo: userId)
        .snapshots();

    // Listen to user's roomReads collection
    final roomReadsStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('roomReads')
        .snapshots();

    final controller = StreamController<int>.broadcast();

    Set<String>? playerRoomCodes;
    Set<String>? teamRoomCodes;
    Set<String>? readRoomCodes;
    StreamSubscription? teamRoomsSub;
    Timer? debounceTimer;
    int? lastEmittedCount;
    bool hasEmittedFirst = false;

    void recalculate() {
      if (playerRoomCodes == null || readRoomCodes == null) return;
      // If user has teams, wait for teamRoomCodes to be set
      if (teamIds.isNotEmpty && teamRoomCodes == null) return;

      // Debounce - use longer delay for first emission to ensure all data is stable
      debounceTimer?.cancel();
      final delay = hasEmittedFirst ? 100 : 400;
      debounceTimer = Timer(Duration(milliseconds: delay), () {
        // Combine player rooms and team rooms (where user is not host)
        final allAccessibleRooms = <String>{
          ...playerRoomCodes!,
          ...?teamRoomCodes,
        };

        // Count rooms that are accessible but not in readRoomCodes
        final unseenCount = allAccessibleRooms
            .where((code) => !readRoomCodes!.contains(code))
            .length;

        // Only emit if count actually changed
        if (lastEmittedCount != unseenCount) {
          lastEmittedCount = unseenCount;
          hasEmittedFirst = true;
          controller.add(unseenCount);
        }
      });
    }

    final playerSub = playerRoomsStream.listen(
      (snapshot) {
        playerRoomCodes = <String>{};
        for (final doc in snapshot.docs) {
          // Extract room code from path: rooms/{roomCode}/players/{playerId}
          final pathParts = doc.reference.path.split('/');
          if (pathParts.length >= 2) {
            playerRoomCodes!.add(pathParts[1]);
          }
        }
        recalculate();
      },
      onError: (e) => controller.addError(e),
    );

    // Listen to team rooms if user has teams
    if (teamIds.isNotEmpty) {
      // Firestore limits whereIn to 30 items
      final teamIdsToQuery = teamIds.take(30).toList();
      teamRoomsSub = _roomsCollection
          .where('teamId', whereIn: teamIdsToQuery)
          .snapshots()
          .listen(
        (snapshot) {
          teamRoomCodes = <String>{};
          for (final doc in snapshot.docs) {
            final room = RoomModel.fromFirestore(doc, []);
            // Only include rooms where user is NOT the host
            if (room.hostId != userId) {
              teamRoomCodes!.add(room.code);
            }
          }
          recalculate();
        },
        onError: (e) => controller.addError(e),
      );
    } else {
      teamRoomCodes = <String>{};
    }

    final readsSub = roomReadsStream.listen(
      (snapshot) {
        readRoomCodes = snapshot.docs.map((doc) => doc.id).toSet();
        recalculate();
      },
      onError: (e) => controller.addError(e),
    );

    controller.onCancel = () {
      debounceTimer?.cancel();
      playerSub.cancel();
      teamRoomsSub?.cancel();
      readsSub.cancel();
      controller.close();
    };

    return controller.stream;
  }
}
