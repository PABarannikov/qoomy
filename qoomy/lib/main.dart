import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
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

    // Initialize Crashlytics (not available on web)
    if (!kIsWeb) {
      // Pass all uncaught Flutter errors to Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
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
