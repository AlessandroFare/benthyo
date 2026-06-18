import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../dive_logs_providers.dart';
import '../surface_interval.dart';

class SurfaceIntervalBanner extends ConsumerStatefulWidget {
  const SurfaceIntervalBanner({super.key});

  @override
  ConsumerState<SurfaceIntervalBanner> createState() =>
      _SurfaceIntervalBannerState();
}

class _SurfaceIntervalBannerState extends ConsumerState<SurfaceIntervalBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(diveLogsProvider);
    return logsAsync.when(
      data: (logs) {
        final status = SurfaceIntervalStatus.fromLogs(logs);
        if (status == null) return const SizedBox.shrink();
        if (status.canFlyNow && status.canDiveNow) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          color: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Surface interval',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (!status.canDiveNow)
                  Text(
                    'Next dive OK in ${formatDuration(status.untilNextDive)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                if (!status.canFlyNow)
                  Text(
                    'No-fly until ${status.noFlyAt.hour.toString().padLeft(2, '0')}:${status.noFlyAt.minute.toString().padLeft(2, '0')} '
                    '(${formatDuration(status.untilNoFly)} left)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                if (status.multiDiveDay)
                  Text(
                    'Multiple dives today — using conservative timers.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
