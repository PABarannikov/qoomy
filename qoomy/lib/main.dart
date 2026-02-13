import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:qoomy/app.dart';
import 'package:qoomy/config/firebase_options.dart';
import 'package:qoomy/services/auth_service.dart';

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Use path-based URLs for web (e.g., /join-team/CODE instead of /#/join-team/CODE)
    usePathUrlStrategy();

    final startTime = DateTime.now();

    // Initialize Firebase (handle case where it's already initialized on Android)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Firebase already initialized (can happen on Android with google-services)
    }

    final firebaseInitTime = DateTime.now();

    // Check currentUser BEFORE awaiting authStateChanges
    final userBeforeAwait = FirebaseAuth.instance.currentUser;

    // Wait for Firebase Auth to restore persisted session before starting the app.
    if (!kIsWeb) {
      await FirebaseAuth.instance.authStateChanges().first;
    }

    final authAwaitTime = DateTime.now();
    final userAfterAwait = FirebaseAuth.instance.currentUser;

    // Initialize Crashlytics and run diagnostics (not available on web)
    if (!kIsWeb) {
      // Pass all uncaught Flutter errors to Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      final crashlytics = FirebaseCrashlytics.instance;
      final auth = FirebaseAuth.instance;

      // === DEEP AUTH DIAGNOSTICS ===

      // 1. Timing info
      final firebaseInitMs = firebaseInitTime.difference(startTime).inMilliseconds;
      final authAwaitMs = authAwaitTime.difference(firebaseInitTime).inMilliseconds;

      // 2. Secure storage state
      final storedUserId = await AuthService.getStoredUserId();
      final storedEmail = await AuthService.getStoredEmail();

      // 3. SharedPreferences inspection (Firebase Auth stores session data here)
      String sharedPrefsInfo = 'UNKNOWN';
      try {
        final prefs = await SharedPreferences.getInstance();
        final allKeys = prefs.getKeys();
        // Look for Firebase Auth keys (they contain "firebase" or "fba" or "com.google")
        final firebaseKeys = allKeys.where((k) =>
            k.toLowerCase().contains('firebase') ||
            k.toLowerCase().contains('fba') ||
            k.toLowerCase().contains('com.google') ||
            k.toLowerCase().contains('auth')).toList();
        sharedPrefsInfo = 'totalKeys=${allKeys.length}, '
            'firebaseKeys=${firebaseKeys.length}, '
            'firebaseKeyNames=$firebaseKeys';
      } catch (e) {
        sharedPrefsInfo = 'ERROR: $e';
      }

      // 4. Device info
      final deviceInfo = 'platform=${Platform.operatingSystem}, '
          'version=${Platform.operatingSystemVersion}, '
          'isPhysicalDevice=true'; // Always true for release builds

      // 5. Firebase App info
      final firebaseApp = Firebase.app();
      final firebaseInfo = 'appName=${firebaseApp.name}, '
          'projectId=${firebaseApp.options.projectId}';

      crashlytics.recordError(
        Exception(
          'AUTH_DEEP_DIAG: '
          'userBeforeAwait=${userBeforeAwait != null ? "EXISTS(${userBeforeAwait.uid})" : "NULL"}, '
          'userAfterAwait=${userAfterAwait != null ? "EXISTS(${userAfterAwait.uid})" : "NULL"}, '
          'firebaseInitMs=$firebaseInitMs, '
          'authAwaitMs=$authAwaitMs, '
          '$deviceInfo, '
          '$firebaseInfo',
        ),
        StackTrace.current,
        reason: 'Deep auth diagnostic: timing and device',
        fatal: false,
      );

      crashlytics.recordError(
        Exception(
          'AUTH_STORAGE_DIAG: '
          'secureStorageUid=${storedUserId ?? "NULL"}, '
          'secureStorageEmail=${storedEmail ?? "NULL"}, '
          'sharedPrefs=[$sharedPrefsInfo]',
        ),
        StackTrace.current,
        reason: 'Deep auth diagnostic: storage state',
        fatal: false,
      );

      // 6. Listen for delayed auth events (maybe auth comes later?)
      if (userAfterAwait == null) {
        // No user found — listen for 5 more seconds to see if one arrives
        crashlytics.recordError(
          Exception('AUTH_DELAYED_CHECK: Starting 5s delayed auth listener...'),
          StackTrace.current,
          reason: 'Deep auth diagnostic: checking for delayed auth events',
          fatal: false,
        );

        // Non-blocking: listen in background while app starts
        () async {
          try {
            final delayedUser = await auth.authStateChanges()
                .where((user) => user != null)
                .first
                .timeout(const Duration(seconds: 5), onTimeout: () => null);

            final delayMs = DateTime.now().difference(authAwaitTime).inMilliseconds;

            crashlytics.recordError(
              Exception(
                'AUTH_DELAYED_CHECK: '
                'result=${delayedUser != null ? "USER_ARRIVED(${delayedUser.uid})" : "STILL_NULL"}, '
                'delayMs=$delayMs',
              ),
              StackTrace.current,
              reason: 'Deep auth diagnostic: delayed auth result',
              fatal: false,
            );
          } catch (e) {
            crashlytics.recordError(
              Exception('AUTH_DELAYED_CHECK: ERROR=$e'),
              StackTrace.current,
              reason: 'Deep auth diagnostic: delayed check error',
              fatal: false,
            );
          }
        }();
      }

      // === FALLBACK RE-AUTHENTICATION ===
      final currentUser = auth.currentUser;
      final needsFallback = currentUser == null && storedUserId != null;

      crashlytics.recordError(
        Exception(
          'AUTH_DECISION: '
          'firebaseUser=${currentUser != null ? "EXISTS" : "NULL"}, '
          'secureStorageUid=${storedUserId ?? "NULL"}, '
          'needsFallbackAuth=$needsFallback',
        ),
        StackTrace.current,
        reason: 'Auth decision on startup',
        fatal: false,
      );

      if (needsFallback) {
        crashlytics.recordError(
          Exception(
            'AUTH_FALLBACK: Attempting re-auth for userId=$storedUserId, '
            'email=${storedEmail ?? "NULL"}',
          ),
          StackTrace.current,
          reason: 'Fallback auth: starting custom token re-auth',
          fatal: false,
        );

        try {
          final callStart = DateTime.now();
          final callable = FirebaseFunctions.instance.httpsCallable('createCustomToken');
          final result = await callable.call({'userId': storedUserId});
          final callMs = DateTime.now().difference(callStart).inMilliseconds;
          final token = result.data['token'] as String;

          crashlytics.recordError(
            Exception('AUTH_FALLBACK: Got custom token in ${callMs}ms, signing in...'),
            StackTrace.current,
            reason: 'Fallback auth: received custom token',
            fatal: false,
          );

          final signInStart = DateTime.now();
          final userCredential = await auth.signInWithCustomToken(token);
          final signInMs = DateTime.now().difference(signInStart).inMilliseconds;

          crashlytics.recordError(
            Exception(
              'AUTH_FALLBACK: SUCCESS in ${signInMs}ms! '
              'uid=${userCredential.user?.uid ?? "NULL"}, '
              'email=${userCredential.user?.email ?? "NULL"}, '
              'providers=${userCredential.user?.providerData.map((p) => p.providerId).toList()}',
            ),
            StackTrace.current,
            reason: 'Fallback auth: sign-in successful',
            fatal: false,
          );
        } catch (e, st) {
          crashlytics.recordError(
            Exception(
              'AUTH_FALLBACK: FAILED! '
              'error=$e, '
              'errorType=${e.runtimeType}, '
              'storedUserId=$storedUserId, '
              'storedEmail=${storedEmail ?? "NULL"}',
            ),
            st,
            reason: 'Fallback auth: sign-in failed',
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
