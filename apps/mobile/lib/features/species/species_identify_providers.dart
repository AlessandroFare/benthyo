import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../uploads/uploads_repository.dart';
import '../../core/ml/clip_providers.dart';
import 'species_api_repository.dart';
import '../../core/models/species.dart';

class SpeciesIdentifyResult {
  const SpeciesIdentifyResult({
    required this.matches,
    this.imageUrl,
    this.inatResults = const [],
    this.ai,
    this.created = false,
  });

  final List<Species> matches;
  final String? imageUrl;
  final List<InatIdentification> inatResults;

  /// The AI vision proposal (Groq), when available.
  final AiVisionProposal? ai;

  /// True when the matched species was created on the fly from the AI result.
  final bool created;
}

final speciesPhotoIdentifyProvider =
    FutureProvider.family<SpeciesIdentifyResult, String>((ref, localPath) async {
  final uploads = ref.read(uploadsRepositoryProvider);
  final api = ref.read(speciesApiRepositoryProvider);

  final bytes = await XFile(localPath).readAsBytes();
  final contentType = _guessContentType(localPath);
  final publicUrl = await uploads.uploadBytes(
    bytes: bytes,
    contentType: contentType,
  );

  // Pre-compute CLIP embedding for vector search (cached locally until sighting saved).
  unawaited(ref.read(clipEmbeddingServiceProvider).embedBytes(bytes));

  // The server does the heavy lifting: Groq vision + iNaturalist, reconciled
  // against the catalog, creating the species on the fly when missing.
  final result = await api.identifyWithAi(publicUrl);

  return SpeciesIdentifyResult(
    matches: result.matches,
    imageUrl: publicUrl,
    inatResults: result.inatResults,
    ai: result.ai,
    created: result.created,
  );
});

String _guessContentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
