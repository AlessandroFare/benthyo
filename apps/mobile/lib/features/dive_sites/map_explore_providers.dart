import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/species.dart';
import 'services/marine_currents_service.dart';
import 'dive_sites_providers.dart';

final marineCurrentsServiceProvider = Provider<MarineCurrentsService>((ref) {
  final svc = MarineCurrentsService();
  ref.onDispose(svc.dispose);
  return svc;
});

final marineCurrentsGridProvider = FutureProvider.family<
    List<MarineCurrentSample>, MarineBounds>((ref, bounds) {
  return ref.watch(marineCurrentsServiceProvider).fetchGrid(bounds);
});

final siteLiveCurrentProvider =
    FutureProvider.family<MarineCurrentSample?, LatLng>((ref, point) {
  return ref.watch(marineCurrentsServiceProvider).fetchPoint(point);
});

class SpeciesHeatmapPoint {
  const SpeciesHeatmapPoint({
    required this.siteId,
    required this.name,
    required this.location,
    required this.sightingCount,
  });

  final String siteId;
  final String name;
  final LatLng location;
  final int sightingCount;
}

final speciesHeatmapProvider = FutureProvider.family<
    List<SpeciesHeatmapPoint>, String>((ref, speciesId) async {
  final repo = ref.watch(diveSitesRepositoryProvider);
  final rows = await repo.fetchSpeciesHeatmap(speciesId);
  return rows
      .map(
        (r) => SpeciesHeatmapPoint(
          siteId: r.siteId,
          name: r.name,
          location: LatLng(r.lat, r.lng),
          sightingCount: r.sightingCount,
        ),
      )
      .toList();
});

final heatmapSpeciesProvider = StateProvider<Species?>((ref) => null);
