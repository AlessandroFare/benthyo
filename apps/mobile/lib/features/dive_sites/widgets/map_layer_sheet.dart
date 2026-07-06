import 'package:flutter/material.dart';

import '../../../core/config/map_config.dart';
import '../../../core/models/species.dart';
import '../../../core/theme/app_theme.dart';

class MapLayerSheet extends StatefulWidget {
  const MapLayerSheet({
    super.key,
    required this.basemap,
    required this.showContours,
    required this.showSeamarks,
    required this.showLiveCurrents,
    required this.showSpeciesHeatmap,
    required this.offlineCache,
    required this.cacheStats,
    this.heatmapSpecies,
    required this.onBasemapChanged,
    required this.onContoursChanged,
    required this.onSeamarksChanged,
    required this.onLiveCurrentsChanged,
    required this.onSpeciesHeatmapChanged,
    required this.onOfflineCacheChanged,
    required this.onPickSpecies,
  });

  final DiveMapBasemap basemap;
  final bool showContours;
  final bool showSeamarks;
  final bool showLiveCurrents;
  final bool showSpeciesHeatmap;
  final bool offlineCache;
  final String cacheStats;
  final Species? heatmapSpecies;
  final ValueChanged<DiveMapBasemap> onBasemapChanged;
  final ValueChanged<bool> onContoursChanged;
  final ValueChanged<bool> onSeamarksChanged;
  final ValueChanged<bool> onLiveCurrentsChanged;
  final ValueChanged<bool> onSpeciesHeatmapChanged;
  final ValueChanged<bool> onOfflineCacheChanged;

  /// Opens the species picker and returns the chosen species (or null if
  /// cancelled). The sheet uses the return value to update its own local
  /// state immediately; the caller may also persist/update its own state
  /// as a side effect.
  final Future<Species?> Function() onPickSpecies;

  static Future<void> show(
    BuildContext context, {
    required DiveMapBasemap basemap,
    required bool showContours,
    required bool showSeamarks,
    required bool showLiveCurrents,
    required bool showSpeciesHeatmap,
    required bool offlineCache,
    required String cacheStats,
    Species? heatmapSpecies,
    required ValueChanged<DiveMapBasemap> onBasemapChanged,
    required ValueChanged<bool> onContoursChanged,
    required ValueChanged<bool> onSeamarksChanged,
    required ValueChanged<bool> onLiveCurrentsChanged,
    required ValueChanged<bool> onSpeciesHeatmapChanged,
    required ValueChanged<bool> onOfflineCacheChanged,
    required Future<Species?> Function() onPickSpecies,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MapLayerSheet(
        basemap: basemap,
        showContours: showContours,
        showSeamarks: showSeamarks,
        showLiveCurrents: showLiveCurrents,
        showSpeciesHeatmap: showSpeciesHeatmap,
        offlineCache: offlineCache,
        cacheStats: cacheStats,
        heatmapSpecies: heatmapSpecies,
        onBasemapChanged: onBasemapChanged,
        onContoursChanged: onContoursChanged,
        onSeamarksChanged: onSeamarksChanged,
        onLiveCurrentsChanged: onLiveCurrentsChanged,
        onSpeciesHeatmapChanged: onSpeciesHeatmapChanged,
        onOfflineCacheChanged: onOfflineCacheChanged,
        onPickSpecies: onPickSpecies,
      ),
    );
  }

  @override
  State<MapLayerSheet> createState() => _MapLayerSheetState();
}

class _MapLayerSheetState extends State<MapLayerSheet> {
  // Local mirror of the layer state so the sheet's own UI (switches,
  // selected basemap chip) reflects taps immediately. The bottom sheet is
  // a separate route from MapScreen, so a setState() on the parent does
  // NOT rebuild this widget — without local state the switches/chips
  // would look "stuck" even though the filtering itself works fine.
  late DiveMapBasemap _basemap;
  late bool _showContours;
  late bool _showSeamarks;
  late bool _showLiveCurrents;
  late bool _showSpeciesHeatmap;
  late bool _offlineCache;
  Species? _heatmapSpecies;

  @override
  void initState() {
    super.initState();
    _basemap = widget.basemap;
    _showContours = widget.showContours;
    _showSeamarks = widget.showSeamarks;
    _showLiveCurrents = widget.showLiveCurrents;
    _showSpeciesHeatmap = widget.showSpeciesHeatmap;
    _offlineCache = widget.offlineCache;
    _heatmapSpecies = widget.heatmapSpecies;
  }

  Future<void> _handleSpeciesHeatmapToggle(bool value) async {
    if (value && _heatmapSpecies == null) {
      final picked = await widget.onPickSpecies();
      if (picked == null) return;
      setState(() {
        _showSpeciesHeatmap = true;
        _heatmapSpecies = picked;
      });
      widget.onSpeciesHeatmapChanged(true);
      return;
    }
    setState(() => _showSpeciesHeatmap = value);
    widget.onSpeciesHeatmapChanged(value);
  }

  Future<void> _handlePickSpecies() async {
    final picked = await widget.onPickSpecies();
    if (picked == null) return;
    setState(() {
      _heatmapSpecies = picked;
      _showSpeciesHeatmap = true;
    });
    widget.onSpeciesHeatmapChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1825),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Title
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.layers_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dive map layers',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                      ),
                      Text(
                        'Basemaps, depth, currents & heatmaps',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Basemap section ──────────────────────────────────────────
              _SectionHeader(
                icon: Icons.map_outlined,
                label: 'Basemap',
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: DiveMapBasemap.values.map((mode) {
                  final preset = MapConfig.basemap(mode);
                  final selected = _basemap == mode;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _basemap = mode);
                      widget.onBasemapChanged(mode);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 0.9,
                        ),
                      ),
                      child: Text(
                        preset.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
              _Divider(),

              // ── Overlays section ─────────────────────────────────────────
              const SizedBox(height: AppSpacing.md),
              _SectionHeader(
                icon: Icons.layers_outlined,
                label: 'Overlays',
              ),
              const SizedBox(height: AppSpacing.xs),

              _OverlayTile(
                icon: Icons.waves_outlined,
                title: 'Depth isolines',
                subtitle: 'EMODnet — slope & wall planning',
                value: _showContours,
                onChanged: (v) {
                  setState(() => _showContours = v);
                  widget.onContoursChanged(v);
                },
              ),
              _OverlayTile(
                icon: Icons.anchor,
                title: 'Nautical marks',
                subtitle: 'OpenSeaMap moorings & hazards',
                value: _showSeamarks,
                onChanged: (v) {
                  setState(() => _showSeamarks = v);
                  widget.onSeamarksChanged(v);
                },
              ),
              _OverlayTile(
                icon: Icons.air,
                title: 'Live ocean currents',
                subtitle: 'NOAA/GFS via Open-Meteo — cyan arrows',
                value: _showLiveCurrents,
                onChanged: (v) {
                  setState(() => _showLiveCurrents = v);
                  widget.onLiveCurrentsChanged(v);
                },
              ),
              _OverlayTile(
                icon: Icons.thermostat_outlined,
                title: 'Species heatmap',
                subtitle:
                    _heatmapSpecies?.displayName() ?? 'Pick a species to overlay',
                value: _showSpeciesHeatmap,
                onChanged: _handleSpeciesHeatmapToggle,
              ),

              if (_showSpeciesHeatmap)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: GestureDetector(
                    onTap: _handlePickSpecies,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.30),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pets_outlined,
                              size: 14, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Text(
                            _heatmapSpecies == null
                                ? 'Choose species'
                                : 'Change species',
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

              _Divider(),
              const SizedBox(height: AppSpacing.md),

              // ── Cache section ────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.download_outlined,
                label: 'Offline cache',
              ),
              const SizedBox(height: AppSpacing.xs),

              _OverlayTile(
                icon: Icons.save_outlined,
                title: 'Offline tile cache',
                subtitle:
                    '${widget.cacheStats} · pan/zoom to cache ${MapConfig.tileCacheMaxTiles} tiles max',
                value: _offlineCache,
                onChanged: (v) {
                  setState(() => _offlineCache = v);
                  widget.onOfflineCacheChanged(v);
                },
              ),

              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'Live currents are model estimates (~8 km resolution). Site cards also show diver-reported conditions when available.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.45),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.45)),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

// ── Overlay tile (dark themed) ──────────────────────────────────────────────────

class _OverlayTile extends StatelessWidget {
  const _OverlayTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: value
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.40),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.accent,
              activeTrackColor: AppColors.accent.withValues(alpha: 0.25),
              inactiveThumbColor: Colors.white.withValues(alpha: 0.35),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section divider ─────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.8,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}