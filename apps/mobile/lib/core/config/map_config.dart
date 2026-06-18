/// Map tile configuration for dive-site exploration.
///
/// Supports a hosted PMTiles raster on R2, public ocean/bathymetry layers
/// (EMODnet isolines, Esri ocean base, OpenSeaMap seamarks), and OSM fallback.
library;

enum DiveMapBasemap {
  /// Custom PMTiles on R2 when configured, otherwise OpenStreetMap.
  standard,
  /// Esri World Ocean Base — tuned for marine context.
  ocean,
  /// EMODnet shaded bathymetry with depth context.
  bathymetry,
  /// Esri World Imagery — useful for reefs and shallow features.
  satellite,
}

class MapLayerPreset {
  const MapLayerPreset({
    required this.id,
    required this.label,
    required this.urlTemplate,
    required this.maxNativeZoom,
    this.subdomains = const [],
    this.attribution,
  });

  final String id;
  final String label;
  final String urlTemplate;
  final int maxNativeZoom;
  final List<String> subdomains;
  final String? attribution;
}

class MapConfig {
  MapConfig._();

  static const pmtilesTileUrl = String.fromEnvironment(
    'PMTILES_TILE_URL',
    defaultValue: '',
  );

  static const openStreetMapUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const esriOceanBaseUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Base/MapServer/tile/{z}/{y}/{x}';

  static const esriWorldImageryUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// EMODnet shaded relief — depth context for dive planning.
  static const emodnetBathymetryUrl =
      'https://tiles.emodnet-bathymetry.eu/2020/baselayer/web_mercator/{z}/{x}/{y}.png';

  /// EMODnet depth contour isolines (important for wall/drift planning).
  static const emodnetContoursUrl =
      'https://tiles.emodnet-bathymetry.eu/2020/contours/web_mercator/{z}/{x}/{y}.png';

  /// Nautical marks, moorings, and hazards from OpenSeaMap.
  static const openSeaMapSeamarksUrl =
      'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png';

  static String get tileUrlTemplate =>
      pmtilesTileUrl.isNotEmpty ? pmtilesTileUrl : openStreetMapUrl;

  static bool get usesPmtiles => pmtilesTileUrl.isNotEmpty;

  /// FMTC store name for offline basemap tiles.
  static const tileStoreName = 'oceanlog_dive_tiles';

  /// Approximate max cached tiles (~15 KB each ≈ 100 MB).
  static const int tileCacheMaxTiles = 6500;

  /// Legacy byte budget documented for operators.
  static const int tileCacheMaxBytes = 100 * 1024 * 1024;

  static MapLayerPreset basemap(DiveMapBasemap mode) {
    return switch (mode) {
      DiveMapBasemap.standard => MapLayerPreset(
          id: 'standard',
          label: 'Standard',
          urlTemplate: tileUrlTemplate,
          maxNativeZoom: usesPmtiles ? 14 : 19,
          attribution: usesPmtiles
              ? 'OceanLog'
              : '© OpenStreetMap contributors',
        ),
      DiveMapBasemap.ocean => MapLayerPreset(
          id: 'ocean',
          label: 'Ocean',
          urlTemplate: esriOceanBaseUrl,
          maxNativeZoom: 13,
          attribution: 'Esri, GEBCO, NOAA, National Geographic',
        ),
      DiveMapBasemap.bathymetry => MapLayerPreset(
          id: 'bathymetry',
          label: 'Bathymetry',
          urlTemplate: emodnetBathymetryUrl,
          maxNativeZoom: 11,
          attribution: 'EMODnet Bathymetry',
        ),
      DiveMapBasemap.satellite => MapLayerPreset(
          id: 'satellite',
          label: 'Satellite',
          urlTemplate: esriWorldImageryUrl,
          maxNativeZoom: 19,
          attribution: 'Esri, Maxar, Earthstar Geographics',
        ),
    };
  }

  static const contoursOverlay = MapLayerPreset(
    id: 'contours',
    label: 'Depth isolines',
    urlTemplate: emodnetContoursUrl,
    maxNativeZoom: 11,
    attribution: 'EMODnet Bathymetry',
  );

  static const seamarksOverlay = MapLayerPreset(
    id: 'seamarks',
    label: 'Nautical marks',
    urlTemplate: openSeaMapSeamarksUrl,
    maxNativeZoom: 18,
    attribution: 'OpenSeaMap',
  );
}
