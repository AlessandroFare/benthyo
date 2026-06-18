import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/models/enums.dart';
import '../../core/supabase/supabase_client.dart';

class PublicDiveSummary {
  const PublicDiveSummary({
    required this.id,
    required this.diveDate,
    required this.maxDepthM,
    required this.durationMin,
  });

  final String id;
  final DateTime diveDate;
  final double maxDepthM;
  final int durationMin;

  factory PublicDiveSummary.fromJson(Map<String, dynamic> json) =>
      PublicDiveSummary(
        id: json['id'] as String,
        diveDate: DateTime.parse(json['dive_date'] as String),
        maxDepthM: (json['max_depth_m'] as num).toDouble(),
        durationMin: (json['duration_min'] as num).toInt(),
      );
}

class LifeListEntry {
  const LifeListEntry({
    required this.scientificName,
    this.commonName,
  });

  final String scientificName;
  final String? commonName;

  factory LifeListEntry.fromJson(Map<String, dynamic> json) {
    final species = json['species'] as Map<String, dynamic>?;
    return LifeListEntry(
      scientificName: species?['scientific_name'] as String? ?? 'Unknown',
      commonName: species?['common_name'] as String?,
    );
  }
}

class PublicLogbookData {
  const PublicLogbookData({
    required this.profile,
    required this.isPublic,
    required this.dives,
    required this.lifeList,
    this.verification,
  });

  final PublicProfile profile;
  final bool isPublic;
  final List<PublicDiveSummary> dives;
  final List<LifeListEntry> lifeList;
  final PublicVerification? verification;
}

class PublicProfile {
  const PublicProfile({
    required this.username,
    this.fullName,
    this.avatarUrl,
    required this.totalDives,
    required this.certificationLevel,
  });

  final String username;
  final String? fullName;
  final String? avatarUrl;
  final int totalDives;
  final CertLevel certificationLevel;

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
        username: json['username'] as String,
        fullName: json['full_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        totalDives: (json['total_dives'] as num?)?.toInt() ?? 0,
        certificationLevel:
            CertLevelX.fromDb(json['certification_level'] as String? ?? 'OW'),
      );
}

class PublicVerification {
  const PublicVerification({required this.level});

  final int level;

  factory PublicVerification.fromJson(Map<String, dynamic> json) =>
      PublicVerification(level: (json['level'] as num?)?.toInt() ?? 1);
}

final publicLogbookProvider =
    FutureProvider.family<PublicLogbookData?, String>((ref, username) async {
  final supabase = ref.watch(supabaseClientProvider);
  final token = supabase.auth.currentSession?.accessToken;
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/users/$username/logbook'),
    headers: headers,
  );
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) {
    throw Exception('Failed to load logbook (${res.statusCode})');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final data = body['data'] as Map<String, dynamic>? ?? body;
  return PublicLogbookData(
    profile: PublicProfile.fromJson(data['profile'] as Map<String, dynamic>),
    isPublic: data['public'] as bool? ?? true,
    dives: (data['dives'] as List<dynamic>? ?? [])
        .map((e) => PublicDiveSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    lifeList: (data['life_list'] as List<dynamic>? ?? [])
        .map((e) => LifeListEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    verification: data['verification'] != null
        ? PublicVerification.fromJson(
            data['verification'] as Map<String, dynamic>,
          )
        : null,
  );
});
