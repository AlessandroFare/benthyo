import 'dart:async' show unawaited;

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
    // The DiveSiteFilters provider now drives filtering. This wrapper
    // remains so the existing call sites in the build method still
    // work — it just passes the list through unchanged.
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
    // The new diveSitesFilteredProvider is the single source of truth
    // for the map + list. It reads the DiveSiteFilters from
    // diveSiteFiltersProvider which is mutated by the MapFilterSheet.
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
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
                  backgroundColor: const Color(0xFF1A2332),
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
                      // Zoom to the cluster centroid; the map controller
                      // supports a boundingLatLngBounds but we use
                      // move() with a tighter zoom for a punchy feel.
                      final lats = items.map((m) => m.point.latitude).toList();
                      final lngs = items.map((m) => m.point.longitude).toList();
                      final centroidLat = lats.reduce((a, b) => a + b) / lats.length;
                      final centroidLng = lngs.reduce((a, b) => a + b) / lngs.length;
                      _mapController.move(LatLng(centroidLat, centroidLng), 10);
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    elevation: 6,
                    shadowColor: Colors.black45,
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search dive sites...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (filters.countryCode != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          avatar: const Icon(Icons.flag, size: 16),
                          label: Text(filters.countryCode!),
                          onDeleted: () {
                            ref
                                .read(diveSiteFiltersProvider.notifier)
                                .state = filters.copyWith(clearCountry: true);
                          },
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          elevation: 4,
                          shadowColor: Colors.black26,
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.white,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              await MapFilterSheet.show(context, ref);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tune,
                                    size: 20,
                                    color: filters.activeCount > 0
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    filters.activeCount == 0
                                        ? 'All filters'
                                        : '${filters.activeCount} filter${filters.activeCount == 1 ? '' : 's'} · ${filters.sortBy.label}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  AnimatedRotation(
                                    duration: const Duration(
                                        milliseconds: 220,),
                                    turns: filters.activeCount > 0 ? 0.25 : 0,
                                    child: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Material(
                        elevation: 4,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                        color: filters.activeCount > 0
                            ? AppColors.primary
                            : Colors.white,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                            ref.read(diveSiteFiltersProvider.notifier).state =
                                DiveSiteFilters.empty;
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.refresh,
                              color: filters.activeCount > 0
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showSpeciesHeatmap && _heatmapSpecies != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Material(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: Text(
                            'Heatmap: ${_heatmapSpecies!.displayName()}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            bottom: _selectedSite != null ? 260 : 96,
            child: FloatingActionButton(
              heroTag: 'layers',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              onPressed: _openLayerSheet,
              child: const Icon(Icons.layers_outlined),
            ),
          ),
          if (_selectedSite != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SitePreviewSheet(
                site: _selectedSite!,
                siteCount: sitesAsync.maybeWhen(
                  data: (sites) => _applyFilters(sites).length,
                  orElse: () => 0,
                ),
                onClose: () => setState(() => _selectedSite = null),
              ),
            ),
          Positioned(
            right: AppSpacing.md,
            bottom: _selectedSite != null ? 380 : 216,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 4),
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
              ],
            ),
          ),
          Positioned(
            right: AppSpacing.md,
            bottom: _selectedSite != null ? 260 : 96,
            child: FloatingActionButton(
              heroTag: 'recenter',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () {
                final site = _selectedSite;
                if (site != null) {
                  _mapController.move(site.location, 10);
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MainNavigationBar(currentIndex: 0),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
      ),
    );
  }
}
