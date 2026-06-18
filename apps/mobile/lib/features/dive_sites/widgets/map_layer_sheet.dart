import 'package:flutter/material.dart';

import '../../../core/config/map_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/species.dart';

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
    return SafeArea(
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Dive map layers',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ocean basemaps, depth isolines, live currents (Open-Meteo / Copernicus), and species sighting heatmaps.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Basemap', style: _sectionStyle(context)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: DiveMapBasemap.values.map((mode) {
                final preset = MapConfig.basemap(mode);
                return ChoiceChip(
                  label: Text(preset.label),
                  selected: basemap == mode,
                  onSelected: (_) => onBasemapChanged(mode),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Overlays', style: _sectionStyle(context)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Depth isolines'),
              subtitle: const Text('EMODnet — slope & wall planning'),
              value: showContours,
              onChanged: onContoursChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nautical marks'),
              subtitle: const Text('OpenSeaMap moorings & hazards'),
              value: showSeamarks,
              onChanged: onSeamarksChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Live ocean currents'),
              subtitle: const Text('NOAA/GFS via Open-Meteo — cyan arrows'),
              value: showLiveCurrents,
              onChanged: onLiveCurrentsChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Species heatmap'),
              subtitle: Text(
                heatmapSpecies?.displayName() ?? 'Pick a species to overlay',
              ),
              value: showSpeciesHeatmap,
              onChanged: onSpeciesHeatmapChanged,
            ),
            if (showSpeciesHeatmap)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onPickSpecies,
                  icon: const Icon(Icons.pets),
                  label: Text(
                    heatmapSpecies == null
                        ? 'Choose species'
                        : 'Change species',
                  ),
                ),
              ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Offline tile cache'),
              subtitle: Text(
                '$cacheStats · pan/zoom to cache ${MapConfig.tileCacheMaxTiles} tiles max',
              ),
              value: offlineCache,
              onChanged: onOfflineCacheChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Live currents are model estimates (~8 km). Site cards also show diver-reported conditions.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
}
