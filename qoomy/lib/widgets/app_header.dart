import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/locale_provider.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';

class AppHeader extends ConsumerWidget {
  final String? title;
  final Widget? titleWidget;
  final bool showBackButton;
  final String backRoute;
  final VoidCallback? onBack;
  final bool showTeamsButton;
  final List<PopupMenuEntry<String>>? extraMenuItems;
  final void Function(String)? onMenuItemSelected;

  const AppHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.showBackButton = true,
    this.backRoute = '/',
    this.onBack,
    this.showTeamsButton = false,
    this.extraMenuItems,
    this.onMenuItemSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Back button
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack ?? () => context.go(backRoute),
            )
          else
            const SizedBox(width: 48), // Placeholder for alignment

          const Spacer(),

          // Title
          if (titleWidget != null)
            titleWidget!
          else if (title != null)
            Text(
              title!,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

          const Spacer(),

          // Teams button (optional, shown on home screen)
          if (showTeamsButton)
            IconButton(
              icon: const Icon(Icons.group),
              onPressed: () => context.push('/teams'),
              tooltip: l10n.teams,
            ),

          // Language toggle
          IconButton(
            icon: Text(
              ref.watch(localeProvider).languageCode.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () {
              ref.read(localeProvider.notifier).toggleLocale();
            },
            tooltip: l10n.language,
          ),

          // Profile button with popup menu
          currentUser.when(
            data: (user) => user != null
                ? PopupMenuButton<String>(
                    icon: CircleAvatar(
                      radius: 14,
                      backgroundColor: QoomyTheme.primaryColor.withOpacity(0.1),
                      backgroundImage: user.avatarUrl != null
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? Text(
                              user.displayName.isNotEmpty
                                  ? user.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: QoomyTheme.primaryColor,
                              ),
                            )
                          : null,
                    ),
                    onSelected: (value) async {
                      if (value == 'logout') {
                        await ref.read(authNotifierProvider.notifier).signOut();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      } else {
                        onMenuItemSelected?.call(value);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              '${l10n.games}: ${user.gamesPlayed} | ${l10n.wins}: ${user.gamesWon}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      if (extraMenuItems != null) ...extraMenuItems!,
                      PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            const Icon(Icons.logout, size: 20),
                            const SizedBox(width: 8),
                            Text(l10n.logout),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: 48),
            loading: () => const SizedBox(width: 48),
            error: (_, __) => const SizedBox(width: 48),
          ),
        ],
      ),
    );
  }
}
