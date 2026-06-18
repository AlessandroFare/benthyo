import 'dart:math';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Native TFLite backend for on-device CLIP inference.
class ClipTfliteBackend {
  static const _embeddingDim = 512;
  static const _inputSize = 224;

  Interpreter? _interpreter;
  bool _loadAttempted = false;

  Future<bool> ensureLoaded(String asset) async {
    if (_interpreter != null) return true;
    if (_loadAttempted) return false;
    _loadAttempted = true;
    try {
      _interpreter = await Interpreter.fromAsset(asset);
      return true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  List<double>? run(img.Image image) {
    final interpreter = _interpreter;
    if (interpreter == null) return null;

    try {
      final resized = img.copyResize(
        image,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      final input = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(
            _inputSize,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            },
          ),
        ),
      );

      final output = List.generate(1, (_) => List.filled(_embeddingDim, 0.0));
      interpreter.run(input, output);
      return _l2Normalize(output[0].cast<double>());
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
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
}
