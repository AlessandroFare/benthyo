import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/main_navigation.dart';
import '../../core/widgets/ocean_card.dart';
import '../../core/widgets/shimmer_skeleton.dart';
import '../../core/widgets/staggered_list_animation.dart';
import 'dive_logs_providers.dart';
import 'widgets/surface_interval_banner.dart';
import '../discovery/widgets/conservation_alerts_section.dart';

class DiveLogListScreen extends ConsumerWidget {
  const DiveLogListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(diveLogsProvider);
    final dateFormat = DateFormat.yMMMd();

    return AppScaffold(
      title: 'My Dives',
      showBack: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.flash_on_outlined),
          tooltip: 'Quick log',
          onPressed: () => context.push('/dive-logs/quick'),
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: 'Import UDDF',
          onPressed: () => context.push('/dive-logs/import'),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/dive-logs/create'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const SurfaceIntervalBanner(),
          const ConservationAlertsSection(),
          Expanded(
            child: AsyncValueWidget(
              value: logsAsync,
              loading: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: 6,
                itemBuilder: (_, __) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ShimmerSkeleton(
                    child: Container(
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                  ),
                ),
              ),
              isEmpty: (logs) => logs.isEmpty,
              empty: EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No dives logged yet',
                subtitle:
                    'Start tracking your underwater adventures.\nEvery dive tells a story.',
                cta: 'Log your first dive',
                onCta: () => context.push('/dive-logs/create'),
              ),
              data: (logs) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(diveLogsProvider),
                color: AppColors.accent,
                child: StaggeredListAnimation(
                  children: logs.asMap().entries.map((entry) {
                    final log = entry.value;
                    return _DiveLogCard(
                      key: ValueKey(log.id),
                      date: dateFormat.format(log.diveDate),
                      depth: log.maxDepthM,
                      duration: log.durationMin,
                      gasMix: log.gasMix.dbValue,
                      rating: log.rating,
                      synced: log.syncedAt != null,
                      onTap: () => context.push('/dive-logs/${log.id}'),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const MainNavigationBar(currentIndex: 2),
        ],
      ),
    );
  }
}

class _DiveLogCard extends StatelessWidget {
  const _DiveLogCard({
    super.key,
    required this.date,
    required this.depth,
    required this.duration,
    required this.gasMix,
    required this.synced,
    this.rating,
    this.onTap,
  });

  final String date;
  final double depth;
  final int duration;
  final String gasMix;
  final int? rating;
  final bool synced;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final depthColor = AppColors.depthColor(depth);

    return OceanCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Depth badge
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  depthColor.withValues(alpha: 0.25),
                  depthColor.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: depthColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${depth.toInt()}',
                  style: TextStyle(
                    color: depthColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1,
                  ),
                ),
                Text(
                  'm',
                  style: TextStyle(
                    color: depthColor.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MetaChip(
                      icon: Icons.timer_outlined,
                      label: '${duration}min',
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _MetaChip(icon: Icons.bubble_chart_outlined, label: gasMix),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Trailing: sync state or rating
          if (!synced)
            _SyncPendingBadge()
          else if (rating != null)
            _StarRating(rating: rating!)
          else
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: scheme.primary),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncPendingBadge extends StatefulWidget {
  @override
  State<_SyncPendingBadge> createState() => _SyncPendingBadgeState();
}

class _SyncPendingBadgeState extends State<_SyncPendingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_outlined, size: 12, color: AppColors.warning),
            const SizedBox(width: 4),
            Text(
              'Pending',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating});
  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        rating.clamp(1, 5),
        (_) => const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
      ),
    );
  }
}
