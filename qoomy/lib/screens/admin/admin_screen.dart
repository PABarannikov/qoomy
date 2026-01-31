import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/widgets/app_header.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedRoomCode;
  bool _isDeleting = false;
  bool _isMigrating = false;

  Future<void> _migrateLastMessageAt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate Rooms'),
        content: const Text(
          'This will set lastMessageAt = createdAt for all rooms that don\'t have it. '
          'This is needed for proper sorting by recent activity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Migrate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMigrating = true);

    try {
      final roomsSnapshot = await _firestore.collection('rooms').get();
      int updated = 0;
      int skipped = 0;

      for (final roomDoc in roomsSnapshot.docs) {
        final data = roomDoc.data();

        // Skip if already has lastMessageAt
        if (data['lastMessageAt'] != null) {
          skipped++;
          continue;
        }

        // Set lastMessageAt to createdAt
        final createdAt = data['createdAt'] ?? Timestamp.now();
        await roomDoc.reference.update({'lastMessageAt': createdAt});
        updated++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migration complete. Updated: $updated, Skipped: $skipped'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during migration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMigrating = false);
      }
    }
  }

  Future<void> _deleteAllRooms() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Rooms'),
        content: const Text(
          'Are you sure you want to delete ALL rooms? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      // Get all rooms
      final roomsSnapshot = await _firestore.collection('rooms').get();

      // Delete each room and its subcollections
      for (final roomDoc in roomsSnapshot.docs) {
        // Delete chat subcollection
        final chatSnapshot = await _firestore
            .collection('rooms')
            .doc(roomDoc.id)
            .collection('chat')
            .get();
        for (final chatDoc in chatSnapshot.docs) {
          await chatDoc.reference.delete();
        }

        // Delete players subcollection
        final playersSnapshot = await _firestore
            .collection('rooms')
            .doc(roomDoc.id)
            .collection('players')
            .get();
        for (final playerDoc in playersSnapshot.docs) {
          await playerDoc.reference.delete();
        }

        // Delete the room document
        await roomDoc.reference.delete();
      }

      setState(() {
        _selectedRoomCode = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted ${roomsSnapshot.docs.length} rooms'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting rooms: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _deleteRoom(String roomCode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text(
          'Are you sure you want to delete room "$roomCode"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete chat subcollection
      final chatSnapshot = await _firestore
          .collection('rooms')
          .doc(roomCode)
          .collection('chat')
          .get();
      for (final chatDoc in chatSnapshot.docs) {
        await chatDoc.reference.delete();
      }

      // Delete players subcollection
      final playersSnapshot = await _firestore
          .collection('rooms')
          .doc(roomCode)
          .collection('players')
          .get();
      for (final playerDoc in playersSnapshot.docs) {
        await playerDoc.reference.delete();
      }

      // Delete the room document
      await _firestore.collection('rooms').doc(roomCode).delete();

      if (_selectedRoomCode == roomCode) {
        setState(() {
          _selectedRoomCode = null;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted room $roomCode'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting room: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                AppHeader(
                  title: 'Admin Panel',
                  backRoute: '/',
                  maxWidth: 1200,
                ),
                Expanded(
                  child: Row(
                    children: [
                      // Rooms list (left panel)
                      SizedBox(
                        width: 300,
                        child: Column(
                          children: [
                            // Migrate button
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isMigrating ? null : _migrateLastMessageAt,
                                  icon: _isMigrating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.update),
                                  label: Text(_isMigrating ? 'Migrating...' : 'Migrate lastMessageAt'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            // Delete All button
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isDeleting ? null : _deleteAllRooms,
                                  icon: _isDeleting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.delete_forever),
                                  label: Text(_isDeleting ? 'Deleting...' : 'Delete All Rooms'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(child: _buildRoomsList()),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      // Room details (right panel)
                      Expanded(
                        child: _selectedRoomCode != null
                            ? _buildRoomDetails(_selectedRoomCode!)
                            : const Center(
                                child: Text(
                                  'Select a room to view details',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('rooms')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No rooms found'));
        }

        final rooms = snapshot.data!.docs;

        return ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final roomDoc = rooms[index];
            final data = roomDoc.data() as Map<String, dynamic>;
            final roomCode = roomDoc.id;
            final question = data['question'] as String? ?? '';
            final status = data['status'] as String? ?? 'unknown';
            final evaluationMode = data['evaluationMode'] as String? ?? 'manual';
            final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

            return ListTile(
              selected: _selectedRoomCode == roomCode,
              selectedTileColor: QoomyTheme.primaryColor.withOpacity(0.1),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: QoomyTheme.primaryColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      roomCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (evaluationMode == 'ai')
                    Icon(Icons.smart_toy, size: 16, color: Colors.deepPurple.shade400),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildStatusBadge(status),
                      const Spacer(),
                      if (createdAt != null)
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.red.shade400,
                tooltip: 'Delete room',
                onPressed: () => _deleteRoom(roomCode),
              ),
              onTap: () {
                setState(() {
                  _selectedRoomCode = roomCode;
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'playing':
        color = QoomyTheme.successColor;
        break;
      case 'waiting':
        color = Colors.orange;
        break;
      case 'finished':
        color = Colors.grey;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildRoomDetails(String roomCode) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('rooms').doc(roomCode).get(),
      builder: (context, roomSnapshot) {
        if (!roomSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final roomData = roomSnapshot.data!.data() as Map<String, dynamic>?;
        if (roomData == null) {
          return const Center(child: Text('Room not found'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Room info card
              _buildInfoCard(roomCode, roomData),
              const SizedBox(height: 16),
              // Chat messages
              _buildChatSection(roomCode),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(String roomCode, Map<String, dynamic> data) {
    final question = data['question'] as String? ?? '';
    final answer = data['answer'] as String? ?? '';
    final comment = data['comment'] as String?;
    final hostName = data['hostName'] as String? ?? '';
    final evaluationMode = data['evaluationMode'] as String? ?? 'manual';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Room: $roomCode',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: evaluationMode == 'ai' ? Colors.deepPurple : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    evaluationMode.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Host: $hostName', style: TextStyle(color: Colors.grey.shade600)),
            const Divider(height: 24),
            const Text('Question:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(question),
            const SizedBox(height: 16),
            const Text('Correct Answer:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(answer),
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Host Comment:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(comment, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatSection(String roomCode) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('rooms')
          .doc(roomCode)
          .collection('chat')
          .orderBy('sentAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data!.docs;

        if (messages.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No messages yet'),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Messages (${messages.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ...messages.map((doc) => _buildMessageItem(doc)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final playerName = data['playerName'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final type = data['type'] as String? ?? 'comment';
    final isCorrect = data['isCorrect'] as bool?;
    final aiSuggestion = data['aiSuggestion'] as bool?;
    final aiConfidence = (data['aiConfidence'] as num?)?.toDouble();
    final aiReasoning = data['aiReasoning'] as String?;
    final sentAt = (data['sentAt'] as Timestamp?)?.toDate();

    final isAnswer = type == 'answer';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAnswer
            ? (isCorrect == true
                ? Colors.green.withOpacity(0.05)
                : isCorrect == false
                    ? Colors.red.withOpacity(0.05)
                    : Colors.blue.withOpacity(0.05))
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAnswer
              ? (isCorrect == true
                  ? Colors.green.withOpacity(0.3)
                  : isCorrect == false
                      ? Colors.red.withOpacity(0.3)
                      : Colors.blue.withOpacity(0.3))
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                playerName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isAnswer ? QoomyTheme.primaryColor : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  type.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
              if (isCorrect != null) ...[
                const SizedBox(width: 8),
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: isCorrect ? Colors.green : Colors.red,
                ),
                Text(
                  isCorrect ? ' CORRECT' : ' WRONG',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? Colors.green : Colors.red,
                  ),
                ),
              ],
              const Spacer(),
              if (sentAt != null)
                Text(
                  _formatDateTime(sentAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Message text
          Text(text, style: const TextStyle(fontSize: 14)),
          // AI reasoning section (always shown for admin)
          if (aiReasoning != null || aiSuggestion != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smart_toy, size: 16, color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      const Text(
                        'AI Analysis',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.deepPurple,
                        ),
                      ),
                      if (aiSuggestion != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: aiSuggestion ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            aiSuggestion ? 'SUGGESTED CORRECT' : 'SUGGESTED WRONG',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ],
                      if (aiConfidence != null) ...[
                        const Spacer(),
                        Text(
                          'Confidence: ${(aiConfidence * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.deepPurple.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (aiReasoning != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      aiReasoning,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.deepPurple.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
