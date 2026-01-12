import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:qoomy/app.dart';
import 'package:qoomy/config/firebase_options.dart';

void main() async {
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

  runApp(
    const ProviderScope(
      child: QoomyApp(),
    ),
  );
}
