import 'enums.dart';

/// Aggregated dive log conditions for a site (from `site_dive_conditions` RPC).
class SiteConditions {
  const SiteConditions({
    required this.logCount,
    this.avgVisibilityM,
    this.typicalCurrent,
    this.currentCounts = const {},
  });

  final int logCount;
  final double? avgVisibilityM;
  final CurrentStrength? typicalCurrent;
  final Map<CurrentStrength, int> currentCounts;

  factory SiteConditions.fromJson(Map<String, dynamic> json) {
    final countsRaw = json['current_counts'];
    final counts = <CurrentStrength, int>{};
    if (countsRaw is Map) {
      for (final entry in countsRaw.entries) {
        final strength = CurrentStrengthX.fromDb(entry.key.toString());
        if (strength == null) continue;
        final value = entry.value;
        if (value is num) counts[strength] = value.toInt();
      }
    }

    final typicalRaw = json['typical_current'] as String?;
    return SiteConditions(
      logCount: (json['log_count'] as num?)?.toInt() ?? 0,
      avgVisibilityM: (json['avg_visibility_m'] as num?)?.toDouble(),
      typicalCurrent: typicalRaw != null
          ? CurrentStrengthX.fromDb(typicalRaw)
          : null,
      currentCounts: counts,
    );
  }

  String currentLabel() {
    if (typicalCurrent == null) return 'No diver reports yet';
    return switch (typicalCurrent!) {
      CurrentStrength.none => 'Usually calm',
      CurrentStrength.light => 'Light current',
      CurrentStrength.moderate => 'Moderate current',
      CurrentStrength.strong => 'Strong current',
    };
  }
}
