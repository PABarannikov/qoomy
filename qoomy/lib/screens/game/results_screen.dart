import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/config/theme.dart';

class ResultsScreen extends ConsumerWidget {
  final String roomCode;

  const ResultsScreen({super.key, required this.roomCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersAsync = ref.watch(playersProvider(roomCode));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              // Trophy Icon
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    size: 60,
                    color: Color(0xFFFFD700),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Game Over!',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Final Leaderboard',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Leaderboard
              Expanded(
                child: playersAsync.when(
                  data: (players) {
                    final sortedPlayers = List<Player>.from(players)
                      ..sort((a, b) => b.score.compareTo(a.score));

                    if (sortedPlayers.isEmpty) {
                      return const Center(child: Text('No players'));
                    }

                    return Column(
                      children: [
                        // Top 3 Podium
                        if (sortedPlayers.isNotEmpty) _buildPodium(sortedPlayers),
                        const SizedBox(height: 24),

                        // Full Rankings
                        Expanded(
                          child: ListView.builder(
                            itemCount: sortedPlayers.length,
                            itemBuilder: (context, index) {
                              final player = sortedPlayers[index];
                              final rank = index + 1;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _getRankColor(rank),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: rank <= 3
                                          ? Icon(
                                              _getRankIcon(rank),
                                              color: Colors.white,
                                              size: 20,
                                            )
                                          : Text(
                                              '$rank',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    player.name,
                                    style: TextStyle(
                                      fontWeight: rank <= 3
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: QoomyTheme.primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${player.score} pts',
                                      style: TextStyle(
                                        color: QoomyTheme.primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Center(child: Text('Error loading results')),
                ),
              ),
              const SizedBox(height: 24),

              // Back to Home Button
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to Home'),
              ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildPodium(List<Player> sortedPlayers) {
    final first = sortedPlayers.isNotEmpty ? sortedPlayers[0] : null;
    final second = sortedPlayers.length > 1 ? sortedPlayers[1] : null;
    final third = sortedPlayers.length > 2 ? sortedPlayers[2] : null;

    return SizedBox(
      height: 180,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Second Place
          if (second != null)
            _buildPodiumPlace(
              player: second,
              rank: 2,
              height: 100,
              color: const Color(0xFFC0C0C0),
            )
          else
            const SizedBox(width: 80),

          const SizedBox(width: 12),

          // First Place
          if (first != null)
            _buildPodiumPlace(
              player: first,
              rank: 1,
              height: 140,
              color: const Color(0xFFFFD700),
            )
          else
            const SizedBox(width: 100),

          const SizedBox(width: 12),

          // Third Place
          if (third != null)
            _buildPodiumPlace(
              player: third,
              rank: 3,
              height: 80,
              color: const Color(0xFFCD7F32),
            )
          else
            const SizedBox(width: 80),
        ],
      ),
    );
  }

  Widget _buildPodiumPlace({
    required Player player,
    required int rank,
    required double height,
    required Color color,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Crown for first place
        if (rank == 1)
          const Icon(
            Icons.workspace_premium,
            color: Color(0xFFFFD700),
            size: 32,
          ),

        // Avatar
        CircleAvatar(
          radius: rank == 1 ? 32 : 24,
          backgroundColor: color.withOpacity(0.3),
          child: Text(
            player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: rank == 1 ? 24 : 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Name
        SizedBox(
          width: rank == 1 ? 100 : 80,
          child: Text(
            player.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: rank == 1 ? 14 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // Score
        Text(
          '${player.score}',
          style: TextStyle(
            fontSize: rank == 1 ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 8),

        // Podium block
        Container(
          width: rank == 1 ? 100 : 80,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return Colors.grey;
    }
  }

  IconData _getRankIcon(int rank) {
    switch (rank) {
      case 1:
        return Icons.emoji_events;
      case 2:
        return Icons.workspace_premium;
      case 3:
        return Icons.military_tech;
      default:
        return Icons.circle;
    }
  }
}
