/// Photo uploads to Cloudflare R2 via the NestJS presign endpoint.
///
/// Spec: `docs/api.md` — `POST /v1/uploads/presign` returns
/// `{ "data": { "upload_url": "…", "public_url": "…" } }`. The mobile app
/// then PUTs the image bytes directly to the signed URL and appends the
/// resulting `public_url` to the sighting's `photo_urls` list.
///
/// We deliberately do *not* stream the file through the NestJS API
/// (matches the architecture doc: "NestJS never streams file bytes").
///
/// On a 401 from the API we force-refresh the Supabase session and retry
/// once. Supabase access tokens default to a 1-hour lifetime; without
/// this the user would see stale-token errors on long-running
/// background sync jobs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';

class UploadsRepository {
  UploadsRepository({
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

  /// Ask the API to mint a presigned R2 PUT URL for [contentType]. The
  /// returned `public_url` is what the sighting record will store; the
  /// `upload_url` is the one-shot signed PUT the client uses to upload the
  /// bytes.
  Future<PresignedUpload> requestPresign({
    required String contentType,
    String? sightingId,
  }) async {
    final token = _currentToken();
    if (token == null) {
      throw StateError('Not authenticated — sign in before uploading.');
    }
    final res = await _postWithRefresh(
      '/uploads/presign',
      {
        'content_type': contentType,
        if (sightingId != null) 'sighting_id': sightingId,
      },
      token,
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    return PresignedUpload(
      uploadUrl: Uri.parse(data['upload_url'] as String),
      publicUrl: data['public_url'] as String,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  /// Upload raw bytes (works on mobile and web).
  Future<String> uploadBytes({
    required List<int> bytes,
    required String contentType,
  }) async {
    final presigned = await requestPresign(contentType: contentType);
    final res = await _http.put(
      presigned.uploadUrl,
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode >= 400) {
      throw HttpException(
        'Upload failed (${res.statusCode})',
        uri: presigned.uploadUrl,
      );
    }
    return presigned.publicUrl;
  }

  /// Upload [file] to [url] with [contentType] using a single-shot PUT.
  /// The signed URL is one-shot, so we never retry on failure.
  Future<void> uploadFile({
    required File file,
    required Uri url,
    required String contentType,
  }) async {
    final bytes = await file.readAsBytes();
    final res = await _http.put(
      url,
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode >= 400) {
      throw HttpException(
        'Upload failed (${res.statusCode})',
        uri: url,
      );
    }
  }

  /// POST with a one-shot silent retry on 401. If the first attempt
  /// returns 401, we ask Supabase to refresh the session, then re-send
  /// the request with the fresh token. If the retry also fails we throw.
  Future<http.Response> _postWithRefresh(
    String path,
    Map<String, dynamic> body,
    String initialToken,
  ) async {
    final uri = _apiBase.resolve(path);
    var attempt = 0;
    var token = initialToken;
    while (true) {
      final res = await _http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode != 401 || attempt == 1) {
        if (res.statusCode >= 400) {
          throw HttpException(
            '$path failed (${res.statusCode}): ${res.body}',
            uri: uri,
          );
        }
        return res;
      }
      // First attempt was 401 — try to refresh and retry once.
      attempt++;
      final refreshed = await _refreshToken();
      if (refreshed == null) {
        throw HttpException(
          '$path failed (401) and session refresh failed',
          uri: uri,
        );
      }
      token = refreshed;
    }
  }

  String? _currentToken() => _supabase.auth.currentSession?.accessToken;

  Future<String?> _refreshToken() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return null;
    try {
      // `refreshSession` accepts the refresh token string (or null to
      // use the one currently held by the SDK).
      final response = await _supabase.auth.refreshSession(
        session.refreshToken,
      );
      return response.session?.accessToken;
    } on AuthException {
      return null;
    }
  }

  void dispose() => _http.close();
}

class PresignedUpload {
  const PresignedUpload({
    required this.uploadUrl,
    required this.publicUrl,
    required this.expiresAt,
  });

  final Uri uploadUrl;
  final String publicUrl;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

final uploadsRepositoryProvider = Provider<UploadsRepository>((ref) {
  final repo = UploadsRepository(
    supabase: ref.watch(supabaseClientProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// One-shot async task: upload [file], return its public R2 URL.
///
/// The caller is expected to add the returned URL to a sighting's
/// `photo_urls` list (and persist via the existing sightings flow, which
/// also handles offline queueing).
final uploadSightingPhotoProvider =
    FutureProvider.family<String, File>((ref, file) async {
  final repo = ref.read(uploadsRepositoryProvider);
  final contentType = _guessContentType(file.path);
  final presigned = await repo.requestPresign(contentType: contentType);
  await repo.uploadFile(
    file: file,
    url: presigned.uploadUrl,
    contentType: contentType,
  );
  return presigned.publicUrl;
});

String _guessContentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    return 'image/heic';
  }
  return 'image/jpeg';
}
