import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/map_config.dart';
import '../../core/map/dive_map_tile_cache.dart';
import '../../core/models/dive_site.dart';
import '../../core/models/dive_site_filters.dart';
import '../../core/models/enums.dart';
import '../../core/models/species.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/main_navigation.dart';
import 'dive_sites_providers.dart';
import 'map_explore_providers.dart';
import '../species/species_providers.dart';
import 'services/marine_currents_service.dart';
import 'widgets/dive_map_layers.dart';
import 'widgets/map_filter_sheet.dart';
import 'widgets/map_layer_sheet.dart';
import 'widgets/map_overlay_layers.dart';
import 'widgets/marker_cluster_layer.dart';
import 'widgets/site_preview_sheet.dart';
import 'widgets/species_picker_sheet.dart';

const _prefBasemap = 'dive_map_basemap';
const _prefContours = 'dive_map_contours';
const _prefSeamarks = 'dive_map_seamarks';
const _prefLiveCurrents = 'dive_map_live_currents';
const _prefSpeciesHeatmap = 'dive_map_species_heatmap';
const _prefOfflineCache = 'dive_map_offline_cache';
const _prefHeatmapSpeciesId = 'dive_map_heatmap_species_id';

// Frosted-glass panel color used by all map overlays.
const _glassColor = Color(0xCC0D1825); // 80% opacity ocean-navy

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  String _query = '';
  DiveSite? _selectedSite;
  DiveMapBasemap _basemap = DiveMapBasemap.ocean;
  bool _showContours = true;
  bool _showSeamarks = true;
  bool _showLiveCurrents = true;
  bool _showSpeciesHeatmap = false;
  bool _offlineCache = true;
  bool _layersLoaded = false;
  String _cacheStats = '';
  Species? _heatmapSpecies;
  double _currentZoom = 6;
  MarineBounds _marineBounds = const MarineBounds(
    south: 35,
    north: 46,
    west: 6,
    east: 20,
  );

  @override
  void initState() {
    super.initState();
    _loadLayerPrefs();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
      // Wire the text query into the filter provider so markers update live.
      final filters = ref.read(diveSiteFiltersProvider);
      ref.read(diveSiteFiltersProvider.notifier).state =
          filters.copyWith(searchQuery: q.isEmpty ? null : q);
    });
  }

  Future<void> _loadLayerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stats = await DiveMapTileCache.cacheStats();
    if (!mounted) return;

    Species? species;
    final speciesId = prefs.getString(_prefHeatmapSpeciesId);
    if (speciesId != null) {
      species = await ref.read(speciesRepositoryProvider).fetchById(speciesId);
    }

    setState(() {
      final saved = prefs.getString(_prefBasemap);
      _basemap =
          DiveMapBasemap.values.asNameMap()[saved] ?? DiveMapBasemap.ocean;
      _showContours = prefs.getBool(_prefContours) ?? !kIsWeb;
      _showSeamarks = prefs.getBool(_prefSeamarks) ?? true;
      _showLiveCurrents = prefs.getBool(_prefLiveCurrents) ?? true;
      _showSpeciesHeatmap = prefs.getBool(_prefSpeciesHeatmap) ?? false;
      _offlineCache = prefs.getBool(_prefOfflineCache) ?? true;
      _heatmapSpecies = species;
      _cacheStats = stats;
      _layersLoaded = true;
    });
  }

  Future<void> _persistLayerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBasemap, _basemap.name);
    await prefs.setBool(_prefContours, _showContours);
    await prefs.setBool(_prefSeamarks, _showSeamarks);
    await prefs.setBool(_prefLiveCurrents, _showLiveCurrents);
    await prefs.setBool(_prefSpeciesHeatmap, _showSpeciesHeatmap);
    await prefs.setBool(_prefOfflineCache, _offlineCache);
    if (_heatmapSpecies != null) {
      await prefs.setString(_prefHeatmapSpeciesId, _heatmapSpecies!.id);
    }
    final stats = await DiveMapTileCache.cacheStats();
    if (mounted) setState(() => _cacheStats = stats);
  }

  void _updateMarineBounds() {
    final bounds = _mapController.camera.visibleBounds;
    setState(() {
      _currentZoom = _mapController.camera.zoom;
      _marineBounds = MarineBounds(
        south: bounds.south,
        north: bounds.north,
        west: bounds.west,
        east: bounds.east,
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DiveSite> _applyFilters(List<DiveSite> sites) {
    // Filtering is driven by diveSiteFiltersProvider; pass-through.
    return sites;
  }

  Future<void> _openLayerSheet() async {
    await MapLayerSheet.show(
      context,
      basemap: _basemap,
      showContours: _showContours,
      showSeamarks: _showSeamarks,
      showLiveCurrents: _showLiveCurrents,
      showSpeciesHeatmap: _showSpeciesHeatmap,
      offlineCache: _offlineCache,
      cacheStats: _cacheStats,
      heatmapSpecies: _heatmapSpecies,
      onBasemapChanged: (mode) {
        setState(() => _basemap = mode);
        _persistLayerPrefs();
      },
      onContoursChanged: (value) {
        setState(() => _showContours = value);
        _persistLayerPrefs();
      },
      onSeamarksChanged: (value) {
        setState(() => _showSeamarks = value);
        _persistLayerPrefs();
      },
      onLiveCurrentsChanged: (value) {
        setState(() => _showLiveCurrents = value);
        _persistLayerPrefs();
      },
      onSpeciesHeatmapChanged: (value) async {
        if (value && _heatmapSpecies == null) {
          final picked = await SpeciesPickerSheet.pick(context);
          if (picked == null) return;
          setState(() {
            _showSpeciesHeatmap = true;
            _heatmapSpecies = picked;
          });
        } else {
          setState(() => _showSpeciesHeatmap = value);
        }
        unawaited(_persistLayerPrefs());
      },
      onOfflineCacheChanged: (value) {
        setState(() => _offlineCache = value);
        _persistLayerPrefs();
      },
      onPickSpecies: () async {
        final picked = await SpeciesPickerSheet.pick(context);
        if (picked == null) return;
        setState(() {
          _heatmapSpecies = picked;
          _showSpeciesHeatmap = true;
        });
        unawaited(_persistLayerPrefs());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(diveSitesFilteredProvider);
    final filters = ref.watch(diveSiteFiltersProvider);

    final currentsAsync = _showLiveCurrents
        ? ref.watch(marineCurrentsGridProvider(_marineBounds))
        : const AsyncValue<List<MarineCurrentSample>>.data([]);

    final heatmapAsync = _showSpeciesHeatmap && _heatmapSpecies != null
        ? ref.watch(speciesHeatmapProvider(_heatmapSpecies!.id))
        : const AsyncValue<List<SpeciesHeatmapPoint>>.data([]);

    final tileProvider =
        DiveMapTileCache.cachedProvider(enabled: _offlineCache);

    if (!_layersLoaded) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final siteCount = sitesAsync.maybeWhen(
      data: (s) => _applyFilters(s).length,
      orElse: () => 0,
    );

    // Whether any overlay is active (used to tint the layers FAB).
    final anyOverlay =
        _showContours || _showSeamarks || _showLiveCurrents || _showSpeciesHeatmap;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          AsyncValueWidget(
            value: sitesAsync,
            data: (sites) {
              final filtered = sites;
              final center = filtered.isNotEmpty
                  ? filtered.first.location
                  : const LatLng(38.0, 14.0);
              final contourLayer =
                  DiveMapLayers.contours(enabled: _showContours);
              final seamarkLayer =
                  DiveMapLayers.seamarks(enabled: _showSeamarks);

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 6,
                  backgroundColor: const Color(0xFF0C1824),
                  onTap: (_, __) => setState(() => _selectedSite = null),
                  onMapReady: _updateMarineBounds,
                  onMapEvent: (event) {
                    if (event is MapEventMoveEnd) _updateMarineBounds();
                  },
                ),
                children: [
                  DiveMapLayers.basemap(
                    _basemap,
                    tileProvider: tileProvider,
                  ),
                  if (contourLayer != null) contourLayer,
                  if (seamarkLayer != null) seamarkLayer,
                  currentsAsync.when(
                    data: (samples) => CurrentArrowsLayer(samples: samples),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  heatmapAsync.when(
                    data: (points) => SpeciesHeatmapLayer(points: points),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  MarkerClusterLayer(
                    markers: filtered
                        .map(
                          (site) => ClusterMarker(
                            id: site.id,
                            point: site.location,
                            label: site.name,
                            siteType: site.siteType,
                          ),
                        )
                        .toList(),
                    onClusterTap: (items) {
                      if (items.length < 2) {
                        final site = filtered
                            .where((s) => s.id == items.first.id)
                            .firstOrNull;
                        if (site != null) {
                          setState(() => _selectedSite = site);
                        }
                        return;
                      }
                      final lats =
                          items.map((m) => m.point.latitude).toList();
                      final lngs =
                          items.map((m) => m.point.longitude).toList();
                      final centroidLat =
                          lats.reduce((a, b) => a + b) / lats.length;
                      final centroidLng =
                          lngs.reduce((a, b) => a + b) / lngs.length;
                      _mapController.move(
                          LatLng(centroidLat, centroidLng), 10);
                    },
                    onMarkerTap: (marker) {
                      final site = filtered
                          .where((s) => s.id == marker.id)
                          .firstOrNull;
                      if (site != null) {
                        setState(() => _selectedSite = site);
                      }
                    },
                  ),
                  RichAttributionWidget(
                    alignment: AttributionAlignment.bottomLeft,
                    attributions: [
                      TextSourceAttribution(
                        MapConfig.basemap(_basemap).attribution ?? 'Benthyo',
                      ),
                      if (_showContours)
                        const TextSourceAttribution('EMODnet isolines'),
                      if (_showSeamarks)
                        const TextSourceAttribution('OpenSeaMap'),
                      if (_showLiveCurrents)
                        const TextSourceAttribution(
                          'Open-Meteo Marine (Copernicus SMOC)',
                        ),
                    ],
                  ),
                ],
              );
            },
          ),

          // ── Top overlays: search + filter row ────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search bar — frosted glass
                  _GlassPanel(
                    borderRadius: 16,
                    child: Row(
                      children: [
                        const SizedBox(width: AppSpacing.md),
                        Icon(
                          Icons.search,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search dive sites…',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.40),
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              final f = ref.read(diveSiteFiltersProvider);
                              ref
                                  .read(diveSiteFiltersProvider.notifier)
                                  .state = f.copyWith(searchQuery: null);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: AppSpacing.md),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Filter row
                  Row(
                    children: [
                      // Filter button
                      Expanded(
                        child: _GlassPanel(
                          borderRadius: 14,
                          tinted: filters.activeCount > 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => MapFilterSheet.show(context, ref),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tune,
                                    size: 18,
                                    color: filters.activeCount > 0
                                        ? AppColors.accent
                                        : Colors.white.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      filters.activeCount == 0
                                          ? 'Filters'
                                          : '${filters.activeCount} active · ${filters.sortBy.label}',
                                      style: TextStyle(
                                        color: filters.activeCount > 0
                                            ? AppColors.accent
                                            : Colors.white
                                                .withValues(alpha: 0.85),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (filters.activeCount > 0)
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: AppColors.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${filters.activeCount}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),

                      // Site count pill
                      _GlassPanel(
                        borderRadius: 14,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$siteCount',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),

                      // Reset button (only when filters active)
                      if (filters.activeCount > 0)
                        _GlassPanel(
                          borderRadius: 14,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                              ref
                                  .read(diveSiteFiltersProvider.notifier)
                                  .state = DiveSiteFilters.empty;
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Icon(
                                Icons.refresh,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Country chip
                  if (filters.countryCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _GlassPanel(
                          borderRadius: 20,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              ref
                                  .read(diveSiteFiltersProvider.notifier)
                                  .state = filters.copyWith(
                                      clearCountry: true);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.flag_outlined,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    filters.countryCode!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.85),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.close,
                                    size: 13,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Heatmap species chip
                  if (_showSpeciesHeatmap && _heatmapSpecies != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _GlassPanel(
                          borderRadius: 20,
                          tinted: true,
                          tintColor: AppColors.accent,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.thermostat_outlined,
                                  size: 14,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Heatmap: ${_heatmapSpecies!.displayName()}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Layers FAB (bottom-left) ──────────────────────────────────────
          Positioned(
            left: AppSpacing.md,
            bottom: _selectedSite != null ? 268 : 104,
            child: _MapFab(
              icon: anyOverlay ? Icons.layers : Icons.layers_outlined,
              tinted: anyOverlay,
              onTap: _openLayerSheet,
              tooltip: 'Map layers',
            ),
          ),

          // ── Zoom buttons + zoom indicator + recenter (right column) ──────
          Positioned(
            right: AppSpacing.md,
            bottom: _selectedSite != null ? 268 : 104,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom in
                _ZoomButton(
                  icon: Icons.add,
                  onTap: () {
                    final zoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      (zoom + 1).clamp(1.0, 18.0),
                    );
                  },
                ),
                const SizedBox(height: 2),
                // Zoom level badge
                _GlassPanel(
                  borderRadius: 8,
                  child: SizedBox(
                    width: 40,
                    height: 28,
                    child: Center(
                      child: Text(
                        _currentZoom.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Zoom out
                _ZoomButton(
                  icon: Icons.remove,
                  onTap: () {
                    final zoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      (zoom - 1).clamp(1.0, 18.0),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // Recenter / fly-to-site
                _MapFab(
                  icon: _selectedSite != null
                      ? Icons.center_focus_strong
                      : Icons.my_location,
                  tinted: true,
                  onTap: () {
                    final site = _selectedSite;
                    if (site != null) {
                      _mapController.move(site.location, 13);
                    }
                  },
                  tooltip: _selectedSite != null
                      ? 'Fly to site'
                      : 'My location',
                ),
              ],
            ),
          ),

          // ── Site preview sheet ────────────────────────────────────────────
          if (_selectedSite != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SitePreviewSheet(
                site: _selectedSite!,
                siteCount: siteCount,
                onClose: () => setState(() => _selectedSite = null),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const MainNavigationBar(currentIndex: 0),
    );
  }
}

// ── Frosted-glass panel ────────────────────────────────────────────────────────

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.borderRadius = 16,
    this.tinted = false,
    this.tintColor,
  });

  final Widget child;
  final double borderRadius;
  final bool tinted;
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final base = tintColor ?? AppColors.accent;
    final bg = tinted
        ? base.withValues(alpha: 0.14)
        : _glassColor;
    final border = tinted
        ? base.withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.08);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: border, width: 0.8),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Map FAB (dark glass style) ─────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.icon,
    required this.onTap,
    this.tinted = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool tinted;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: _GlassPanel(
        borderRadius: 14,
        tinted: tinted,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 22,
              color: tinted ? AppColors.accent : Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Zoom button (glass) ────────────────────────────────────────────────────────

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: 8,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.85),
            size: 20,
          ),
        ),
      ),
    );
  }
}
