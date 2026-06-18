import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'clip_embedding_tflite_stub.dart'
    if (dart.library.ffi) 'clip_embedding_tflite_io.dart';

/// On-device 512-d image embeddings for pgvector similarity search.
///
/// Loads `assets/models/mobileclip_512.tflite` when present (MobileCLIP-S0
/// compatible). Falls back to a deterministic visual embedder otherwise.
class ClipEmbeddingService {
  ClipEmbeddingService._();
  static final ClipEmbeddingService instance = ClipEmbeddingService._();

  static const _modelAsset = 'assets/models/mobileclip_512.tflite';
  static const _embeddingDim = 512;
  static const _inputSize = 224;

  final ClipTfliteBackend _tflite = ClipTfliteBackend();

  Future<List<double>> embedBytes(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ArgumentError('Could not decode image');
    }
    return embedImage(decoded);
  }

  Future<List<double>> embedImage(img.Image source) async {
    if (await _tflite.ensureLoaded(_modelAsset)) {
      final vector = _tflite.run(source);
      if (vector != null) return vector;
    }

    final resized = img.copyResize(
      source,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );
    return _visualFallbackEmbedding(resized);
  }

  String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  List<double> _visualFallbackEmbedding(img.Image image) {
    const grid = 16;
    final blockW = max(1, image.width ~/ grid);
    final blockH = max(1, image.height ~/ grid);
    final features = <double>[];

    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        var sumR = 0.0, sumG = 0.0, sumB = 0.0;
        var sumSq = 0.0;
        var count = 0;

        for (var y = gy * blockH; y < (gy + 1) * blockH && y < image.height; y++) {
          for (var x = gx * blockW; x < (gx + 1) * blockW && x < image.width; x++) {
            final p = image.getPixel(x, y);
            final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
            sumR += p.r / 255.0;
            sumG += p.g / 255.0;
            sumB += p.b / 255.0;
            sumSq += lum * lum;
            count++;
          }
        }

        if (count == 0) {
          features.addAll([0, 0]);
          continue;
        }

        final mean = (sumR + sumG + sumB) / (3 * count);
        final variance = max(0.0, (sumSq / count) - (mean * mean));
        features.add(mean);
        features.add(variance.clamp(0, 1));
      }
    }

    return _l2Normalize(features.take(_embeddingDim).toList());
  }

  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm < 1e-12) return vector;
    return vector.map((v) => v / norm).toList();
  }

  void dispose() {
    _tflite.dispose();
  }
}
