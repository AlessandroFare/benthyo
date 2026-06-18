import '../models/enums.dart';

class RecentDiver {
  const RecentDiver({
    required this.userId,
    required this.username,
    this.fullName,
    this.avatarUrl,
    required this.certLevel,
    required this.lastDiveDate,
    required this.diveCount,
  });

  final String userId;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final CertLevel certLevel;
  final DateTime lastDiveDate;
  final int diveCount;

  String displayName() => fullName?.isNotEmpty == true ? fullName! : username;

  factory RecentDiver.fromJson(Map<String, dynamic> json) {
    return RecentDiver(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      certLevel: CertLevelX.fromDb(json['cert_level'] as String? ?? 'OW'),
      lastDiveDate: DateTime.parse(json['last_dive_date'] as String),
      diveCount: (json['dive_count'] as num).toInt(),
    );
  }
}
