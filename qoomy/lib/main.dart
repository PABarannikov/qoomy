import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:qoomy/app.dart';
import 'package:qoomy/config/firebase_options.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Use path-based URLs for web (e.g., /join-team/CODE instead of /#/join-team/CODE)
    usePathUrlStrategy();

    // Initialize Firebase (handle case where it's already initialized on Android)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Firebase already initialized (can happen on Android with google-services)
    }

    // Wait for Firebase Auth to restore persisted session before starting the app.
    // Without this, some devices (Samsung S25, Galaxy Z Fold4) show the login screen
    // because the auth state stream hasn't emitted the restored user yet.
    if (!kIsWeb) {
      await FirebaseAuth.instance.authStateChanges().first;
    }

    // Initialize Crashlytics (not available on web)
    if (!kIsWeb) {
      // Pass all uncaught Flutter errors to Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Log auth state on startup for diagnostics
      final currentUser = FirebaseAuth.instance.currentUser;
      final authStatus = currentUser != null ? 'SIGNED_IN' : 'SIGNED_OUT';
      FirebaseCrashlytics.instance.recordError(
        Exception('AUTH_DIAG: $authStatus, user=${currentUser?.uid ?? "NULL"}, '
            'email=${currentUser?.email ?? "NULL"}, '
            'providers=${currentUser?.providerData.map((p) => p.providerId).toList()}'),
        StackTrace.current,
        reason: 'Auth state diagnostic on startup',
        fatal: false,
      );
    }

    runApp(
      const ProviderScope(
        child: QoomyApp(),
      ),
    );
  }, (error, stack) {
    // Pass all uncaught async errors to Crashlytics
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}
