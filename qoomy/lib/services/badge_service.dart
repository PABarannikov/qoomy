import 'dart:async';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/providers/team_provider.dart';
import 'package:qoomy/services/room_service.dart';

class BadgeService {
  static const platform = MethodChannel('com.qoomy.qoomy/badge');
  static int _lastBadgeCount = -1;
  static Function()? _onRefreshRequested;
  static Function()? _onAppBackground;

  static void init() {
    // Listen for requests from native platform
    platform.setMethodCallHandler((call) async {
      if (call.method == 'refreshBadge') {
        print('🔔 Native platform requested badge refresh');
        _onRefreshRequested?.call();
      } else if (call.method == 'onAppBackground') {
        print('🔔 App went to background - triggering server notification');
        _onAppBackground?.call();
      }
    });
  }

  static void setOnAppBackgroundCallback(Function() callback) {
    _onAppBackground = callback;
  }

  static void setRefreshCallback(Function() callback) {
    _onRefreshRequested = callback;
  }

  static Future<void> setBadgeCount(int count, {bool forceUpdate = false}) async {
    // Only update if count actually changed (unless forceUpdate is true for debugging)
    if (!forceUpdate && count == _lastBadgeCount) return;
    _lastBadgeCount = count;

    try {
      await platform.invokeMethod('setBadgeCount', {'count': count});
    } catch (e) {
      print('Error setting badge count: $e');
    }
  }

  static Future<void> resetBadge() async {
    _lastBadgeCount = 0;
    try {
      await platform.invokeMethod('resetBadge');
    } catch (e) {
      print('Error resetting badge: $e');
    }
  }
}

/// Provider that watches total unread count and updates app badge with periodic refresh
final badgeSyncProvider = StreamProvider.family<int, String>((ref, userId) {
  final controller = StreamController<int>.broadcast();
  Timer? periodicTimer;
  final roomService = RoomService();
  final timeFormat = DateFormat('HH:mm:ss');

  // Initialize badge service to listen for native refresh requests
  BadgeService.init();

  // Direct Firestore query for periodic refresh (not cached)
  Future<void> refreshFromFirestore() async {
    final timestamp = timeFormat.format(DateTime.now());
    try {
      // Get user's team IDs
      final teamsAsync = ref.read(userTeamsProvider(userId));
      final teamIds = teamsAsync.valueOrNull?.map((t) => t.id).toList() ?? [];

      // Query Firestore directly for accurate count
      final count = await roomService.getTotalUnreadCountDirect(userId, teamIds);
      print('🔔 Checked at $timestamp. Total unread count: $count');
      BadgeService.setBadgeCount(count, forceUpdate: true);
      controller.add(count);
    } catch (e) {
      print('🔔 Checked at $timestamp. Error: $e');
    }
  }

  // Register callback for native platform refresh requests (iOS background fetch / app active)
  BadgeService.setRefreshCallback(() {
    refreshFromFirestore();
  });

  // Register callback for when app goes to background (Android)
  // This triggers the server to send a summary FCM notification
  BadgeService.setOnAppBackgroundCallback(() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('onAppBackground').call();
      print('🔔 Called onAppBackground Cloud Function');
    } catch (e) {
      print('🔔 Error calling onAppBackground: $e');
    }
  });

  // Listen to the totalUnreadCountProvider for real-time updates
  ref.listen<AsyncValue<int>>(totalUnreadCountProvider(userId), (previous, next) {
    next.whenData((count) {
      final timestamp = timeFormat.format(DateTime.now());
      print('🔔 Real-time update at $timestamp. Total unread count: $count');
      BadgeService.setBadgeCount(count);
      controller.add(count);
    });
  });

  // Also refresh every 5 seconds by directly querying Firestore
  periodicTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    refreshFromFirestore();
  });

  // Initial update from provider
  final totalUnreadAsync = ref.read(totalUnreadCountProvider(userId));
  totalUnreadAsync.whenData((count) {
    final timestamp = timeFormat.format(DateTime.now());
    print('🔔 Initial check at $timestamp. Total unread count: $count');
    BadgeService.setBadgeCount(count);
    controller.add(count);
  });

  ref.onDispose(() {
    periodicTimer?.cancel();
    BadgeService.setRefreshCallback(() {}); // Clear callback
    BadgeService.setOnAppBackgroundCallback(() {}); // Clear callback
    controller.close();
  });

  return controller.stream;
});
