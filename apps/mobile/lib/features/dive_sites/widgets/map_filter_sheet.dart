import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dive_site_filters.dart';
import '../../../core/models/enums.dart';
import '../dive_sites_providers.dart';

/// Bottom sheet for editing the active [DiveSiteFilters] on the map
/// screen. Designed to feel "Komoot-meets-iOS": grouped sections, sticky
/// "Apply" button, count-of-active-filters chip, haptic feedback on
/// clear-all.
///
/// The sheet animates in from the bottom with a curved top edge. The
/// height is bounded to 80% of the screen so the user can still see
/// the map behind the scrim.
class MapFilterSheet extends ConsumerStatefulWidget {
  const MapFilterSheet({super.key});

  /// Opens the sheet. Use from a button on the map screen.
  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      // Subtle spring-like feel.
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 320),
        reverseDuration: const Duration(milliseconds: 220),
      ),
      builder: (ctx) => const MapFilterSheet(),
    );
  }

  @override
  ConsumerState<MapFilterSheet> createState() => _MapFilterSheetState();
}

class _MapFilterSheetState extends ConsumerState<MapFilterSheet> {
  late DiveSiteFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(diveSiteFiltersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        return Material(
          color: theme.colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Text(
                      'Filters',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_draft.activeCount > 0)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _draft = DiveSiteFilters.empty;
                          });
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('Clear (${_draft.activeCount})'),
                      ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _SearchField(
                      initial: _draft.query,
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(query: v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Country',
                      child: _CountryChips(
                        selected: _draft.countryCode,
                        onSelect: (c) => setState(() {
                          _draft = c == null
                              ? _draft.copyWith(clearCountry: true)
                              : _draft.copyWith(countryCode: c);
                        }),
                      ),
                    ),
                    _Section(
                      title: 'Difficulty',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in SiteDifficulty.values)
                            _ChoiceChip(
                              label: _difficultyLabel(d),
                              selected: _draft.difficulty == d,
                              onTap: () => setState(() {
                                _draft = _draft.difficulty == d
                                    ? _draft.copyWith(clearDifficulty: true)
                                    : _draft.copyWith(difficulty: d);
                              }),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Site type',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in SiteType.values)
                            _ChoiceChip(
                              label: _siteTypeLabel(t),
                              selected: _draft.siteType == t,
                              onTap: () => setState(() {
                                _draft = _draft.siteType == t
                                    ? _draft.copyWith(clearSiteType: true)
                                    : _draft.copyWith(siteType: t);
                              }),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Access',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in AccessType.values)
                            _ChoiceChip(
                              label: _accessLabel(a),
                              selected: _draft.accessType == a,
                              onTap: () => setState(() {
                                _draft = _draft.accessType == a
                                    ? _draft.copyWith(clearAccessType: true)
                                    : _draft.copyWith(accessType: a);
                              }),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Max depth (m)',
                      child: _RangeSlider(
                        min: _draft.minDepth?.toDouble() ?? 0,
                        max: _draft.maxDepth?.toDouble() ?? 60,
                        onMinChanged: (v) => setState(() {
                          _draft = v == 0
                              ? _draft.copyWith(clearMinDepth: true)
                              : _draft.copyWith(minDepth: v.round());
                        }),
                        onMaxChanged: (v) => setState(() {
                          _draft = v == 60
                              ? _draft.copyWith(clearMaxDepth: true)
                              : _draft.copyWith(maxDepth: v.round());
                        }),
                      ),
                    ),
                    _Section(
                      title: 'Sort by',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in DiveSiteSort.values)
                            _ChoiceChip(
                              label: s.label,
                              selected: _draft.sortBy == s,
                              onTap: () => setState(() {
                                _draft = _draft.copyWith(sortBy: s);
                              }),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Verified sites only'),
                      subtitle: const Text(
                        'Hide sites that have not been verified by an editor',
                      ),
                      value: _draft.verifiedOnly,
                      onChanged: (v) => setState(() {
                        _draft = _draft.copyWith(verifiedOnly: v);
                      }),
                    ),
                    const SizedBox(height: 96),
                  ],
                ),
              ),
              _ApplyBar(
                count: _draft.activeCount,
                onApply: () {
                  ref.read(diveSiteFiltersProvider.notifier).state = _draft;
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryChips extends ConsumerWidget {
  const _CountryChips({required this.selected, required this.onSelect});
  final String? selected;
  final ValueChanged<String?> onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(availableCountriesProvider);
    return countries.when(
      data: (list) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final c = list[i];
            return _ChoiceChip(
              label: '${c.code} · ${c.name}',
              selected: selected == c.code,
              onTap: () => onSelect(selected == c.code ? null : c.code),
            );
          },
        ),
      ),
      loading: () => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Text(
        'Could not load countries',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Search by name or region…',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _c.clear();
                  widget.onChanged('');
                },
                icon: const Icon(Icons.clear, size: 18),
              ),
      ),
    );
  }
}

class _RangeSlider extends StatelessWidget {
  const _RangeSlider({
    required this.min,
    required this.max,
    required this.onMinChanged,
    required this.onMaxChanged,
  });
  final double min;
  final double max;
  final ValueChanged<double> onMinChanged;
  final ValueChanged<double> onMaxChanged;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RangeSlider(
          min: 0,
          max: 60,
          divisions: 60,
          values: RangeValues(min, max),
          labels: RangeLabels('${min.round()}m', '${max.round()}m'),
          onChanged: (v) {
            onMinChanged(v.start);
            onMaxChanged(v.end);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${min.round()} m'),
              Text('${max.round()} m'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({required this.count, required this.onApply});
  final int count;
  final VoidCallback onApply;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onApply,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              count == 0
                  ? 'Show all sites'
                  : 'Apply $count filter${count == 1 ? '' : 's'}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _difficultyLabel(SiteDifficulty d) {
  switch (d) {
    case SiteDifficulty.beginner:
      return 'Beginner';
    case SiteDifficulty.intermediate:
      return 'Intermediate';
    case SiteDifficulty.advanced:
      return 'Advanced';
    case SiteDifficulty.technical:
      return 'Technical';
  }
}

String _siteTypeLabel(SiteType t) {
  switch (t) {
    case SiteType.reef:
      return 'Reef';
    case SiteType.wall:
      return 'Wall';
    case SiteType.wreck:
      return 'Wreck';
    case SiteType.cave:
      return 'Cave';
    case SiteType.pinnacle:
      return 'Pinnacle';
    case SiteType.muck:
      return 'Muck';
    case SiteType.other:
      return 'Other';
  }
}

String _accessLabel(AccessType a) {
  switch (a) {
    case AccessType.shore:
      return 'Shore';
    case AccessType.boat:
      return 'Boat';
    case AccessType.liveaboard:
      return 'Liveaboard';
  }
}
