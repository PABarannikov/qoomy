import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/widgets/app_header.dart';

enum RoleFilter { all, host, player }
enum StatusFilter { all, active }
enum UnreadFilter { all, unread }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  RoleFilter _roleFilter = RoleFilter.all;
  StatusFilter _statusFilter = StatusFilter.all;
  UnreadFilter _unreadFilter = UnreadFilter.all;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: Column(
              children: [
                // Shared header with Qoomy title
                AppHeader(
                  showBackButton: false,
                  titleWidget: Text(
                    'Qoomy',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: QoomyTheme.primaryColor,
                    ),
                  ),
                  showTeamsButton: true,
                ),
                // Filters
                _buildFilters(l10n),
                Expanded(
                  child: currentUser.when(
                    data: (user) {
                      if (user == null) {
                        return Center(child: Text(l10n.pleaseLogin));
                      }
                      return _buildRoomsList(context, ref, user.id);
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
                // Bottom buttons
                _buildBottomButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Role filter
          _buildIconFilterChip(
            icon: Icons.apps,
            tooltip: l10n.all,
            isSelected: _roleFilter == RoleFilter.all,
            onTap: () => setState(() => _roleFilter = RoleFilter.all),
          ),
          const SizedBox(width: 8),
          _buildIconFilterChip(
            icon: Icons.star,
            tooltip: l10n.asHost,
            isSelected: _roleFilter == RoleFilter.host,
            onTap: () => setState(() => _roleFilter = RoleFilter.host),
          ),
          const SizedBox(width: 8),
          _buildIconFilterChip(
            icon: Icons.person,
            tooltip: l10n.asPlayer,
            isSelected: _roleFilter == RoleFilter.player,
            onTap: () => setState(() => _roleFilter = RoleFilter.player),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 28, color: Colors.grey.shade300),
          const SizedBox(width: 12),
          // Status filter
          _buildIconFilterChip(
            icon: Icons.bolt,
            tooltip: l10n.active,
            isSelected: _statusFilter == StatusFilter.active,
            onTap: () => setState(() => _statusFilter = _statusFilter == StatusFilter.active ? StatusFilter.all : StatusFilter.active),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 28, color: Colors.grey.shade300),
          const SizedBox(width: 12),
          // Unread filter
          _buildIconFilterChip(
            icon: Icons.markunread,
            tooltip: l10n.unread,
            isSelected: _unreadFilter == UnreadFilter.unread,
            onTap: () => setState(() => _unreadFilter = _unreadFilter == UnreadFilter.unread ? UnreadFilter.all : UnreadFilter.unread),
          ),
        ],
      ),
    );
  }

  Widget _buildIconFilterChip({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? QoomyTheme.primaryColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? QoomyTheme.primaryColor : Colors.grey.shade300,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildRoomsList(BuildContext context, WidgetRef ref, String userId) {
    final hostedRoomsAsync = ref.watch(userHostedRoomsProvider(userId));
    final joinedRoomsAsync = ref.watch(userJoinedRoomsProvider(userId));

    return hostedRoomsAsync.when(
      data: (hostedRooms) => joinedRoomsAsync.when(
        data: (joinedRooms) {
          // Filter out rooms where user is host from joined rooms
          final playerRooms = joinedRooms
              .where((r) => r.hostId != userId)
              .toList();

          // Combine all rooms and sort by creation time (newest first)
          var allRooms = <MapEntry<RoomModel, bool>>[];
          for (final room in hostedRooms) {
            allRooms.add(MapEntry(room, true)); // isHost = true
          }
          for (final room in playerRooms) {
            allRooms.add(MapEntry(room, false)); // isHost = false
          }

          // Apply role filter
          if (_roleFilter == RoleFilter.host) {
            allRooms = allRooms.where((e) => e.value).toList();
          } else if (_roleFilter == RoleFilter.player) {
            allRooms = allRooms.where((e) => !e.value).toList();
          }

          // Apply status filter
          if (_statusFilter == StatusFilter.active) {
            allRooms = allRooms.where((e) => e.key.status != RoomStatus.finished).toList();
          }

          // Note: Unread filter is applied in the UI by checking unreadCountProvider for each room
          // The filter just hides rooms with 0 unread count when enabled

          allRooms.sort((a, b) => b.key.createdAt.compareTo(a.key.createdAt));

          if (allRooms.isEmpty) {
            // Check if we have rooms but they're filtered out
            final hasAnyRooms = hostedRooms.isNotEmpty || playerRooms.isNotEmpty;
            if (hasAnyRooms) {
              return _buildNoMatchingState(context);
            }
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userHostedRoomsProvider(userId));
              ref.invalidate(userJoinedRoomsProvider(userId));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...allRooms.map((entry) => _buildRoomCard(
                  context,
                  ref,
                  entry.key,
                  isHost: entry.value,
                  userId: userId,
                )),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildRoomCard(
    BuildContext context,
    WidgetRef ref,
    RoomModel room, {
    required bool isHost,
    required String userId,
  }) {
    final l10n = AppLocalizations.of(context);
    final unreadCountAsync = ref.watch(unreadCountProvider((roomCode: room.code, userId: userId)));
    final hasCorrectAnswerAsync = ref.watch(hasCorrectAnswerProvider(room.code));

    // Determine status color and text based on room status and correct answer
    Color statusColor;
    String statusText;

    if (room.status == RoomStatus.finished) {
      statusColor = Colors.grey;
      statusText = l10n.finished;
    } else if (room.status == RoomStatus.playing) {
      final hasCorrect = hasCorrectAnswerAsync.valueOrNull ?? false;
      if (hasCorrect) {
        statusColor = QoomyTheme.successColor;
        statusText = l10n.correctAnswerGiven;
      } else {
        statusColor = Colors.orange;
        statusText = l10n.noCorrectAnswer;
      }
    } else {
      statusColor = Colors.orange;
      statusText = l10n.waiting;
    }

    // Apply unread filter: hide rooms with 0 unread when filter is active
    if (_unreadFilter == UnreadFilter.unread) {
      final unreadCount = unreadCountAsync.valueOrNull ?? 0;
      if (unreadCount == 0) {
        return const SizedBox.shrink();
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToRoom(context, room, isHost, userId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Room code
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: QoomyTheme.primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      room.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Unread badge
                  unreadCountAsync.when(
                    data: (count) => count > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: QoomyTheme.secondaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              count > 99 ? '99+' : count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  // Role badge
                  if (isHost)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            l10n.host,
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Question
              Text(
                room.question,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Footer
              Row(
                children: [
                  Icon(
                    room.evaluationMode == EvaluationMode.ai
                        ? Icons.smart_toy
                        : Icons.person,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    room.evaluationMode == EvaluationMode.ai ? l10n.aiMode : l10n.manual,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(room.createdAt, l10n),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.quiz_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noRoomsYet,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noRoomsDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchingState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list_off,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noMatchingQuestions,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}${l10n.minutesAgo}';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}${l10n.hoursAgo}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}${l10n.daysAgo}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _navigateToRoom(BuildContext context, RoomModel room, bool isHost, String userId) {
    if (room.status == RoomStatus.finished) {
      context.push('/results/${room.code}');
    } else {
      context.push('/game/${room.code}');
    }
  }

  Widget _buildBottomButtons(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/join-room'),
              icon: const Icon(Icons.login_rounded),
              label: Text(l10n.joinRoom),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade400),
                foregroundColor: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push('/create-room'),
              icon: const Icon(Icons.add),
              label: Text(l10n.createRoom),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
