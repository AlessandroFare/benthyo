import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import 'dive_logs_providers.dart';

/// Minimal dive log flow — depth, duration, optional site (Apple Watch style).
class QuickLogScreen extends ConsumerStatefulWidget {
  const QuickLogScreen({super.key, this.initialSiteId});

  final String? initialSiteId;

  @override
  ConsumerState<QuickLogScreen> createState() => _QuickLogScreenState();
}

class _QuickLogScreenState extends ConsumerState<QuickLogScreen> {
  int _depthM = 18;
  int _durationMin = 45;
  bool _loading = false;
  DateTime _diveDate = dateOnly(DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _diveDate,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _diveDate = dateOnly(picked));
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final user = ref.read(supabaseClientProvider).auth.currentUser;
      if (user == null) return;

      await ref.read(diveLogsRepositoryProvider).create(
            userId: user.id,
            input: DiveLogCreateInput(
              diveDate: _diveDate,
              diveSiteId: widget.initialSiteId,
              maxDepthM: _depthM.toDouble(),
              avgDepthM: (_depthM * 0.65).roundToDouble(),
              durationMin: _durationMin,
            ),
            isOnline: true,
          );
      ref.invalidate(diveLogsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quick dive logged')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Quick log',
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Log a dive in seconds',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dive date'),
              subtitle: Text(DateFormat.yMMMd().format(_diveDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Max depth: $_depthM m'),
            Slider(
              value: _depthM.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              label: '$_depthM m',
              onChanged: (v) => setState(() => _depthM = v.round()),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Duration: $_durationMin min'),
            Slider(
              value: _durationMin.toDouble(),
              min: 10,
              max: 120,
              divisions: 22,
              label: '$_durationMin min',
              onChanged: (v) => setState(() => _durationMin = v.round()),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save dive'),
            ),
          ],
        ),
      ),
    );
  }
}
