import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qoomy/config/router.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/providers/locale_provider.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/services/badge_service.dart';

class QoomyApp extends ConsumerStatefulWidget {
  const QoomyApp({super.key});

  @override
  ConsumerState<QoomyApp> createState() => _QoomyAppState();
}

class _QoomyAppState extends ConsumerState<QoomyApp> {

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    // Watch current user and sync badge count with unread messages
    final currentUser = ref.watch(currentUserProvider);
    currentUser.whenData((user) {
      if (user != null) {
        // Initialize badge sync for logged in user
        ref.watch(badgeSyncProvider(user.id));
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
