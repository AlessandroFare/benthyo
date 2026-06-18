import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/enums.dart';
import '../../core/models/sighting.dart';
import '../../core/offline/sync_manager.dart';
import '../../core/supabase/supabase_client.dart';

class SightingsRepository {
  SightingsRepository(this._client, this._syncManager);

  final SupabaseClient _client;
  final SyncManager _syncManager;
  final _uuid = const Uuid();

  Future<List<SightingWithDetails>> fetchFeed({int limit = 50}) async {
    final data = await _client
        .from('sightings')
        .select(
          '*, dive_sites(name), species(scientific_name, common_name, image_url)',
        )
        .order('observed_at', ascending: false)
        .limit(limit);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(SightingWithDetails.fromJson).toList();
  }

  Future<List<SightingWithDetails>> fetchForUser(String userId) async {
    final data = await _client
        .from('sightings')
        .select(
          '*, dive_sites(name), species(scientific_name, common_name, image_url)',
        )
        .eq('user_id', userId)
        .order('observed_at', ascending: false);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(SightingWithDetails.fromJson).toList();
  }

  Future<Sighting> create({
    required String userId,
    required String diveSiteId,
    required String speciesId,
    required DateTime observedAt,
    required ConfidenceLevel confidence,
    int count = 1,
    double? depthM,
    String? notes,
    String? diveLogId,
    List<String> photoUrls = const [],
    required bool isOnline,
  }) async {
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'user_id': userId,
      'dive_site_id': diveSiteId,
      'species_id': speciesId,
      'dive_log_id': diveLogId,
      'observed_at': observedAt.toIso8601String(),
      'depth_m': depthM,
      'count': count,
      'confidence_level': confidence.dbValue,
      'notes': notes,
      'behavior_tags': <String>[],
      'photo_urls': photoUrls,
      'source': SightingSource.user.dbValue,
    };

    if (isOnline) {
      final data =
          await _client.from('sightings').insert(payload).select().single();
      return Sighting.fromJson(data);
    }

    await _syncManager.enqueue(
      SyncEntityType.sighting,
      payload,
      tableName: 'sightings',
      operation: SyncOperationType.insert,
    );

    return Sighting.fromJson({
      ...payload,
      'water_temp_c': null,
      'visibility_m': null,
      'verified_by': null,
      'verified_at': null,
      'location': null,
      'external_id': null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

final sightingsRepositoryProvider = Provider<SightingsRepository>((ref) {
  return SightingsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncManagerProvider),
  );
});

final sightingsFeedProvider = FutureProvider<List<SightingWithDetails>>((ref) {
  return ref.watch(sightingsRepositoryProvider).fetchFeed();
});

final userSightingsProvider =
    FutureProvider<List<SightingWithDetails>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(sightingsRepositoryProvider).fetchForUser(user.id);
});
