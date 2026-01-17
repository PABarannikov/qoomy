import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qoomy/config/router.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/providers/locale_provider.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/services/badge_service.dart';
import 'package:qoomy/services/push_notification_service.dart';

class QoomyApp extends ConsumerStatefulWidget {
  const QoomyApp({super.key});

  @override
  ConsumerState<QoomyApp> createState() => _QoomyAppState();
}

class _QoomyAppState extends ConsumerState<QoomyApp> {
  String? _lastUserId;
  bool _initializedForUser = false;

  Future<void> _initializeUserServices(String userId) async {
    // Small delay to allow Firebase auth token to propagate to Firestore
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted && _lastUserId == userId) {
      setState(() => _initializedForUser = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    // Watch current user and sync badge count with unread messages
    final currentUser = ref.watch(currentUserProvider);
    currentUser.whenData((user) {
      if (user != null) {
        // Initialize services only once per user, with delay for auth propagation
        if (_lastUserId != user.id) {
          _lastUserId = user.id;
          _initializedForUser = false;
          _initializeUserServices(user.id);
          PushNotificationService.init(user.id);
        }

        // Only start badge sync after initialization delay
        if (_initializedForUser) {
          ref.watch(badgeSyncProvider(user.id));
        }
      } else if (_lastUserId != null) {
        // User logged out - clean up
        PushNotificationService.removeToken();
        _lastUserId = null;
        _initializedForUser = false;
      }
    });

    return MaterialApp.router(
      title: 'Qoomy',
      debugShowCheckedModeBanner: false,
      theme: QoomyTheme.lightTheme,
      darkTheme: QoomyTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      locale: locale,
      supportedLocales: const [
        Locale('ru'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
