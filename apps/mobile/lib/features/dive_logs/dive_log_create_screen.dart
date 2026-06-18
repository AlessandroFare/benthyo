import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/dive_site.dart';
import '../../core/models/enums.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/wheel_picker_sheet.dart';
import '../dive_sites/dive_sites_providers.dart';
import 'dive_logs_providers.dart';

class DiveLogCreateScreen extends ConsumerStatefulWidget {
  const DiveLogCreateScreen({super.key, this.initialSiteId});

  final String? initialSiteId;

  @override
  ConsumerState<DiveLogCreateScreen> createState() =>
      _DiveLogCreateScreenState();
}

class _DiveLogCreateScreenState extends ConsumerState<DiveLogCreateScreen> {
  late DateTime _diveDate = dateOnly(DateTime.now());
  String? _siteId;
  String? _siteName;
  GasMix _gasMix = GasMix.air;
  CurrentStrength? _current;
  int _maxDepthM = 18;
  int _durationMin = 45;
  int _visibilityM = 15;
  int _feelLevel = 3;
  final _buddyController = TextEditingController();
  final _notesController = TextEditingController();
  int? _rating;
  bool _loading = false;
  Map<String, String> _errors = {};

  static const _depthValues = [
    6,
    10,
    12,
    15,
    18,
    21,
    24,
    27,
    30,
    35,
    40,
    45,
    50,
    60,
  ];
  static const _durationValues = [
    20,
    30,
    35,
    40,
    45,
    50,
    55,
    60,
    70,
    80,
    90,
    100,
    110,
    120,
  ];
  static const _feelLabels = [
    'Very easy',
    'Easy',
    'Comfortable',
    'Moderate',
    'Challenging',
    'Hard',
  ];

  @override
  void initState() {
    super.initState();
    _siteId = widget.initialSiteId;
  }

  @override
  void dispose() {
    _buddyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _diveDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _diveDate = dateOnly(picked));
  }

  Future<void> _pickSite(List<DiveSite> sites) async {
    final selected = await showOptionSheet<String?>(
      context: context,
      title: 'Dive site',
      options: [null, ...sites.map((s) => s.id)],
      selected: _siteId,
      labelBuilder: (id) {
        if (id == null) return 'No site selected';
        return sites.firstWhere((s) => s.id == id).name;
      },
    );
    if (selected == null && _siteId != null) {
      setState(() {
        _siteId = null;
        _siteName = null;
      });
      return;
    }
    if (selected != null) {
      final site = sites.firstWhere((s) => s.id == selected);
      setState(() {
        _siteId = selected;
        _siteName = site.name;
      });
    }
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final validation = validateDiveLogInput(
      diveDate: _diveDate,
      maxDepthM: _maxDepthM.toDouble(),
      durationMin: _durationMin,
      avgDepthM: (_maxDepthM * 0.7).roundToDouble(),
      rating: _rating,
    );

    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      return;
    }

    setState(() {
      _loading = true;
      _errors = {};
    });

    try {
      await ref.read(diveLogsRepositoryProvider).create(
            userId: user.id,
            input: DiveLogCreateInput(
              diveDate: _diveDate,
              diveSiteId: _siteId,
              maxDepthM: _maxDepthM.toDouble(),
              avgDepthM: (_maxDepthM * 0.7).roundToDouble(),
              durationMin: _durationMin,
              visibilityM: _visibilityM.toDouble(),
              currentStrength: _current,
              gasMix: _gasMix,
              buddyName: _buddyController.text.trim().isEmpty
                  ? null
                  : _buddyController.text.trim(),
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              rating: _rating,
            ),
            isOnline: await ref.read(isOnlineProvider.future),
          );
      ref.invalidate(diveLogsProvider);
      if (!mounted) return;
      context.go('/dive-logs');
    } catch (e) {
      setState(() => _errors = {'general': e.toString()});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(diveSitesProvider);

    return AppScaffold(
      title: 'Add Dive',
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormGroup(
                    children: [
                      _FormRow(
                        label: 'Activity date',
                        value:
                            '${_diveDate.year}-${_diveDate.month.toString().padLeft(2, '0')}-${_diveDate.day.toString().padLeft(2, '0')}',
                        onTap: _pickDate,
                      ),
                      AsyncValueWidget(
                        value: sitesAsync,
                        data: (sites) => _FormRow(
                          label: 'Dive site',
                          value: _siteName ?? 'Optional',
                          onTap: () => _pickSite(sites),
                        ),
                      ),
                      _FormRow(
                        label: 'Max depth',
                        value: '$_maxDepthM m',
                        onTap: () async {
                          final picked = await showWheelPickerSheet<int>(
                            context: context,
                            title: 'Max depth',
                            unit: 'Meters',
                            values: _depthValues,
                            initialValue: _maxDepthM,
                            labelBuilder: (v) => '$v',
                          );
                          if (picked != null) {
                            setState(() => _maxDepthM = picked);
                          }
                        },
                      ),
                      _FormRow(
                        label: 'Duration',
                        value: '$_durationMin min',
                        onTap: () async {
                          final picked = await showWheelPickerSheet<int>(
                            context: context,
                            title: 'Duration',
                            unit: 'Minutes',
                            values: _durationValues,
                            initialValue: _durationMin,
                            labelBuilder: (v) => '$v',
                          );
                          if (picked != null) {
                            setState(() => _durationMin = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FormGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How did it feel?',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _feelLabels[_feelLevel - 1],
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 8,
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: Colors.white12,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                min: 1,
                                max: 6,
                                divisions: 5,
                                value: _feelLevel.toDouble(),
                                onChanged: (v) =>
                                    setState(() => _feelLevel = v.round()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FormGroup(
                    children: [
                      _FormRow(
                        label: 'Visibility',
                        value: '$_visibilityM m',
                        onTap: () async {
                          final picked = await showWheelPickerSheet<int>(
                            context: context,
                            title: 'Visibility',
                            unit: 'Meters',
                            values: const [3, 5, 8, 10, 12, 15, 20, 25, 30, 40],
                            initialValue: _visibilityM,
                            labelBuilder: (v) => '$v',
                          );
                          if (picked != null) {
                            setState(() => _visibilityM = picked);
                          }
                        },
                      ),
                      _FormRow(
                        label: 'Gas mix',
                        value: _gasMix.dbValue,
                        onTap: () async {
                          final picked = await showOptionSheet<GasMix>(
                            context: context,
                            title: 'Gas mix',
                            options: GasMix.values,
                            selected: _gasMix,
                            labelBuilder: (g) => g.dbValue,
                          );
                          if (picked != null) setState(() => _gasMix = picked);
                        },
                      ),
                      _FormRow(
                        label: 'Current',
                        value: _current?.dbValue ?? 'Unknown',
                        onTap: () async {
                          final picked =
                              await showOptionSheet<CurrentStrength?>(
                            context: context,
                            title: 'Current',
                            options: [null, ...CurrentStrength.values],
                            selected: _current,
                            labelBuilder: (c) => c?.dbValue ?? 'Unknown',
                          );
                          if (picked != null) setState(() => _current = picked);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: TextField(
                          controller: _buddyController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Buddy (optional)',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Rating',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  Row(
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      return IconButton(
                        icon: Icon(
                          _rating != null && star <= _rating!
                              ? Icons.star
                              : Icons.star_border,
                          color: AppColors.accent,
                        ),
                        onPressed: () => setState(() => _rating = star),
                      );
                    }),
                  ),
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                  if (_errors['general'] != null || _errors['dive_date'] != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _errors['general'] ?? _errors['dive_date']!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add dive log'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormGroup extends StatelessWidget {
  const _FormGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(children: children),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
