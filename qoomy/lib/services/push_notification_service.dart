import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static String? _currentUserId;

  /// Initialize push notifications for iOS only
  static Future<void> init(String userId) async {
    // Only initialize for iOS
    if (!Platform.isIOS) {
      debugPrint('Push notifications: Skipping - not iOS');
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
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  /// Save token to Firestore under user's fcmTokens collection
  static Future<void> _saveTokenToFirestore(String token) async {
    if (_currentUserId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': 'ios',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved for iOS');
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
    if (_currentUserId == null) return;

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('fcmTokens')
            .doc(token)
            .delete();

        debugPrint('FCM token removed');
      }
    } catch (e) {
      debugPrint('Error removing FCM token: $e');
    }

    _currentUserId = null;
  }
}
