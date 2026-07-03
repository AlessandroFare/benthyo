import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../ml/clip_embedding_service.dart';

/// Uploads CLIP embeddings + SHA256 fingerprints to the API after photo capture.
class PhotoEmbeddingRepository {
  PhotoEmbeddingRepository(this._clip);

  final ClipEmbeddingService _clip;

  Future<void> registerPhoto({
    required Uint8List bytes,
    required String accessToken,
    required String sightingId,
    required String photoUrl,
    String? speciesId,
  }) async {
    final embedding = await _clip.embedBytes(bytes);
    final hash = _clip.sha256Hex(bytes);

    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/sightings/photo-fingerprint'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sighting_id': sightingId,
        'photo_url': photoUrl,
        'sha256': hash,
        if (speciesId != null) 'species_id': speciesId,
      }),
    );

    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/sightings/photo-embedding'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sighting_id': sightingId,
        'photo_url': photoUrl,
        'sha256': hash,
        if (speciesId != null) 'species_id': speciesId,
        'embedding': embedding,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> findSimilar({
    required Uint8List bytes,
    int limit = 10,
  }) async {
    final embedding = await _clip.embedBytes(bytes);
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/sightings/vector-search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'embedding': embedding, 'limit': limit}),
    );
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    return body is List
        ? body.cast<Map<String, dynamic>>()
        : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
  }
}
