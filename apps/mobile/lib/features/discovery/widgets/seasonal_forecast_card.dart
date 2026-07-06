import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/seasonal_forecast.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../discovery_providers.dart';

class SeasonalForecastCard extends ConsumerWidget {
  const SeasonalForecastCard({
    super.key,
    required this.speciesId,
    this.siteId,
    this.title = 'Best season to see',
  });

  final String speciesId;
  final String? siteId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final forecastAsync = ref.watch(
      speciesSeasonalForecastProvider((speciesId: speciesId, siteId: siteId)),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: AsyncValueWidget(
          value: forecastAsync,
          data: (forecast) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                forecast.bestSeasonLabel(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: isDark ? AppColors.accent : AppColors.primary,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Based on ${forecast.totalSightings} community sightings',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (forecast.monthlyCounts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _MonthBars(counts: forecast.monthlyCounts),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.counts});

  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) {
    final peak = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(12, (index) {
          final month = index + 1;
          final value = counts[month] ?? 0;
          final height = peak == 0 ? 4.0 : (value / peak) * 56 + 4;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    SeasonalForecast.monthNames[month],
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
