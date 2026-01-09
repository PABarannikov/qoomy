import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/team_provider.dart';
import 'package:qoomy/models/team_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';

class TeamDetailsScreen extends ConsumerWidget {
  final String teamId;

  const TeamDetailsScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamProvider(teamId));
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teams),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/teams'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
          child: teamAsync.when(
            data: (team) {
              if (team == null) {
                return Center(child: Text(l10n.teamNotFound));
              }
              final userId = currentUser.valueOrNull?.id ?? '';
              return _buildTeamDetails(context, ref, team, userId, l10n);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamDetails(
    BuildContext context,
    WidgetRef ref,
    TeamModel team,
    String userId,
    AppLocalizations l10n,
  ) {
    final isOwner = team.isOwner(userId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Team header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: QoomyTheme.primaryColor.withOpacity(0.1),
                    child: Text(
                      team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: QoomyTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    team.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${team.memberCount} ${l10n.members.toLowerCase()}',
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

          // Invite code section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: QoomyTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l10n.inviteCode,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: QoomyTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            team.inviteCode,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: team.inviteCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.inviteCodeCopied)),
                            );
                          },
                          tooltip: l10n.inviteCodeCopied,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final text = '${l10n.joinTeam}: ${team.name}\n${l10n.inviteCode}: ${team.inviteCode}';
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.inviteCodeCopied)),
                        );
                      },
                      icon: const Icon(Icons.share),
                      label: Text(l10n.shareInvite),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Members section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people, color: QoomyTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l10n.members,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: QoomyTheme.primaryColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${team.memberCount}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...team.members.map((member) => _buildMemberTile(
                        context,
                        ref,
                        team,
                        member,
                        userId,
                        isOwner,
                        l10n,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          if (isOwner)
            OutlinedButton.icon(
              onPressed: () => _showDeleteConfirmation(context, ref, team, l10n),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.deleteTeam),
              style: OutlinedButton.styleFrom(
                foregroundColor: QoomyTheme.errorColor,
                side: BorderSide(color: QoomyTheme.errorColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _showLeaveConfirmation(context, ref, team.id, userId, l10n),
              icon: const Icon(Icons.exit_to_app),
              label: Text(l10n.leaveTeam),
              style: OutlinedButton.styleFrom(
                foregroundColor: QoomyTheme.errorColor,
                side: BorderSide(color: QoomyTheme.errorColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMemberTile(
    BuildContext context,
    WidgetRef ref,
    TeamModel team,
    TeamMember member,
    String userId,
    bool isOwner,
    AppLocalizations l10n,
  ) {
    final isMemberOwner = member.role == TeamMemberRole.owner;
    final isCurrentUser = member.id == userId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isMemberOwner
                ? Colors.amber.withOpacity(0.2)
                : QoomyTheme.primaryColor.withOpacity(0.1),
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isMemberOwner ? Colors.amber.shade700 : QoomyTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${l10n.you})',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMemberOwner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    l10n.owner,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.amber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else if (isOwner && !isCurrentUser)
            IconButton(
              icon: Icon(Icons.remove_circle_outline, color: QoomyTheme.errorColor, size: 20),
              onPressed: () => _showRemoveMemberConfirmation(
                context,
                ref,
                team.id,
                member,
                userId,
                l10n,
              ),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }

  void _showLeaveConfirmation(
    BuildContext context,
    WidgetRef ref,
    String teamId,
    String userId,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.leaveTeam),
        content: Text(l10n.confirmLeaveTeam),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.hide),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(teamNotifierProvider.notifier).leaveTeam(teamId, userId);
              if (context.mounted) {
                context.go('/teams');
              }
            },
            style: TextButton.styleFrom(foregroundColor: QoomyTheme.errorColor),
            child: Text(l10n.leaveTeam),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    TeamModel team,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTeam),
        content: Text(l10n.confirmDeleteTeam),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.hide),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(teamNotifierProvider.notifier).deleteTeam(team.id);
              if (context.mounted) {
                context.go('/teams');
              }
            },
            style: TextButton.styleFrom(foregroundColor: QoomyTheme.errorColor),
            child: Text(l10n.deleteTeam),
          ),
        ],
      ),
    );
  }

  void _showRemoveMemberConfirmation(
    BuildContext context,
    WidgetRef ref,
    String teamId,
    TeamMember member,
    String requesterId,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from the team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.hide),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(teamServiceProvider).removeMember(teamId, member.id, requesterId);
              ref.invalidate(teamProvider(teamId));
            },
            style: TextButton.styleFrom(foregroundColor: QoomyTheme.errorColor),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
