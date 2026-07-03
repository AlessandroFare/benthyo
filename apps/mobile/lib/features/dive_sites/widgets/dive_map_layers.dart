import 'package:flutter_map/flutter_map.dart';

import '../../../core/config/map_config.dart';

/// Builds [TileLayer] widgets for the dive exploration map.
class DiveMapLayers {
  DiveMapLayers._();

  static TileLayer basemap(
    DiveMapBasemap mode, {
    TileProvider? tileProvider,
  }) {
    final preset = MapConfig.basemap(mode);
    return TileLayer(
      urlTemplate: preset.urlTemplate,
      userAgentPackageName: 'com.benthyo.app',
      maxNativeZoom: preset.maxNativeZoom,
      subdomains: preset.subdomains,
      tileProvider: tileProvider,
    );
  }

  static TileLayer? contours({required bool enabled}) {
    if (!enabled) return null;
    const preset = MapConfig.contoursOverlay;
    return TileLayer(
      urlTemplate: preset.urlTemplate,
      userAgentPackageName: 'com.benthyo.app',
      maxNativeZoom: preset.maxNativeZoom,
    );
  }

  static TileLayer? seamarks({required bool enabled}) {
    if (!enabled) return null;
    const preset = MapConfig.seamarksOverlay;
    return TileLayer(
      urlTemplate: preset.urlTemplate,
      userAgentPackageName: 'com.benthyo.app',
      maxNativeZoom: preset.maxNativeZoom,
    );
  }
}
