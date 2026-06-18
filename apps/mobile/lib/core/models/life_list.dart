import '../utils/json_utils.dart';
import 'enums.dart';
import 'species.dart';

class UserLifeListEntry {
  const UserLifeListEntry({
    required this.userId,
    required this.speciesId,
    required this.firstSeenAt,
    required this.totalSightings,
    required this.siteIds,
    required this.createdAt,
    this.species,
  });

  final String userId;
  final String speciesId;
  final DateTime firstSeenAt;
  final int totalSightings;
  final List<String> siteIds;
  final DateTime createdAt;
  final Species? species;

  factory UserLifeListEntry.fromJson(Map<String, dynamic> json) {
    final speciesJson = json['species'] as Map<String, dynamic>?;
    return UserLifeListEntry(
      userId: json['user_id'] as String,
      speciesId: json['species_id'] as String,
      firstSeenAt: DateTime.parse(json['first_seen_at'] as String),
      totalSightings: parseInt(json['total_sightings']) ?? 1,
      siteIds: parseUuidList(json['site_ids']),
      createdAt: DateTime.parse(json['created_at'] as String),
      species: speciesJson != null ? Species.fromJson(speciesJson) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'species_id': speciesId,
        'first_seen_at': firstSeenAt.toIso8601String(),
        'total_sightings': totalSightings,
        'site_ids': siteIds,
        'created_at': createdAt.toIso8601String(),
      };
}

class Badge {
  const Badge({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    this.iconUrl,
    required this.criteriaType,
    required this.criteriaValue,
    required this.tier,
    required this.createdAt,
  });

  final String id;
  final String code;
  final String name;
  final String description;
  final String? iconUrl;
  final BadgeCriteriaType criteriaType;
  final Map<String, dynamic> criteriaValue;
  final int tier;
  final DateTime createdAt;

  factory Badge.fromJson(Map<String, dynamic> json) => Badge(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        iconUrl: json['icon_url'] as String?,
        criteriaType:
            BadgeCriteriaTypeX.fromDb(json['criteria_type'] as String),
        criteriaValue: parseMetadata(json['criteria_value']),
        tier: parseInt(json['tier']) ?? 1,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'description': description,
        'icon_url': iconUrl,
        'criteria_type': criteriaType.dbValue,
        'criteria_value': criteriaValue,
        'tier': tier,
        'created_at': createdAt.toIso8601String(),
      };
}

class UserBadge {
  const UserBadge({
    required this.userId,
    required this.badgeId,
    required this.earnedAt,
    required this.contextJson,
    this.badge,
  });

  final String userId;
  final String badgeId;
  final DateTime earnedAt;
  final Map<String, dynamic> contextJson;
  final Badge? badge;

  factory UserBadge.fromJson(Map<String, dynamic> json) {
    final badgeJson = json['badges'] as Map<String, dynamic>?;
    return UserBadge(
      userId: json['user_id'] as String,
      badgeId: json['badge_id'] as String,
      earnedAt: DateTime.parse(json['earned_at'] as String),
      contextJson: parseMetadata(json['context_json']),
      badge: badgeJson != null ? Badge.fromJson(badgeJson) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'badge_id': badgeId,
        'earned_at': earnedAt.toIso8601String(),
        'context_json': contextJson,
      };
}
