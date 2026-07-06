import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/species.dart';
import '../../core/supabase/supabase_client.dart';

class InatIdentification {
  const InatIdentification({
    required this.taxonId,
    required this.scientificName,
    this.commonName,
    required this.confidence,
    this.imageUrl,
  });

  final int taxonId;
  final String scientificName;
  final String? commonName;
  final double confidence;
  final String? imageUrl;

  factory InatIdentification.fromJson(Map<String, dynamic> json) {
    return InatIdentification(
      taxonId: (json['taxon_id'] as num).toInt(),
      scientificName: json['scientific_name'] as String,
      commonName: json['common_name'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      imageUrl: json['image_url'] as String?,
    );
  }
}

/// The AI vision proposal returned by `POST species/identify/ai`.
class AiVisionProposal {
  const AiVisionProposal({
    required this.scientificName,
    this.commonName,
    this.commonNameIt,
    this.commonNameEs,
    this.family,
    this.genus,
    required this.confidence,
    this.rationale,
    required this.isMarine,
    required this.source,
  });

  final String? scientificName;
  final String? commonName;
  final String? commonNameIt;
  final String? commonNameEs;
  final String? family;
  final String? genus;
  final double confidence;
  final String? rationale;
  final bool isMarine;
  final String source;

  String displayName({String locale = 'en'}) {
    if (locale.startsWith('it') && commonNameIt != null) return commonNameIt!;
    if (locale.startsWith('es') && commonNameEs != null) return commonNameEs!;
    return commonName ?? scientificName ?? 'Unknown';
  }

  factory AiVisionProposal.fromJson(Map<String, dynamic> json) {
    return AiVisionProposal(
      scientificName: json['scientific_name'] as String?,
      commonName: json['common_name'] as String?,
      commonNameIt: json['common_name_it'] as String?,
      commonNameEs: json['common_name_es'] as String?,
      family: json['family'] as String?,
      genus: json['genus'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      rationale: json['rationale'] as String?,
      isMarine: json['is_marine'] as bool? ?? true,
      source: json['source'] as String? ?? 'ai',
    );
  }
}

/// Full response of the AI-assisted identification endpoint.
class AiIdentifyResponse {
  const AiIdentifyResponse({
    this.ai,
    this.matches = const [],
    this.inatResults = const [],
    this.created = false,
  });

  final AiVisionProposal? ai;
  final List<Species> matches;
  final List<InatIdentification> inatResults;
  final bool created;

  factory AiIdentifyResponse.fromJson(Map<String, dynamic> json) {
    final aiJson = json['ai'];
    final matchesJson = (json['matches'] as List?) ?? const [];
    final inatJson = (json['inat'] as List?) ?? const [];
    return AiIdentifyResponse(
      ai: aiJson is Map<String, dynamic>
          ? AiVisionProposal.fromJson(aiJson)
          : null,
      matches: matchesJson
          .cast<Map<String, dynamic>>()
          .map(Species.fromJson)
          .toList(),
      inatResults: inatJson
          .cast<Map<String, dynamic>>()
          .map(InatIdentification.fromJson)
          .toList(),
      created: json['created'] as bool? ?? false,
    );
  }
}

class SpeciesApiRepository {
  SpeciesApiRepository({
    required SupabaseClient supabase,
    http.Client? httpClient,
    Uri? apiBase,
  })  : _supabase = supabase,
        _http = httpClient ?? http.Client(),
        _apiBase = apiBase ??
            Uri.parse(
              const String.fromEnvironment(
                'API_URL',
                defaultValue: 'http://localhost:3000/api/v1',
              ),
            );

  final SupabaseClient _supabase;
  final http.Client _http;
  final Uri _apiBase;

  Future<List<InatIdentification>> identifyFromImageUrl(String imageUrl) async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) {
      throw StateError('Sign in to identify species from photos.');
    }

    final uri = _apiBase.resolve('species/identify');
    final res = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'image_url': imageUrl}),
    );

    if (res.statusCode >= 400) {
      throw Exception(
        'Identify failed (${res.statusCode}): ${res.body}',
      );
    }

    final json = jsonDecode(res.body);
    if (json is List) {
      return json
          .cast<Map<String, dynamic>>()
          .map(InatIdentification.fromJson)
          .toList();
    }
    if (json is Map<String, dynamic>) {
      final data = json['data'];
      if (data is List) {
        return data
            .cast<Map<String, dynamic>>()
            .map(InatIdentification.fromJson)
            .toList();
      }
    }
    return const [];
  }

  /// AI-assisted identification. The server runs Groq vision + iNaturalist,
  /// reconciles them against the catalog, and creates the species on the fly
  /// when it is missing — so the client just renders the result.
  Future<AiIdentifyResponse> identifyWithAi(String imageUrl) async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) {
      throw StateError('Sign in to identify species from photos.');
    }

    final uri = _apiBase.resolve('species/identify/ai');
    final res = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'image_url': imageUrl}),
    );

    if (res.statusCode >= 400) {
      throw Exception('AI identify failed (${res.statusCode}): ${res.body}');
    }

    final json = jsonDecode(res.body);
    final map = json is Map<String, dynamic>
        ? (json['data'] is Map<String, dynamic>
            ? json['data'] as Map<String, dynamic>
            : json)
        : <String, dynamic>{};
    return AiIdentifyResponse.fromJson(map);
  }

  void dispose() => _http.close();
}

final speciesApiRepositoryProvider = Provider<SpeciesApiRepository>((ref) {
  final repo = SpeciesApiRepository(
    supabase: ref.watch(supabaseClientProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final speciesIdentifyFromUrlProvider = FutureProvider.family<
    List<InatIdentification>, String>((ref, imageUrl) {
  return ref.watch(speciesApiRepositoryProvider).identifyFromImageUrl(imageUrl);
});
