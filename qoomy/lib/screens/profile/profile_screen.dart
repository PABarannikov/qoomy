import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/stats_provider.dart';
import 'package:qoomy/models/player_stats_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/widgets/app_header.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: Column(
              children: [
                AppHeader(
                  title: l10n.profile,
                  backRoute: '/',
                ),
                Expanded(
                  child: currentUser.when(
                    data: (user) {
                      if (user == null) {
                        return Center(child: Text(l10n.notLoggedIn));
                      }
                      return _buildProfileContent(context, ref, user, l10n);
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContent(
    BuildContext context,
    WidgetRef ref,
    dynamic user,
    AppLocalizations l10n,
  ) {
    final statsAsync = ref.watch(playerStatsProvider(user.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: QoomyTheme.primaryColor.withOpacity(0.1),
                    child: Text(
                      user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: QoomyTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Statistics card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bar_chart, color: QoomyTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l10n.statistics,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: QoomyTheme.primaryColor,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  statsAsync.when(
                    data: (stats) => _buildStatsGrid(context, stats, l10n),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('Error loading stats: $e'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Logout button
          OutlinedButton.icon(
            onPressed: () => _showLogoutConfirmation(context, ref, l10n),
            icon: const Icon(Icons.logout),
            label: Text(l10n.logout),
            style: OutlinedButton.styleFrom(
              foregroundColor: QoomyTheme.errorColor,
              side: const BorderSide(color: QoomyTheme.errorColor),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, PlayerStats stats, AppLocalizations l10n) {
    return Column(
      children: [
        // Questions row
        Row(
          children: [
            Expanded(
              child: _buildStatItem(
                icon: Icons.quiz,
                label: l10n.questionsAsHost,
                value: stats.questionsAsHost.toString(),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem(
                icon: Icons.person,
                label: l10n.questionsAsPlayer,
                value: stats.questionsAsPlayer.toString(),
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Answers row
        Row(
          children: [
            Expanded(
              child: _buildStatItem(
                icon: Icons.check_circle,
                label: l10n.correctAnswersTotal,
                value: stats.correctAnswersTotal.toString(),
                color: QoomyTheme.successColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem(
                icon: Icons.cancel,
                label: l10n.wrongAnswers,
                value: stats.wrongAnswers.toString(),
                color: QoomyTheme.errorColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // First/not first row
        Row(
          children: [
            Expanded(
              child: _buildStatItem(
                icon: Icons.emoji_events,
                label: l10n.correctFirst,
                value: stats.correctAnswersFirst.toString(),
                color: Colors.amber,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem(
                icon: Icons.looks_two,
                label: l10n.correctNotFirst,
                value: stats.correctAnswersNotFirst.toString(),
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Total points - full width
        _buildStatItem(
          icon: Icons.star,
          label: l10n.totalPoints,
          value: stats.totalPoints.toStringAsFixed(1),
          color: QoomyTheme.primaryColor,
          isLarge: true,
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isLarge = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isLarge ? 16 : 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: isLarge ? 32 : 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isLarge ? 28 : 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isLarge ? 14 : 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.confirmLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
            style: TextButton.styleFrom(foregroundColor: QoomyTheme.errorColor),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}
