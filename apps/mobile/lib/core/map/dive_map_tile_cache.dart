import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import '../config/map_config.dart';

/// Offline tile cache for dive map basemaps (mobile/desktop only).
class DiveMapTileCache {
  DiveMapTileCache._();

  static const storeName = MapConfig.tileStoreName;
  static bool _ready = false;

  static Future<void> initialize() async {
    if (kIsWeb || _ready) return;
    await FMTCObjectBoxBackend().initialise();
    await const FMTCStore(storeName).manage.create();
    _ready = true;
  }

  static TileProvider? cachedProvider({required bool enabled}) {
    if (kIsWeb || !enabled || !_ready) return null;
    return const FMTCStore(storeName).getTileProvider(
      settings: FMTCTileProviderSettings(
        behavior: CacheBehavior.cacheFirst,
        maxStoreLength: MapConfig.tileCacheMaxTiles,
        setInstance: false,
      ),
    );
  }

  static Future<String> cacheStats() async {
    if (kIsWeb || !_ready) return 'Offline cache unavailable on web';
    final stats = await const FMTCStore(storeName).stats.all;
    final sizeMb = stats.size / (1024 * 1024);
    return '${stats.length} tiles · ${sizeMb.toStringAsFixed(1)} MB';
  }
}
