import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/citizen_science_impact.dart';
import '../../core/models/enums.dart';
import '../../core/models/sighting.dart';
import '../../core/models/sighting_photo.dart';
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

  /// Calls the `citizen_science_impact` RPC and returns the parsed result.
  /// Returns a zeroed-out model if the user has no sightings or is offline.
  Future<CitizenScienceImpact> fetchImpact(String userId) async {
    try {
      final data = await _client.rpc(
        'citizen_science_impact',
        params: {'p_user_id': userId},
      );
      return CitizenScienceImpact.fromJson(
          Map<String, dynamic>.from(data as Map));
    } catch (_) {
      return const CitizenScienceImpact(
        totalSightings: 0,
        inatContributed: 0,
        gbifContributed: 0,
        databasesCount: 0,
      );
    }
  }

  // ─── Photo gallery methods ─────────────────────────────────────────────────

  /// Fetches all photos for [sightingId] ordered by [sort_order].
  Future<List<SightingPhoto>> fetchPhotosForSighting(
      String sightingId) async {
    final data = await _client
        .from('sighting_photos')
        .select()
        .eq('sighting_id', sightingId)
        .order('sort_order')
        .order('created_at');
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(SightingPhoto.fromJson).toList();
  }

  /// Inserts a photo row for [sightingId].
  ///
  /// [storagePathOrUrl] is the Supabase Storage path; [publicUrl] is the
  /// resolved CDN URL. If the caller only has a URL (legacy path), pass the
  /// same value for both parameters.
  Future<SightingPhoto> addPhoto({
    required String sightingId,
    required String userId,
    required String storagePath,
    required String publicUrl,
    String? caption,
    int sortOrder = 0,
  }) async {
    final data = await _client
        .from('sighting_photos')
        .insert({
          'sighting_id': sightingId,
          'user_id': userId,
          'storage_path': storagePath,
          'public_url': publicUrl,
          'caption': caption,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return SightingPhoto.fromJson(data);
  }

  /// Deletes [photoId] (caller must own the row — enforced by RLS).
  Future<void> deletePhoto(String photoId) async {
    await _client.from('sighting_photos').delete().eq('id', photoId);
  }

  // ─── Sighting fetch methods ────────────────────────────────────────────────

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

/// Fetches all [SightingPhoto] rows for a given sighting ID.
/// Automatically refreshed when [sightingsRepositoryProvider] is invalidated.
final sightingPhotosProvider =
    FutureProvider.family<List<SightingPhoto>, String>((ref, sightingId) {
  return ref.watch(sightingsRepositoryProvider).fetchPhotosForSighting(
        sightingId,
      );
});

/// Fetches the citizen-science contribution counts for the current user
/// by calling the `citizen_science_impact` Postgres RPC.
final citizenScienceImpactProvider =
    FutureProvider<CitizenScienceImpact?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(sightingsRepositoryProvider).fetchImpact(user.id);
});
