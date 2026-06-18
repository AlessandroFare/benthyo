import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/life_list.dart';
import '../../core/supabase/supabase_client.dart';

class LifeListRepository {
  LifeListRepository(this._client);

  final SupabaseClient _client;

  Future<List<UserLifeListEntry>> fetchForUser(String userId) async {
    final data = await _client
        .from('user_life_list')
        .select('*, species(*)')
        .eq('user_id', userId)
        .order('first_seen_at', ascending: false);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(UserLifeListEntry.fromJson).toList();
  }
}

final lifeListRepositoryProvider = Provider<LifeListRepository>((ref) {
  return LifeListRepository(ref.watch(supabaseClientProvider));
});

final lifeListProvider = FutureProvider<List<UserLifeListEntry>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(lifeListRepositoryProvider).fetchForUser(user.id);
});
