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
final badgeSyncProvider = StreamProvider.family<void, String>((ref, userId) async* {
  final roomService = ref.watch(roomServiceProvider);

  await for (final count in roomService.totalUnreadCountStream(userId)) {
    await BadgeService.setBadgeCount(count);
    yield null;
  }
});
