/// Web / non-FFI stub — TFLite is unavailable; fallback embedder only.
class ClipTfliteBackend {
  Future<bool> ensureLoaded(String asset) async => false;

  List<double>? run(dynamic image) => null;

  void dispose() {}
}
