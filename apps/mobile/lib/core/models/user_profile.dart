import '../utils/json_utils.dart';
import 'enums.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.bio,
    required this.certificationLevel,
    required this.certificationAgency,
    required this.totalDives,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String? bio;
  final CertLevel certificationLevel;
  final CertAgency certificationAgency;
  final int totalDives;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isProfileComplete =>
      username.isNotEmpty && !username.startsWith('user_');

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        fullName: json['full_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        certificationLevel:
            CertLevelX.fromDb(json['certification_level'] as String),
        certificationAgency:
            CertAgencyX.fromDb(json['certification_agency'] as String),
        totalDives: parseInt(json['total_dives']) ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'bio': bio,
        'certification_level': certificationLevel.dbValue,
        'certification_agency': certificationAgency.dbValue,
        'total_dives': totalDives,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  UserProfile copyWith({
    String? username,
    String? fullName,
    String? avatarUrl,
    String? bio,
    CertLevel? certificationLevel,
    CertAgency? certificationAgency,
  }) =>
      UserProfile(
        id: id,
        username: username ?? this.username,
        fullName: fullName ?? this.fullName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        certificationLevel: certificationLevel ?? this.certificationLevel,
        certificationAgency: certificationAgency ?? this.certificationAgency,
        totalDives: totalDives,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
