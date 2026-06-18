import '../utils/json_utils.dart';
import 'enums.dart';

class DiveLog {
  const DiveLog({
    required this.id,
    required this.userId,
    this.diveSiteId,
    this.operatorId,
    required this.diveDate,
    this.diveNumber,
    this.entryTime,
    this.exitTime,
    required this.maxDepthM,
    this.avgDepthM,
    required this.durationMin,
    this.waterTempSurfaceC,
    this.waterTempBottomC,
    this.visibilityM,
    this.currentStrength,
    this.tankStartBar,
    this.tankEndBar,
    this.tankSizeL,
    required this.gasMix,
    this.buddyName,
    this.notes,
    this.rating,
    this.syncedAt,
    this.profileSamples = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String? diveSiteId;
  final String? operatorId;
  final DateTime diveDate;
  final int? diveNumber;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final double maxDepthM;
  final double? avgDepthM;
  final int durationMin;
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
  final DateTime? syncedAt;
  final List<Map<String, dynamic>> profileSamples;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DiveLog.fromJson(Map<String, dynamic> json) => DiveLog(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        diveSiteId: json['dive_site_id'] as String?,
        operatorId: json['operator_id'] as String?,
        diveDate: DateTime.parse(json['dive_date'] as String),
        diveNumber: parseInt(json['dive_number']),
        entryTime: json['entry_time'] != null
            ? DateTime.parse(json['entry_time'] as String)
            : null,
        exitTime: json['exit_time'] != null
            ? DateTime.parse(json['exit_time'] as String)
            : null,
        maxDepthM: parseDouble(json['max_depth_m']) ?? 0,
        avgDepthM: parseDouble(json['avg_depth_m']),
        durationMin: parseInt(json['duration_min']) ?? 0,
        waterTempSurfaceC: parseDouble(json['water_temp_surface_c']),
        waterTempBottomC: parseDouble(json['water_temp_bottom_c']),
        visibilityM: parseDouble(json['visibility_m']),
        currentStrength:
            CurrentStrengthX.fromDb(json['current_strength'] as String?),
        tankStartBar: parseDouble(json['tank_start_bar']),
        tankEndBar: parseDouble(json['tank_end_bar']),
        tankSizeL: parseDouble(json['tank_size_l']),
        gasMix: GasMixX.fromDb(json['gas_mix'] as String),
        buddyName: json['buddy_name'] as String?,
        notes: json['notes'] as String?,
        rating: parseInt(json['rating']),
        syncedAt: json['synced_at'] != null
            ? DateTime.parse(json['synced_at'] as String)
            : null,
        profileSamples: (json['profile_samples'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'dive_site_id': diveSiteId,
        'operator_id': operatorId,
        'dive_date':
            '${diveDate.year.toString().padLeft(4, '0')}-${diveDate.month.toString().padLeft(2, '0')}-${diveDate.day.toString().padLeft(2, '0')}',
        'dive_number': diveNumber,
        'entry_time': entryTime?.toIso8601String(),
        'exit_time': exitTime?.toIso8601String(),
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
        'synced_at': syncedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
