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
import 'marker_cluster_layer.dart' show siteTypeStyle;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conditionsAsync = ref.watch(siteConditionsProvider(site.id));
    final liveCurrentAsync = ref.watch(siteLiveCurrentProvider(site.location));
    final typeStyle = siteTypeStyle(site.siteType);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1825),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Nearby sites count
              Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$siteCount site${siteCount == 1 ? '' : 's'} in this area',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.50),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Hero gradient card ─────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 152,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        typeStyle.color.withValues(alpha: 0.80),
                        AppColors.primary.withValues(alpha: 0.95),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Large translucent type icon in the background
                      Positioned(
                        right: -12,
                        top: -12,
                        child: Icon(
                          typeStyle.icon,
                          size: 100,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      // Content
                      Positioned(
                        left: AppSpacing.lg,
                        bottom: AppSpacing.lg,
                        right: AppSpacing.lg,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Difficulty tag + type pill
                            Row(
                              children: [
                                OceanTag(
                                  label: site.difficulty.dbValue,
                                  color: Colors.white.withValues(alpha: 0.18),
                                  textColor: Colors.white,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                _TypePill(
                                  icon: typeStyle.icon,
                                  label: site.siteType.dbValue,
                                ),
                                if (site.verified == true) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  _VerifiedBadge(),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              site.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${site.region ?? site.countryCode} · ${site.depthMax.toStringAsFixed(0)} m max depth',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.72),
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

              // ── Depth profile ──────────────────────────────────────────
              _DepthProfileBar(
                depthMin: site.depthMin,
                depthMax: site.depthMax,
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Conditions chips ───────────────────────────────────────
              AsyncValueWidget(
                value: conditionsAsync,
                data: (conditions) => _ConditionsRow(conditions: conditions),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Live current / drift hint ──────────────────────────────
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

              // ── Action buttons ─────────────────────────────────────────
              Row(
                children: [
                  // Close
                  _SheetButton(
                    label: 'Close',
                    onTap: onClose,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Quick log
                  _SheetButton(
                    label: 'Log a dive',
                    icon: Icons.add,
                    filled: false,
                    accent: true,
                    onTap: () {
                      onClose();
                      context.push('/dive-logs/create?siteId=${site.id}');
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // View site (primary)
                  Expanded(
                    flex: 2,
                    child: _SheetButton(
                      label: 'View site',
                      filled: true,
                      onTap: () {
                        onClose();
                        context.push('/dive-sites/${site.id}');
                      },
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

// ── Inline widgets ──────────────────────────────────────────────────────────────

class _TypePill extends StatelessWidget {
  const _TypePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2ECC71).withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF2ECC71).withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 11, color: Color(0xFF2ECC71)),
          SizedBox(width: 3),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2ECC71),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool filled;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? AppColors.accent.withValues(alpha: 0.0) // handled below
        : accent
            ? AppColors.accent.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.07);

    final border = accent
        ? AppColors.accent.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.12);

    final textColor = accent
        ? AppColors.accent
        : filled
            ? Colors.black
            : Colors.white.withValues(alpha: 0.80);

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );

    if (filled) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: content,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 0.8),
        ),
        child: content,
      ),
    );
  }
}

// ── Depth profile bar ───────────────────────────────────────────────────────────

class _DepthProfileBar extends StatelessWidget {
  const _DepthProfileBar({
    required this.depthMin,
    required this.depthMax,
  });

  final double depthMin;
  final double depthMax;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Depth profile',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 9,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF7DD3FC), // sky-300
                    Color(0xFF1D4ED8), // blue-700
                    Color(0xFF1E1B4B), // indigo-950
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${depthMin.toStringAsFixed(0)} m',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${depthMax.toStringAsFixed(0)} m',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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

// ── Conditions row ──────────────────────────────────────────────────────────────

class _ConditionsRow extends StatelessWidget {
  const _ConditionsRow({required this.conditions});
  final SiteConditions conditions;

  @override
  Widget build(BuildContext context) {
    final visibility = conditions.avgVisibilityM;
    final currentLabel = conditions.currentLabel();
    final logCount = conditions.logCount;

    // Color-code current strength
    final currentColor = switch (currentLabel.toLowerCase()) {
      String s when s.contains('strong') => const Color(0xFFE74C3C),
      String s when s.contains('moderate') => const Color(0xFFF39C12),
      _ => const Color(0xFF2ECC71),
    };

    final visColor = visibility != null && visibility > 15
        ? const Color(0xFF2ECC71)
        : visibility != null && visibility > 8
            ? const Color(0xFF3498DB)
            : const Color(0xFF95A5A6);

    return Row(
      children: [
        Expanded(
          child: _ConditionChip(
            icon: Icons.waves,
            label: currentLabel,
            iconColor: currentColor,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ConditionChip(
            icon: Icons.visibility_outlined,
            label: visibility != null
                ? '${visibility.toStringAsFixed(0)} m vis'
                : logCount > 0
                    ? '$logCount diver logs'
                    : 'No logs yet',
            iconColor: visColor,
          ),
        ),
      ],
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drift hint card ─────────────────────────────────────────────────────────────

class _DriftHintCard extends StatelessWidget {
  const _DriftHintCard({required this.hint, required this.live});
  final DriftPlanHint hint;
  final MarineCurrentSample live;

  @override
  Widget build(BuildContext context) {
    final color = switch (hint.level) {
      DriftRiskLevel.high     => const Color(0xFFF97316),
      DriftRiskLevel.moderate => const Color(0xFF3B82F6),
      DriftRiskLevel.low      => const Color(0xFF2ECC71),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.rotate(
            angle: directionToRadians(live.directionDeg),
            child: Icon(Icons.navigation, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hint.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  '${hint.detail} Live: ${live.velocityKmh.toStringAsFixed(1)} km/h.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
