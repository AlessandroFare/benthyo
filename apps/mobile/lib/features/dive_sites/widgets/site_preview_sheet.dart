import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/dive_site.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/site_conditions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/ocean_tag.dart';
import '../dive_sites_providers.dart';
import '../map_explore_providers.dart';
import '../services/marine_currents_service.dart';

class SitePreviewSheet extends ConsumerWidget {
  const SitePreviewSheet({
    super.key,
    required this.site,
    required this.siteCount,
    required this.onClose,
  });

  final DiveSite site;
  final int siteCount;
  final VoidCallback onClose;

  static Color markerColor(SiteType type) {
    return switch (type) {
      SiteType.reef => const Color(0xFF2ECC71),
      SiteType.wreck => const Color(0xFFE74C3C),
      SiteType.wall => const Color(0xFF3498DB),
      SiteType.cave => const Color(0xFF9B59B6),
      SiteType.pinnacle => const Color(0xFFF39C12),
      SiteType.muck => const Color(0xFF95A5A6),
      SiteType.other => AppColors.accent,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conditionsAsync = ref.watch(siteConditionsProvider(site.id));
    final liveCurrentAsync = ref.watch(siteLiveCurrentProvider(site.location));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '$siteCount sites nearby',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        markerColor(site.siteType).withValues(alpha: 0.85),
                        AppColors.primary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: AppSpacing.lg,
                        bottom: AppSpacing.lg,
                        right: AppSpacing.lg,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OceanTag(
                              label: site.difficulty.dbValue,
                              color: Colors.white.withValues(alpha: 0.18),
                              textColor: Colors.white,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              site.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            Text(
                              '${site.region ?? site.countryCode} · ${site.depthMax.toStringAsFixed(0)}m max',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _DepthProfileBar(
                depthMin: site.depthMin,
                depthMax: site.depthMax,
              ),
              const SizedBox(height: AppSpacing.sm),
              AsyncValueWidget(
                value: conditionsAsync,
                data: (conditions) => _ConditionsRow(conditions: conditions),
              ),
              const SizedBox(height: AppSpacing.sm),
              liveCurrentAsync.when(
                data: (MarineCurrentSample? live) {
                  if (live == null) return const SizedBox.shrink();
                  final hint = DriftPlanHint.compute(
                    depthMin: site.depthMin,
                    depthMax: site.depthMax,
                    siteType: site.siteType.dbValue,
                    liveCurrent: live,
                    loggedVisibilityM:
                        conditionsAsync.valueOrNull?.avgVisibilityM,
                  );
                  return _DriftHintCard(hint: hint, live: live);
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClose,
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        onClose();
                        context.push('/dive-sites/${site.id}');
                      },
                      child: const Text('View site'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepthProfileBar extends StatelessWidget {
  const _DepthProfileBar({
    required this.depthMin,
    required this.depthMax,
  });

  final double depthMin;
  final double depthMax;

  @override
  Widget build(BuildContext context) {
    final range = (depthMax - depthMin).clamp(1, 120);
    final minFraction = (depthMin / (depthMin + range)).clamp(0.0, 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Depth profile',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    Colors.lightBlue.shade200,
                    Colors.blue.shade700,
                    Colors.indigo.shade900,
                  ],
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: minFraction,
              child: const SizedBox(height: 10),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${depthMin.toStringAsFixed(0)}m',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    '${depthMax.toStringAsFixed(0)}m',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConditionsRow extends StatelessWidget {
  const _ConditionsRow({required this.conditions});

  final SiteConditions conditions;

  @override
  Widget build(BuildContext context) {
    final visibility = conditions.avgVisibilityM;
    final currentLabel = conditions.currentLabel();
    final logCount = conditions.logCount;

    return Row(
      children: [
        Expanded(
          child: _ConditionChip(
            icon: Icons.waves,
            label: currentLabel,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ConditionChip(
            icon: Icons.visibility_outlined,
            label: visibility != null
                ? '${visibility.toStringAsFixed(0)}m vis · $logCount logs'
                : logCount > 0
                    ? '$logCount diver logs'
                    : 'No logs yet',
          ),
        ),
      ],
    );
  }
}

class _DriftHintCard extends StatelessWidget {
  const _DriftHintCard({required this.hint, required this.live});

  final DriftPlanHint hint;
  final MarineCurrentSample live;

  @override
  Widget build(BuildContext context) {
    final color = switch (hint.level) {
      DriftRiskLevel.high => Colors.orange.shade800,
      DriftRiskLevel.moderate => Colors.blue.shade800,
      DriftRiskLevel.low => AppColors.primary,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.rotate(
            angle: directionToRadians(live.directionDeg),
            child: Icon(Icons.navigation, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hint.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
                Text(
                  '${hint.detail} Live: ${live.velocityKmh.toStringAsFixed(1)} km/h.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
