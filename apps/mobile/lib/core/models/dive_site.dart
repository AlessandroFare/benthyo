import 'package:latlong2/latlong.dart';

import '../utils/geo_utils.dart';
import '../utils/json_utils.dart';
import 'enums.dart';

class DiveSite {
  const DiveSite({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.location,
    required this.countryCode,
    this.region,
    required this.depthMin,
    required this.depthMax,
    required this.difficulty,
    required this.siteType,
    required this.accessType,
    this.createdBy,
    required this.verified,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final LatLng location;
  final String countryCode;
  final String? region;
  final double depthMin;
  final double depthMax;
  final SiteDifficulty difficulty;
  final SiteType siteType;
  final AccessType accessType;
  final String? createdBy;
  final bool verified;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DiveSite.fromJson(Map<String, dynamic> json) {
    final coords = parseGeography(json['location']);
    if (coords == null) {
      throw FormatException('Invalid location for dive site ${json['id']}');
    }
    return DiveSite(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      location: coords,
      countryCode: json['country_code'] as String,
      region: json['region'] as String?,
      depthMin: parseDouble(json['depth_min']) ?? 0,
      depthMax: parseDouble(json['depth_max']) ?? 0,
      difficulty: SiteDifficultyX.fromDb(json['difficulty'] as String),
      siteType: SiteTypeX.fromDb(json['site_type'] as String),
      accessType: AccessTypeX.fromDb(json['access_type'] as String),
      createdBy: json['created_by'] as String?,
      verified: json['verified'] as bool? ?? false,
      metadata: parseMetadata(json['metadata']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'location': geographyToWkt(location),
        'country_code': countryCode,
        'region': region,
        'depth_min': depthMin,
        'depth_max': depthMax,
        'difficulty': difficulty.dbValue,
        'site_type': siteType.dbValue,
        'access_type': accessType.dbValue,
        'created_by': createdBy,
        'verified': verified,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
