import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/locale_provider.dart';
import 'package:qoomy/l10n/app_localizations.dart';

class AppHeader extends ConsumerWidget {
  final String? title;
  final Widget? titleWidget;
  final bool showBackButton;
  final String backRoute;
  final VoidCallback? onBack;

  const AppHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.showBackButton = true,
    this.backRoute = '/',
    this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              final currentLocale = ref.read(localeProvider);
              final newLocale = currentLocale.languageCode == 'en'
                  ? const Locale('ru')
                  : const Locale('en');
              ref.read(localeProvider.notifier).state = newLocale;
            },
          ),

          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
            tooltip: l10n.logout,
          ),
        ],
      ),
    );
  }
}
