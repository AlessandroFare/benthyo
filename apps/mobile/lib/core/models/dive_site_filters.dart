import 'package:flutter/foundation.dart';

import '../models/enums.dart';

/// A normalised representation of every filter that can be applied to the
/// dive-site map and list. Created from URL query parameters in
/// `app_router.dart`, persisted in `SharedPreferences`, mutated by the
/// new `MapFilterSheet`, and consumed by `diveSitesFilteredProvider`.
@immutable
class DiveSiteFilters {
  const DiveSiteFilters({
    this.countryCode,
    this.region,
    this.difficulty,
    this.siteType,
    this.accessType,
    this.minDepth,
    this.maxDepth,
    this.verifiedOnly = false,
    this.sortBy = DiveSiteSort.name,
    this.query = '',
  });

  final String? countryCode;
  final String? region;
  final SiteDifficulty? difficulty;
  final SiteType? siteType;
  final AccessType? accessType;
  final int? minDepth;
  final int? maxDepth;
  final bool verifiedOnly;
  final DiveSiteSort sortBy;
  final String query;

  static const empty = DiveSiteFilters();

  /// True when no filter is active. Used by the UI to render the
  /// "All filters" chip without an indicator dot.
  bool get isEmpty =>
      countryCode == null &&
      region == null &&
      difficulty == null &&
      siteType == null &&
      accessType == null &&
      minDepth == null &&
      maxDepth == null &&
      !verifiedOnly &&
      query.isEmpty;

  int get activeCount {
    var n = 0;
    if (countryCode != null) n++;
    if (region != null) n++;
    if (difficulty != null) n++;
    if (siteType != null) n++;
    if (accessType != null) n++;
    if (minDepth != null) n++;
    if (maxDepth != null) n++;
    if (verifiedOnly) n++;
    if (query.isNotEmpty) n++;
    return n;
  }

  DiveSiteFilters copyWith({
    String? countryCode,
    String? region,
    SiteDifficulty? difficulty,
    SiteType? siteType,
    AccessType? accessType,
    int? minDepth,
    int? maxDepth,
    bool? verifiedOnly,
    DiveSiteSort? sortBy,
    String? query,
    bool clearCountry = false,
    bool clearRegion = false,
    bool clearDifficulty = false,
    bool clearSiteType = false,
    bool clearAccessType = false,
    bool clearMinDepth = false,
    bool clearMaxDepth = false,
    bool clearQuery = false,
  }) {
    return DiveSiteFilters(
      countryCode: clearCountry ? null : (countryCode ?? this.countryCode),
      region: clearRegion ? null : (region ?? this.region),
      difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
      siteType: clearSiteType ? null : (siteType ?? this.siteType),
      accessType: clearAccessType ? null : (accessType ?? this.accessType),
      minDepth: clearMinDepth ? null : (minDepth ?? this.minDepth),
      maxDepth: clearMaxDepth ? null : (maxDepth ?? this.maxDepth),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      sortBy: sortBy ?? this.sortBy,
      query: clearQuery ? '' : (query ?? this.query),
    );
  }
}

enum DiveSiteSort { name, depth, difficulty, country }

extension DiveSiteSortX on DiveSiteSort {
  String get dbColumn {
    switch (this) {
      case DiveSiteSort.name:
        return 'name';
      case DiveSiteSort.depth:
        return 'depth_max';
      case DiveSiteSort.difficulty:
        return 'difficulty';
      case DiveSiteSort.country:
        return 'country_code';
    }
  }

  String get label {
    switch (this) {
      case DiveSiteSort.name:
        return 'Name (A → Z)';
      case DiveSiteSort.depth:
        return 'Max depth';
      case DiveSiteSort.difficulty:
        return 'Difficulty';
      case DiveSiteSort.country:
        return 'Country';
    }
  }
}
