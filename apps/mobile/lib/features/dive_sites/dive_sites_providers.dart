import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/dive_site.dart';
import '../../core/models/dive_site_filters.dart';
import '../../core/models/recent_diver.dart';
import '../../core/models/seasonal_forecast.dart';
import '../../core/models/site_conditions.dart';
import '../../core/supabase/supabase_client.dart';

class DiveSitesRepository {
  DiveSitesRepository(this._client);

  final SupabaseClient _client;

  Future<List<DiveSite>> fetchAll({int limit = 5000}) async {
    final data =
        await _client.from('dive_sites').select().order('name').limit(limit);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(DiveSite.fromJson).toList();
  }

  Future<DiveSite?> fetchById(String id) async {
    final data =
        await _client.from('dive_sites').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return DiveSite.fromJson(data);
  }

  Future<List<DiveSite>> search(String query) async {
    if (query.trim().isEmpty) return fetchAll();
    final data = await _client
        .from('dive_sites')
        .select()
        .or('name.ilike.%$query%,region.ilike.%$query%')
        .limit(50);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(DiveSite.fromJson).toList();
  }

  Future<SiteConditions> fetchConditions(String siteId) async {
    final data = await _client.rpc(
      'site_dive_conditions',
      params: {'p_site_id': siteId},
    );
    if (data is Map<String, dynamic>) {
      return SiteConditions.fromJson(data);
    }
    return const SiteConditions(logCount: 0);
  }

  Future<List<SpeciesHeatmapRow>> fetchSpeciesHeatmap(String speciesId) async {
    final data = await _client.rpc(
      'species_sighting_heatmap',
      params: {'p_species_id': speciesId},
    );
    if (data is! List) return const [];
    return data
        .cast<Map<String, dynamic>>()
        .map(SpeciesHeatmapRow.fromJson)
        .toList();
  }

  Future<List<RecentDiver>> fetchRecentDivers(String siteId) async {
    final data = await _client.rpc(
      'recent_divers_at_site',
      params: {'p_site_id': siteId, 'p_days': 90},
    );
    if (data is! List) return const [];
    return data
        .cast<Map<String, dynamic>>()
        .map(RecentDiver.fromJson)
        .toList();
  }

  /// Fetch dive sites with the [DiveSiteFilters] applied. The previous
  /// repository method only supported free-text search; this method
  /// supports country, region, difficulty, site type, access type,
  /// min/max depth, verified-only, and sort.
  Future<List<DiveSite>> fetchFiltered(DiveSiteFilters filters) async {
    var query = _client.from('dive_sites').select();
    if (filters.countryCode != null) {
      query = query.eq('country_code', filters.countryCode!);
    }
    if (filters.region != null && filters.region!.isNotEmpty) {
      query = query.ilike('region', '%${filters.region}%');
    }
    if (filters.difficulty != null) {
      query = query.eq('difficulty', filters.difficulty!.name);
    }
    if (filters.siteType != null) {
      query = query.eq('site_type', filters.siteType!.name);
    }
    if (filters.accessType != null) {
      query = query.eq('access_type', filters.accessType!.name);
    }
    if (filters.minDepth != null) {
      query = query.gte('depth_max', filters.minDepth!);
    }
    if (filters.maxDepth != null) {
      query = query.lte('depth_min', filters.maxDepth!);
    }
    if (filters.verifiedOnly) {
      query = query.eq('verified', true);
    }
    if (filters.query.trim().isNotEmpty) {
      // Note: this hits the tsvector index defined in migration 004.
      final q = filters.query.trim();
      query = query.or('name.ilike.%$q%,region.ilike.%$q%');
    }
    final ascending = filters.sortBy == DiveSiteSort.name ||
        filters.sortBy == DiveSiteSort.country;
    final data = await query.order(filters.sortBy.dbColumn, ascending: ascending).limit(2000);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(DiveSite.fromJson).toList();
  }

  /// Distinct country codes that have at least one dive site. Used to
  /// populate the country filter dropdown.
  Future<List<({String code, String name})>> fetchAvailableCountries() async {
    final data = await _client
        .from('dive_sites')
        .select('country_code, region')
        .not('country_code', 'is', null)
        .limit(2000);
    final rows = (data as List).cast<Map<String, dynamic>>();
    final codes = <String>{};
    String nameFor(String code) {
      // Lightweight ISO 3166 alpha-2 -> English short name. Avoids a
      // heavyweight package; for the small set of countries we ship in
      // the seed this is more than enough.
      const names = <String, String>{
        'AD': 'Andorra', 'AL': 'Albania', 'AT': 'Austria',
        'BA': 'Bosnia and Herzegovina', 'BE': 'Belgium',
        'BG': 'Bulgaria', 'CH': 'Switzerland', 'CY': 'Cyprus',
        'CZ': 'Czechia', 'DE': 'Germany', 'DK': 'Denmark',
        'EE': 'Estonia', 'EG': 'Egypt', 'ES': 'Spain',
        'FI': 'Finland', 'FR': 'France', 'GB': 'United Kingdom',
        'GR': 'Greece', 'HR': 'Croatia', 'HU': 'Hungary',
        'IE': 'Ireland', 'IL': 'Israel', 'IS': 'Iceland',
        'IT': 'Italy', 'JO': 'Jordan', 'LB': 'Lebanon',
        'LI': 'Liechtenstein', 'LT': 'Lithuania', 'LU': 'Luxembourg',
        'LV': 'Latvia', 'MA': 'Morocco', 'MC': 'Monaco',
        'ME': 'Montenegro', 'MT': 'Malta', 'NL': 'Netherlands',
        'NO': 'Norway', 'PL': 'Poland', 'PT': 'Portugal',
        'RO': 'Romania', 'RS': 'Serbia', 'RU': 'Russia',
        'SE': 'Sweden', 'SI': 'Slovenia', 'SK': 'Slovakia',
        'TN': 'Tunisia', 'TR': 'Turkey', 'UA': 'Ukraine',
        'US': 'United States',
      };
      return names[code] ?? code;
    }
    for (final row in rows) {
      final code = row['country_code'] as String?;
      if (code != null) codes.add(code);
    }
    final sorted = codes.toList()..sort();
    return sorted.map((c) => (code: c, name: nameFor(c))).toList();
  }

  Future<SeasonalForecast> fetchSeasonalForecast({
    required String speciesId,
    String? siteId,
  }) async {
    final data = await _client.rpc(
      'species_seasonal_forecast',
      params: {
        'p_species_id': speciesId,
        if (siteId != null) 'p_site_id': siteId,
      },
    );
    if (data is Map<String, dynamic>) {
      return SeasonalForecast.fromJson(data);
    }
    return const SeasonalForecast(
      bestMonths: [],
      monthlyCounts: {},
      totalSightings: 0,
    );
  }
}

class SpeciesHeatmapRow {
  const SpeciesHeatmapRow({
    required this.siteId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.sightingCount,
  });

  final String siteId;
  final String name;
  final double lat;
  final double lng;
  final int sightingCount;

  factory SpeciesHeatmapRow.fromJson(Map<String, dynamic> json) {
    return SpeciesHeatmapRow(
      siteId: json['dive_site_id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      sightingCount: (json['sighting_count'] as num).toInt(),
    );
  }
}

final diveSitesRepositoryProvider = Provider<DiveSitesRepository>((ref) {
  return DiveSitesRepository(ref.watch(supabaseClientProvider));
});

final diveSitesProvider = FutureProvider<List<DiveSite>>((ref) {
  return ref.watch(diveSitesRepositoryProvider).fetchAll();
});

/// The current map filter state. Persisted to SharedPreferences by the
/// map screen on change; consumed by [diveSitesFilteredProvider] and the
/// filter sheet.
final diveSiteFiltersProvider =
    StateProvider<DiveSiteFilters>((ref) => DiveSiteFilters.empty);

/// Distinct list of country codes present in the dive_sites table.
final availableCountriesProvider =
    FutureProvider<List<({String code, String name})>>((ref) {
  return ref.watch(diveSitesRepositoryProvider).fetchAvailableCountries();
});

/// Filtered + sorted list of dive sites. The map screen, the list
/// screen, and the dashboard's "operators/me/sites" view all consume
/// this single source of truth.
final diveSitesFilteredProvider =
    FutureProvider<List<DiveSite>>((ref) async {
  final filters = ref.watch(diveSiteFiltersProvider);
  return ref.watch(diveSitesRepositoryProvider).fetchFiltered(filters);
});

final diveSiteProvider = FutureProvider.family<DiveSite?, String>((ref, id) {
  return ref.watch(diveSitesRepositoryProvider).fetchById(id);
});

final diveSiteSearchProvider =
    FutureProvider.family<List<DiveSite>, String>((ref, query) {
  return ref.watch(diveSitesRepositoryProvider).search(query);
});

final siteConditionsProvider =
    FutureProvider.family<SiteConditions, String>((ref, siteId) {
  return ref.watch(diveSitesRepositoryProvider).fetchConditions(siteId);
});
