/// Lightweight value object returned by the `citizen_science_impact` RPC.
///
/// Counts how many of the user's sightings have been forwarded to external
/// citizen-science databases (iNaturalist and GBIF) and how many distinct
/// platforms have received at least one contribution.
class CitizenScienceImpact {
  const CitizenScienceImpact({
    required this.totalSightings,
    required this.inatContributed,
    required this.gbifContributed,
    required this.databasesCount,
  });

  /// Total user-created sightings (source = 'user').
  final int totalSightings;

  /// Sightings successfully pushed to iNaturalist.
  final int inatContributed;

  /// Sightings included in a GBIF export batch.
  final int gbifContributed;

  /// Number of distinct platforms that received at least one sighting (0–2).
  final int databasesCount;

  factory CitizenScienceImpact.fromJson(Map<String, dynamic> json) {
    return CitizenScienceImpact(
      totalSightings: (json['total_sightings'] as num?)?.toInt() ?? 0,
      inatContributed: (json['inat_contributed'] as num?)?.toInt() ?? 0,
      gbifContributed: (json['gbif_contributed'] as num?)?.toInt() ?? 0,
      databasesCount: (json['databases_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Returns true when the user has contributed to at least one external DB.
  bool get hasContributed =>
      inatContributed > 0 || gbifContributed > 0;

  /// Total sightings shared across all external databases.
  int get totalContributed => inatContributed + gbifContributed;
}
