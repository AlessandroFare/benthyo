import '../utils/geo_utils.dart';
import '../utils/json_utils.dart';
import 'enums.dart';

class Sighting {
  const Sighting({
    required this.id,
    required this.userId,
    required this.diveSiteId,
    required this.speciesId,
    this.diveLogId,
    required this.observedAt,
    this.depthM,
    this.waterTempC,
    this.visibilityM,
    required this.count,
    required this.behaviorTags,
    required this.photoUrls,
    required this.confidenceLevel,
    this.verifiedBy,
    this.verifiedAt,
    this.notes,
    this.location,
    required this.source,
    this.externalId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String diveSiteId;
  final String speciesId;
  final String? diveLogId;
  final DateTime observedAt;
  final double? depthM;
  final double? waterTempC;
  final double? visibilityM;
  final int count;
  final List<String> behaviorTags;
  final List<String> photoUrls;
  final ConfidenceLevel confidenceLevel;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? notes;
  final dynamic location;
  final SightingSource source;
  final String? externalId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Sighting.fromJson(Map<String, dynamic> json) => Sighting(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        diveSiteId: json['dive_site_id'] as String,
        speciesId: json['species_id'] as String,
        diveLogId: json['dive_log_id'] as String?,
        observedAt: DateTime.parse(json['observed_at'] as String),
        depthM: parseDouble(json['depth_m']),
        waterTempC: parseDouble(json['water_temp_c']),
        visibilityM: parseDouble(json['visibility_m']),
        count: parseInt(json['count']) ?? 1,
        behaviorTags: parseStringList(json['behavior_tags']),
        photoUrls: parseStringList(json['photo_urls']),
        confidenceLevel:
            ConfidenceLevelX.fromDb(json['confidence_level'] as String),
        verifiedBy: json['verified_by'] as String?,
        verifiedAt: json['verified_at'] != null
            ? DateTime.parse(json['verified_at'] as String)
            : null,
        notes: json['notes'] as String?,
        location: json['location'],
        source: SightingSourceX.fromDb(json['source'] as String),
        externalId: json['external_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'dive_site_id': diveSiteId,
        'species_id': speciesId,
        'dive_log_id': diveLogId,
        'observed_at': observedAt.toIso8601String(),
        'depth_m': depthM,
        'water_temp_c': waterTempC,
        'visibility_m': visibilityM,
        'count': count,
        'behavior_tags': behaviorTags,
        'photo_urls': photoUrls,
        'confidence_level': confidenceLevel.dbValue,
        'verified_by': verifiedBy,
        'verified_at': verifiedAt?.toIso8601String(),
        'notes': notes,
        'location': location != null && parseGeography(location) != null
            ? geographyToWkt(parseGeography(location)!)
            : null,
        'source': source.dbValue,
        'external_id': externalId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class SightingWithDetails extends Sighting {
  const SightingWithDetails({
    required super.id,
    required super.userId,
    required super.diveSiteId,
    required super.speciesId,
    super.diveLogId,
    required super.observedAt,
    super.depthM,
    super.waterTempC,
    super.visibilityM,
    required super.count,
    required super.behaviorTags,
    required super.photoUrls,
    required super.confidenceLevel,
    super.verifiedBy,
    super.verifiedAt,
    super.notes,
    super.location,
    required super.source,
    super.externalId,
    required super.createdAt,
    required super.updatedAt,
    this.siteName,
    this.speciesName,
    this.speciesScientificName,
    this.speciesImageUrl,
    this.isRemoved = false,
  });

  final String? siteName;
  final String? speciesName;
  final String? speciesScientificName;
  final String? speciesImageUrl;
  /// True when the underlying row was soft-deleted but the caller
  /// still has a cached copy (e.g. from the offline queue). The feed
  /// should render a "Removed" placeholder instead of crashing on
  /// null dive-site / species data.
  final bool isRemoved;

  factory SightingWithDetails.fromJson(Map<String, dynamic> json) {
    final site = json['dive_sites'] as Map<String, dynamic>?;
    final species = json['species'] as Map<String, dynamic>?;
    return SightingWithDetails(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      diveSiteId: json['dive_site_id'] as String,
      speciesId: json['species_id'] as String,
      diveLogId: json['dive_log_id'] as String?,
      observedAt: DateTime.parse(json['observed_at'] as String),
      depthM: parseDouble(json['depth_m']),
      waterTempC: parseDouble(json['water_temp_c']),
      visibilityM: parseDouble(json['visibility_m']),
      count: parseInt(json['count']) ?? 1,
      behaviorTags: parseStringList(json['behavior_tags']),
      photoUrls: parseStringList(json['photo_urls']),
      confidenceLevel:
          ConfidenceLevelX.fromDb(json['confidence_level'] as String),
      verifiedBy: json['verified_by'] as String?,
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      notes: json['notes'] as String?,
      location: json['location'],
      source: SightingSourceX.fromDb(json['source'] as String),
      externalId: json['external_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      siteName: site?['name'] as String?,
      speciesName: species?['common_name'] as String?,
      speciesScientificName: species?['scientific_name'] as String?,
      speciesImageUrl: species?['image_url'] as String?,
      isRemoved: json['deleted_at'] != null,
    );
  }
}
