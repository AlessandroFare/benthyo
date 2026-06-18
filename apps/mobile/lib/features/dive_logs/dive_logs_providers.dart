import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/dive_log.dart';
import '../../core/models/enums.dart';
import '../../core/offline/sync_manager.dart';
import '../../core/supabase/supabase_client.dart';

class DiveLogValidationResult {
  const DiveLogValidationResult({
    required this.isValid,
    this.errors = const {},
  });

  final bool isValid;
  final Map<String, String> errors;
}

DiveLogValidationResult validateDiveLogInput({
  required DateTime diveDate,
  required double maxDepthM,
  required int durationMin,
  double? avgDepthM,
  int? rating,
  double? tankStartBar,
  double? tankEndBar,
}) {
  final errors = <String, String>{};
  final today = DateTime.now();
  final diveDay = DateTime(diveDate.year, diveDate.month, diveDate.day);
  final todayDate = DateTime(today.year, today.month, today.day);

  if (diveDay.isAfter(todayDate)) {
    errors['dive_date'] = 'Dive date cannot be in the future';
  }
  if (maxDepthM <= 0) {
    errors['max_depth_m'] = 'Max depth must be greater than 0';
  }
  if (durationMin <= 0) {
    errors['duration_min'] = 'Duration must be greater than 0';
  }
  if (avgDepthM != null && avgDepthM > maxDepthM) {
    errors['avg_depth_m'] = 'Average depth cannot exceed max depth';
  }
  if (rating != null && (rating < 1 || rating > 5)) {
    errors['rating'] = 'Rating must be between 1 and 5';
  }
  if (tankStartBar != null && tankEndBar != null && tankEndBar > tankStartBar) {
    errors['tank_end_bar'] = 'End pressure cannot exceed start pressure';
  }

  return DiveLogValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
  );
}

/// Strips time component so "today" comparisons work for quick-log flows.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class DiveLogCreateInput {
  const DiveLogCreateInput({
    required this.diveDate,
    required this.maxDepthM,
    required this.durationMin,
    this.diveSiteId,
    this.operatorId,
    this.diveNumber,
    this.avgDepthM,
    this.waterTempSurfaceC,
    this.waterTempBottomC,
    this.visibilityM,
    this.currentStrength,
    this.tankStartBar,
    this.tankEndBar,
    this.tankSizeL,
    this.gasMix = GasMix.air,
    this.buddyName,
    this.notes,
    this.rating,
  });

  final DateTime diveDate;
  final double maxDepthM;
  final int durationMin;
  final String? diveSiteId;
  final String? operatorId;
  final int? diveNumber;
  final double? avgDepthM;
  final double? waterTempSurfaceC;
  final double? waterTempBottomC;
  final double? visibilityM;
  final CurrentStrength? currentStrength;
  final double? tankStartBar;
  final double? tankEndBar;
  final double? tankSizeL;
  final GasMix gasMix;
  final String? buddyName;
  final String? notes;
  final int? rating;

  Map<String, dynamic> toPayload(String userId, String id) => {
        'id': id,
        'user_id': userId,
        'dive_site_id': diveSiteId,
        'operator_id': operatorId,
        'dive_date':
            '${diveDate.year.toString().padLeft(4, '0')}-${diveDate.month.toString().padLeft(2, '0')}-${diveDate.day.toString().padLeft(2, '0')}',
        'dive_number': diveNumber,
        'max_depth_m': maxDepthM,
        'avg_depth_m': avgDepthM,
        'duration_min': durationMin,
        'water_temp_surface_c': waterTempSurfaceC,
        'water_temp_bottom_c': waterTempBottomC,
        'visibility_m': visibilityM,
        'current_strength': currentStrength?.dbValue,
        'tank_start_bar': tankStartBar,
        'tank_end_bar': tankEndBar,
        'tank_size_l': tankSizeL,
        'gas_mix': gasMix.dbValue,
        'buddy_name': buddyName,
        'notes': notes,
        'rating': rating,
        'synced_at': DateTime.now().toIso8601String(),
      };
}

class DiveLogsRepository {
  DiveLogsRepository(this._client, this._syncManager);

  final SupabaseClient _client;
  final SyncManager _syncManager;
  final _uuid = const Uuid();

  Future<List<DiveLog>> fetchForUser(String userId) async {
    final data = await _client
        .from('dive_logs')
        .select()
        .eq('user_id', userId)
        .order('dive_date', ascending: false);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(DiveLog.fromJson).toList();
  }

  Future<DiveLog?> fetchById(String id) async {
    final data =
        await _client.from('dive_logs').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return DiveLog.fromJson(data);
  }

  Future<DiveLog> create({
    required String userId,
    required DiveLogCreateInput input,
    required bool isOnline,
  }) async {
    final validation = validateDiveLogInput(
      diveDate: input.diveDate,
      maxDepthM: input.maxDepthM,
      durationMin: input.durationMin,
      avgDepthM: input.avgDepthM,
      rating: input.rating,
      tankStartBar: input.tankStartBar,
      tankEndBar: input.tankEndBar,
    );
    if (!validation.isValid) {
      throw ArgumentError(validation.errors.values.join(', '));
    }

    final id = _uuid.v4();
    final payload = input.toPayload(userId, id);

    if (isOnline) {
      final data =
          await _client.from('dive_logs').insert(payload).select().single();
      return DiveLog.fromJson(data);
    }

    await _syncManager.enqueue(
      SyncEntityType.diveLog,
      payload,
      tableName: 'dive_logs',
      operation: SyncOperationType.insert,
    );

    return DiveLog.fromJson({
      ...payload,
      'entry_time': null,
      'exit_time': null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

final diveLogsRepositoryProvider = Provider<DiveLogsRepository>((ref) {
  return DiveLogsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncManagerProvider),
  );
});

final diveLogsProvider = FutureProvider<List<DiveLog>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(diveLogsRepositoryProvider).fetchForUser(user.id);
});

final diveLogProvider = FutureProvider.family<DiveLog?, String>((ref, id) {
  return ref.watch(diveLogsRepositoryProvider).fetchById(id);
});
