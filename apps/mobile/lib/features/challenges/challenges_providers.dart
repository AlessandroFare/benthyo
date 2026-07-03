import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';

/// A single entry in the monthly species leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.speciesCount,
    required this.newToLifelist,
  });

  final int rank;
  final String userId;
  final String username;
  final String? avatarUrl;
  final int speciesCount;
  final int newToLifelist;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: (json['rank'] as num).toInt(),
        userId: json['user_id'] as String,
        username: json['username'] as String? ?? 'Unknown diver',
        avatarUrl: json['avatar_url'] as String?,
        speciesCount: (json['species_count'] as num).toInt(),
        newToLifelist: (json['new_to_lifelist'] as num).toInt(),
      );
}

class ChallengesRepository {
  ChallengesRepository(this._client);

  final SupabaseClient _client;

  Future<List<LeaderboardEntry>> fetchMonthlyLeaderboard({
    int limit = 50,
  }) async {
    final data = await _client.rpc(
      'monthly_species_leaderboard',
      params: {'p_limit': limit},
    );
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(LeaderboardEntry.fromJson).toList();
  }
}

final challengesRepositoryProvider = Provider<ChallengesRepository>((ref) {
  return ChallengesRepository(ref.watch(supabaseClientProvider));
});

/// Fetches the current month's species leaderboard.
/// Returns an empty list when the user is offline or the RPC fails.
final monthlyLeaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  try {
    return await ref
        .watch(challengesRepositoryProvider)
        .fetchMonthlyLeaderboard();
  } catch (_) {
    return [];
  }
});
