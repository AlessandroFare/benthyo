import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clip_embedding_service.dart';
import 'photo_embedding_repository.dart';

final clipEmbeddingServiceProvider = Provider<ClipEmbeddingService>(
  (_) => ClipEmbeddingService.instance,
);

final photoEmbeddingRepositoryProvider = Provider<PhotoEmbeddingRepository>(
  (ref) => PhotoEmbeddingRepository(ref.watch(clipEmbeddingServiceProvider)),
);
