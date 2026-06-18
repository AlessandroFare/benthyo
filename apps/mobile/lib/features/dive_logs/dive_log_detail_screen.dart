import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import 'widgets/dive_profile_chart.dart';
import 'dive_logs_providers.dart';

class DiveLogDetailScreen extends ConsumerWidget {
  const DiveLogDetailScreen({super.key, required this.logId});

  final String logId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(diveLogProvider(logId));
    final dateFormat = DateFormat.yMMMMd();

    return AppScaffold(
      title: 'Dive Log',
      body: AsyncValueWidget(
        value: logAsync,
        data: (log) {
          if (log == null) {
            return const Center(child: Text('Dive log not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                dateFormat.format(log.diveDate),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (log.diveNumber != null)
                Text(
                  'Dive #${log.diveNumber}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: AppSpacing.lg),
              _DetailTile('Max depth', '${log.maxDepthM} m'),
              if (log.avgDepthM != null)
                _DetailTile('Avg depth', '${log.avgDepthM} m'),
              _DetailTile('Duration', '${log.durationMin} min'),
              _DetailTile('Gas mix', log.gasMix.dbValue),
              if (log.visibilityM != null)
                _DetailTile('Visibility', '${log.visibilityM} m'),
              if (log.currentStrength != null)
                _DetailTile('Current', log.currentStrength!.dbValue),
              if (log.waterTempSurfaceC != null)
                _DetailTile('Surface temp', '${log.waterTempSurfaceC} °C'),
              if (log.waterTempBottomC != null)
                _DetailTile('Bottom temp', '${log.waterTempBottomC} °C'),
              if (log.tankStartBar != null)
                _DetailTile('Start pressure', '${log.tankStartBar} bar'),
              if (log.tankEndBar != null)
                _DetailTile('End pressure', '${log.tankEndBar} bar'),
              if (log.buddyName != null) _DetailTile('Buddy', log.buddyName!),
              if (log.rating != null) _DetailTile('Rating', '${log.rating}/5'),
              if (log.syncedAt == null)
                const ListTile(
                  leading: Icon(Icons.cloud_off, color: AppColors.error),
                  title: Text('Saved on device — will sync when online'),
                  subtitle: Text('Pending sync'),
                ),
              if (log.profileSamples.length >= 2)
                DiveProfileChart(
                  samples: log.profileSamples
                      .map(DiveProfileSample.fromJson)
                      .toList(),
                ),
              if (log.notes != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(log.notes!),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
