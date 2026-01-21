import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static String? _currentUserId;

  /// Initialize push notifications for iOS and Android
  static Future<void> init(String userId) async {
    // Skip on web
    if (kIsWeb) {
      debugPrint('Push notifications: Skipping - web platform');
      return;
    }

    // Only initialize for iOS and Android
    if (!Platform.isIOS && !Platform.isAndroid) {
      debugPrint('Push notifications: Skipping - unsupported platform');
      return;
    }

    _currentUserId = userId;

    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('Push notification permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get and save FCM token
      await _saveToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((token) {
        _saveTokenToFirestore(token);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background/terminated message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Check if app was opened from a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }
    }
  }

  /// Save FCM token to Firestore
  static Future<void> _saveToken() async {
    try {
      debugPrint('FCM: Requesting token...');

      // On iOS, we need the APNs token first
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        debugPrint('FCM: APNs token: ${apnsToken != null ? "obtained (${apnsToken.length} chars)" : "NULL"}');

        if (apnsToken == null) {
          debugPrint('FCM: No APNs token - waiting and retrying...');
          // Wait a bit and retry - APNs token may not be ready immediately
          await Future.delayed(const Duration(seconds: 2));
          final retryApns = await _messaging.getAPNSToken();
          debugPrint('FCM: APNs token retry: ${retryApns != null ? "obtained" : "still NULL"}');
        }
      }

      final token = await _messaging.getToken();
      debugPrint('FCM: FCM token: ${token != null ? "obtained (${token.length} chars)" : "NULL"}');

      if (token != null) {
        await _saveTokenToFirestore(token);
      } else {
        debugPrint('FCM: Failed to get FCM token');
      }
    } catch (e, st) {
      debugPrint('Error getting FCM token: $e');
      debugPrint('Stack trace: $st');
    }
  }

  /// Save token to Firestore under user's fcmTokens collection
  static Future<void> _saveTokenToFirestore(String token) async {
    if (_currentUserId == null) return;

    final platform = Platform.isIOS ? 'ios' : 'android';

    try {
      await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': platform,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved for $platform');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Handle foreground messages (app is open)
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.notification?.title}');
    // Badge is handled by the existing badge_service.dart when app is open
  }

  /// Handle message tap (user tapped on notification)
  static void _handleMessageTap(RemoteMessage message) {
    debugPrint('Message tapped: ${message.data}');
    // Could navigate to specific room here if needed
    // final roomCode = message.data['roomCode'];
  }

  /// Remove FCM token on logout
  static Future<void> removeToken() async {
    // Skip on web and unsupported platforms
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;

    final userIdToRemove = _currentUserId;
    if (userIdToRemove == null) {
      debugPrint('FCM: No user ID to remove token for');
      return;
    }

    // Clear the current user ID immediately to prevent race conditions
    _currentUserId = null;

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore
            .collection('users')
            .doc(userIdToRemove)
            .collection('fcmTokens')
            .doc(token)
            .delete();

        debugPrint('FCM token removed for user $userIdToRemove');
      } else {
        debugPrint('FCM: No token to remove');
      }
    } catch (e) {
      debugPrint('Error removing FCM token: $e');
    }
  }
}
