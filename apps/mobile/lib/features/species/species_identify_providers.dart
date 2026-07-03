import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../uploads/uploads_repository.dart';
import '../../core/ml/clip_providers.dart';
import 'species_api_repository.dart';
import 'species_providers.dart';
import '../../core/models/species.dart';

class SpeciesIdentifyResult {
  const SpeciesIdentifyResult({
    required this.matches,
    this.imageUrl,
    this.inatResults = const [],
  });

  final List<Species> matches;
  final String? imageUrl;
  final List<InatIdentification> inatResults;
}

final speciesPhotoIdentifyProvider =
    FutureProvider.family<SpeciesIdentifyResult, String>((ref, localPath) async {
  final uploads = ref.read(uploadsRepositoryProvider);
  final api = ref.read(speciesApiRepositoryProvider);
  final speciesRepo = ref.read(speciesRepositoryProvider);

  final bytes = await XFile(localPath).readAsBytes();
  final contentType = _guessContentType(localPath);
  final publicUrl = await uploads.uploadBytes(
    bytes: bytes,
    contentType: contentType,
  );

  // Pre-compute CLIP embedding for vector search (cached locally until sighting saved).
  unawaited(ref.read(clipEmbeddingServiceProvider).embedBytes(bytes));

  final inatResults = await api.identifyFromImageUrl(publicUrl);
  if (inatResults.isEmpty) {
    return SpeciesIdentifyResult(
      matches: const [],
      imageUrl: publicUrl,
      inatResults: inatResults,
    );
  }

  final allSpecies = await speciesRepo.fetchAll(limit: 500);
  final matches = <Species>[];
  for (final hit in inatResults) {
    final name = hit.scientificName.toLowerCase();
    final found = allSpecies.where(
      (s) =>
          s.scientificName.toLowerCase() == name ||
          s.scientificName.toLowerCase().startsWith(name.split(' ').first),
    );
    matches.addAll(found);
  }

  final unique = <String, Species>{};
  for (final s in matches) {
    unique[s.id] = s;
  }

  return SpeciesIdentifyResult(
    matches: unique.values.toList(),
    imageUrl: publicUrl,
    inatResults: inatResults,
  );
});

String _guessContentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
