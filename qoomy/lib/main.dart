import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:qoomy/app.dart';
import 'package:qoomy/config/firebase_options.dart';
import 'package:qoomy/services/auth_service.dart';

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

    // Warm up Firestore gRPC connection in the background (Android cold start is slow)
    if (!kIsWeb) {
      FirebaseFirestore.instance.collection('rooms').limit(1).get();
    }

    // Wait for Firebase Auth to restore persisted session before starting the app.
    if (!kIsWeb) {
      await FirebaseAuth.instance.authStateChanges().first;
    }

    // Initialize Crashlytics (not available on web)
    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Fallback re-authentication (S25 workaround)
      final auth = FirebaseAuth.instance;
      final storedUserId = await AuthService.getStoredUserId();
      final needsFallback = auth.currentUser == null && storedUserId != null;

      if (needsFallback) {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('createCustomToken');
          final result = await callable.call({'userId': storedUserId});
          final token = result.data['token'] as String;
          await auth.signInWithCustomToken(token);
        } catch (e, st) {
          FirebaseCrashlytics.instance.recordError(e, st,
            reason: 'Fallback auth failed for userId=$storedUserId',
            fatal: false,
          );
        }
      }
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
