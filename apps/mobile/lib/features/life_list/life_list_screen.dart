import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import 'life_list_filter_sheet.dart';
import 'life_list_providers.dart';

class LifeListScreen extends ConsumerStatefulWidget {
  const LifeListScreen({super.key});

  @override
  ConsumerState<LifeListScreen> createState() => _LifeListScreenState();
}

class _LifeListScreenState extends ConsumerState<LifeListScreen> {
  final _searchController = TextEditingController();
  Set<SiteType> _filters = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showLifeListFilterSheet(
      context: context,
      selectedTypes: _filters,
    );
    if (result != null) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final lifeListAsync = ref.watch(lifeListProvider);
    final dateFormat = DateFormat.yMMMd();

    return AppScaffold(
      title: 'Life List',
      actions: [
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: _openFilters,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search your life list...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          if (_filters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: _filters
                      .map(
                        (type) => Chip(
                          label: Text(type.dbValue),
                          onDeleted: () =>
                              setState(() => _filters.remove(type)),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          Expanded(
            child: AsyncValueWidget(
              value: lifeListAsync,
              isEmpty: (entries) => entries.isEmpty,
              empty: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.list_alt,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text('Your life list is empty'),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Report sightings to build your collection',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: () => context.push('/species/identify'),
                      child: const Text('Identify species'),
                    ),
                  ],
                ),
              ),
              data: (entries) {
                final filtered = entries.where((entry) {
                  final species = entry.species;
                  if (species == null) return false;
                  if (_query.isNotEmpty) {
                    final q = _query.toLowerCase();
                    final matchesName =
                        species.displayName().toLowerCase().contains(q) ||
                            species.scientificName.toLowerCase().contains(q);
                    if (!matchesName) return false;
                  }
                  return true;
                }).toList();

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(lifeListProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final species = entry.species!;
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => context.push('/species/${species.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: species.imageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: species.imageUrl!,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 72,
                                          height: 72,
                                          color: AppColors.surfaceDark,
                                          child: const Icon(Icons.pets),
                                        ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        species.displayName(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        species.scientificName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontStyle: FontStyle.italic,
                                              color: AppColors.textSecondary,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'First seen ${dateFormat.format(entry.firstSeenAt)} · '
                                        '${entry.totalSightings} sightings',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
