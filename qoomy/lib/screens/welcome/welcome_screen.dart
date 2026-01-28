import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/providers/team_provider.dart';
import 'package:qoomy/widgets/app_header.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: Column(
              children: [
                // Header
                const AppHeader(
                  showBackButton: false,
                  titleWidget: Text(
                    'Qoomy',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: QoomyTheme.primaryColor,
                    ),
                  ),
                  showTeamsButton: false,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        // Welcome message
                        Text(
                          l10n.welcomeTitle,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        // App description
                        Text(
                          l10n.welcomeDescription,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.start,
                        ),
                        const SizedBox(height: 24),

                        // Join Team button
                        _buildBigButton(
                          context: context,
                          icon: Icons.group_add,
                          title: l10n.joinTeam,
                          subtitle: l10n.joinTeamDescription,
                          color: Colors.blue,
                          onTap: () => context.push('/join-team'),
                        ),
                        const SizedBox(height: 12),

                        // Create Team button
                        _buildBigButton(
                          context: context,
                          icon: Icons.group,
                          title: l10n.createTeam,
                          subtitle: l10n.createTeamDescription,
                          color: Colors.blue.shade700,
                          onTap: () => context.push('/teams/create'),
                        ),
                        const SizedBox(height: 24),

                        // Join Question button
                        _buildBigButton(
                          context: context,
                          icon: Icons.quiz,
                          title: l10n.joinQuestion,
                          subtitle: l10n.joinRoomDescription,
                          color: QoomyTheme.primaryColor,
                          onTap: () => context.push('/join-room'),
                        ),
                        const SizedBox(height: 12),

                        // Ask Question button
                        _buildBigButton(
                          context: context,
                          icon: Icons.add_circle,
                          title: l10n.askQuestion,
                          subtitle: l10n.askQuestionDescription,
                          color: QoomyTheme.primaryColor.withBlue(180),
                          onTap: () => context.push('/create-room'),
                        ),

                        const SizedBox(height: 24),

                        // Skip link
                        TextButton(
                          onPressed: () {
                            ref.read(welcomeSkippedProvider.notifier).state = true;
                            context.go('/');
                          },
                          child: Text(
                            l10n.skipForNow,
                            style: TextStyle(
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBigButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
