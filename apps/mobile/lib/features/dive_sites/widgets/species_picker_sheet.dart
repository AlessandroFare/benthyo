import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/species.dart';
import '../../../core/theme/app_theme.dart';
import '../../species/species_providers.dart';

class SpeciesPickerSheet extends ConsumerStatefulWidget {
  const SpeciesPickerSheet({super.key});

  static Future<Species?> pick(BuildContext context) {
    return showModalBottomSheet<Species>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const SpeciesPickerSheet(),
    );
  }

  @override
  ConsumerState<SpeciesPickerSheet> createState() => _SpeciesPickerSheetState();
}

class _SpeciesPickerSheetState extends ConsumerState<SpeciesPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final speciesAsync = _query.isEmpty
        ? ref.watch(speciesListProvider)
        : ref.watch(speciesSearchProvider(_query));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
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
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Species heatmap',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search species...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: speciesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
                data: (species) => ListView.builder(
                  shrinkWrap: true,
                  itemCount: species.length.clamp(0, 30),
                  itemBuilder: (context, index) {
                    final s = species[index];
                    return ListTile(
                      title: Text(s.displayName()),
                      subtitle: Text(s.scientificName),
                      onTap: () => Navigator.pop(context, s),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
