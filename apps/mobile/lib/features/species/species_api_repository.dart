import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
