import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/operator.dart';
import '../../core/supabase/supabase_client.dart';

class OperatorsRepository {
  OperatorsRepository(this._client);

  final SupabaseClient _client;

  Future<List<Operator>> fetchAll({int limit = 100}) async {
    final data =
        await _client.from('operators').select().order('name').limit(limit);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(Operator.fromJson).toList();
  }

  Future<Operator?> fetchById(String id) async {
    final data =
        await _client.from('operators').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return Operator.fromJson(data);
  }
}

final operatorsRepositoryProvider = Provider<OperatorsRepository>((ref) {
  return OperatorsRepository(ref.watch(supabaseClientProvider));
});

final operatorsProvider = FutureProvider<List<Operator>>((ref) {
  return ref.watch(operatorsRepositoryProvider).fetchAll();
});

final operatorProvider = FutureProvider.family<Operator?, String>((ref, id) {
  return ref.watch(operatorsRepositoryProvider).fetchById(id);
});
