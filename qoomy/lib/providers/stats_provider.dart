import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qoomy/services/stats_service.dart';
import 'package:qoomy/models/player_stats_model.dart';

final statsServiceProvider = Provider<StatsService>((ref) => StatsService());

final playerStatsProvider = FutureProvider.family<PlayerStats, String>((ref, userId) async {
  return ref.watch(statsServiceProvider).getPlayerStats(userId);
});
