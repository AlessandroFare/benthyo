import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/recent_diver.dart';
import '../../core/models/seasonal_forecast.dart';
import '../dive_sites/dive_sites_providers.dart';

final recentDiversAtSiteProvider =
    FutureProvider.family<List<RecentDiver>, String>((ref, siteId) async {
  return ref.watch(diveSitesRepositoryProvider).fetchRecentDivers(siteId);
});

final speciesSeasonalForecastProvider = FutureProvider.family<
    SeasonalForecast, ({String speciesId, String? siteId})>((ref, args) async {
  return ref.watch(diveSitesRepositoryProvider).fetchSeasonalForecast(
        speciesId: args.speciesId,
        siteId: args.siteId,
      );
});
