import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/main_navigation.dart';
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
      title: 'Dive Logs',
      showBack: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.flash_on),
          tooltip: 'Quick log',
          onPressed: () => context.push('/dive-logs/quick'),
        ),
        IconButton(
          icon: const Icon(Icons.upload_file),
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
              isEmpty: (logs) => logs.isEmpty,
              empty: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.book_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text('No dive logs yet'),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => context.push('/dive-logs/create'),
                      child: const Text('Log your first dive'),
                    ),
                  ],
                ),
              ),
              data: (logs) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(diveLogsProvider),
                child: ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return ListTile(
                      minVerticalPadding: AppSpacing.sm,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: Text('${log.maxDepthM.toInt()}m'),
                      ),
                      title: Text(dateFormat.format(log.diveDate)),
                      subtitle: Text(
                        '${log.durationMin} min · ${log.gasMix.dbValue}',
                      ),
                      trailing: log.syncedAt == null
                          ? const Chip(
                              label: Text('Pending sync'),
                              visualDensity: VisualDensity.compact,
                            )
                          : log.rating != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    log.rating!,
                                    (_) => const Icon(
                                      Icons.star,
                                      size: 16,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                )
                              : null,
                      onTap: () => context.push('/dive-logs/${log.id}'),
                    );
                  },
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
