import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/config/theme.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  final String roomCode;

  const LobbyScreen({super.key, required this.roomCode});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomProvider(widget.roomCode));
    final playersAsync = ref.watch(playersProvider(widget.roomCode));
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // Listen for room status changes
    ref.listen(roomProvider(widget.roomCode), (previous, next) {
      next.whenData((room) {
        if (room != null && room.status == RoomStatus.playing) {
          context.go('/game/${widget.roomCode}');
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Lobby'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleLeave(currentUser?.id),
        ),
      ),
      body: roomAsync.when(
        data: (room) {
          if (room == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Room not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            );
          }

          final isHost = currentUser?.id == room.hostId;

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Room Code Card
                  Card(
                    color: QoomyTheme.primaryColor,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Text(
                            'ROOM CODE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.roomCode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: widget.roomCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Room code copied!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy, color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share this code with players',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Room Info
                  Row(
                    children: [
                      _buildInfoChip(
                        icon: Icons.person,
                        label: 'Host: ${room.hostName}',
                      ),
                      const SizedBox(width: 12),
                      _buildInfoChip(
                        icon: room.evaluationMode == EvaluationMode.ai
                            ? Icons.smart_toy_outlined
                            : Icons.person_outline,
                        label: room.evaluationMode == EvaluationMode.ai
                            ? 'AI Mode'
                            : 'Manual Mode',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Players Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Players',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      playersAsync.when(
                        data: (players) => Text(
                          '${players.length}/ joined',
                          style: const TextStyle(
                            color: QoomyTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Players List
                  Expanded(
                    child: playersAsync.when(
                      data: (players) {
                        if (players.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Waiting for players...',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: players.length,
                          itemBuilder: (context, index) {
                            final player = players[index];
                            final isCurrentUser = player.id == currentUser?.id;
                            final isPlayerHost = player.id == room.hostId;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isPlayerHost
                                      ? QoomyTheme.secondaryColor
                                      : QoomyTheme.primaryColor.withOpacity(0.1),
                                  child: Text(
                                    player.name.isNotEmpty
                                        ? player.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: isPlayerHost
                                          ? Colors.white
                                          : QoomyTheme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      player.name,
                                      style: TextStyle(
                                        fontWeight: isCurrentUser
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    if (isCurrentUser)
                                      Text(
                                        ' (You)',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: isPlayerHost
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: QoomyTheme.secondaryColor,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'HOST',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, __) => const Center(child: Text('Error loading players')),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Start/Leave Buttons
                  if (isHost)
                    playersAsync.when(
                      data: (players) => ElevatedButton(
                        onPressed: players.isEmpty || _isStarting
                            ? null
                            : () => _startGame(),
                        child: _isStarting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Start Game'),
                      ),
                      loading: () => const ElevatedButton(
                        onPressed: null,
                        child: Text('Start Game'),
                      ),
                      error: (_, __) => const ElevatedButton(
                        onPressed: null,
                        child: Text('Start Game'),
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => _handleLeave(currentUser?.id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: QoomyTheme.errorColor,
                        side: const BorderSide(color: QoomyTheme.errorColor),
                      ),
                      child: const Text('Leave Room'),
                    ),
                  ],
                ),
              ),
            ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startGame() async {
    setState(() => _isStarting = true);
    await ref.read(roomNotifierProvider.notifier).startGame(widget.roomCode);
    if (mounted) {
      setState(() => _isStarting = false);
    }
  }

  Future<void> _handleLeave(String? userId) async {
    if (userId != null) {
      await ref.read(roomNotifierProvider.notifier).leaveRoom(
            widget.roomCode,
            userId,
          );
    }
    if (mounted) {
      context.go('/');
    }
  }
}
