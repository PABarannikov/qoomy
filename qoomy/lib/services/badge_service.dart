import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qoomy/providers/room_provider.dart';

class BadgeService {
  static const platform = MethodChannel('com.qoomy.qoomy/badge');

  static Future<void> setBadgeCount(int count) async {
    try {
      await platform.invokeMethod('setBadgeCount', {'count': count});
    } catch (e) {
      print('Error setting badge count: $e');
    }
  }

  static Future<void> resetBadge() async {
    try {
      await platform.invokeMethod('resetBadge');
    } catch (e) {
      print('Error resetting badge: $e');
    }
  }
}

/// Provider that watches total unread count and updates app badge
final badgeSyncProvider = Provider.family<void, String>((ref, userId) {
  // Watch totalUnreadCountProvider which includes hosted, joined, AND team rooms
  final totalUnreadAsync = ref.watch(totalUnreadCountProvider(userId));

  totalUnreadAsync.whenData((count) {
    BadgeService.setBadgeCount(count);
  });
});
