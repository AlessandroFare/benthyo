# MobileCLIP embedding model (optional)

Place a 512-dimensional image embedding TFLite model here:

```
mobileclip_512.tflite
```

Recommended: [MobileCLIP-S0](https://github.com/apple/ml-mobileclip) exported to TFLite
with input shape `[1, 224, 224, 3]` (float32, RGB normalized) and output `[1, 512]`.

When the file is present, OceanLog uses on-device CLIP inference. Without it, a
deterministic visual fallback embedder is used (same 512-d API, lower accuracy).

After adding the model, declare it in `pubspec.yaml` under `flutter.assets`.
