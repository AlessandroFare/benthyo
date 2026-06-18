class SeasonalForecast {
  const SeasonalForecast({
    required this.bestMonths,
    required this.monthlyCounts,
    required this.totalSightings,
  });

  final List<int> bestMonths;
  final Map<int, int> monthlyCounts;
  final int totalSightings;

  factory SeasonalForecast.fromJson(Map<String, dynamic> json) {
    final bestRaw = json['best_months'];
    final months = <int>[];
    if (bestRaw is List) {
      for (final m in bestRaw) {
        if (m is num) months.add(m.toInt());
      }
    }

    final countsRaw = json['monthly_counts'];
    final counts = <int, int>{};
    if (countsRaw is Map) {
      for (final entry in countsRaw.entries) {
        final month = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (month != null && value is num) counts[month] = value.toInt();
      }
    }

    if (months.isEmpty && counts.isNotEmpty) {
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      months.addAll(sorted.take(3).map((e) => e.key));
    }

    return SeasonalForecast(
      bestMonths: months,
      monthlyCounts: counts,
      totalSightings: (json['total_sightings'] as num?)?.toInt() ?? 0,
    );
  }

  static const monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String bestSeasonLabel() {
    if (bestMonths.isEmpty) return 'Not enough sightings yet';
    return bestMonths.map((m) => monthNames[m.clamp(1, 12)]).join(', ');
  }
}
