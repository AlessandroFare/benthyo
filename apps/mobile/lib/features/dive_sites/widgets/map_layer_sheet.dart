import 'package:flutter/material.dart';

import '../../../core/config/map_config.dart';
import '../../../core/models/species.dart';
import '../../../core/theme/app_theme.dart';

class MapLayerSheet extends StatelessWidget {
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
  final VoidCallback onPickSpecies;

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
    required VoidCallback onPickSpecies,
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
                  final selected = basemap == mode;
                  return GestureDetector(
                    onTap: () => onBasemapChanged(mode),
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
                value: showContours,
                onChanged: onContoursChanged,
              ),
              _OverlayTile(
                icon: Icons.anchor,
                title: 'Nautical marks',
                subtitle: 'OpenSeaMap moorings & hazards',
                value: showSeamarks,
                onChanged: onSeamarksChanged,
              ),
              _OverlayTile(
                icon: Icons.air,
                title: 'Live ocean currents',
                subtitle: 'NOAA/GFS via Open-Meteo — cyan arrows',
                value: showLiveCurrents,
                onChanged: onLiveCurrentsChanged,
              ),
              _OverlayTile(
                icon: Icons.thermostat_outlined,
                title: 'Species heatmap',
                subtitle:
                    heatmapSpecies?.displayName() ?? 'Pick a species to overlay',
                value: showSpeciesHeatmap,
                onChanged: onSpeciesHeatmapChanged,
              ),

              if (showSpeciesHeatmap)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: GestureDetector(
                    onTap: onPickSpecies,
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
                            heatmapSpecies == null
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
                    '$cacheStats · pan/zoom to cache ${MapConfig.tileCacheMaxTiles} tiles max',
                value: offlineCache,
                onChanged: onOfflineCacheChanged,
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
