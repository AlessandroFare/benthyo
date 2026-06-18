import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_value_widget.dart';

/// Species ID + name + similarity score. The shape returned by
/// `find_similar_species` in migration 032.
class SimilarSpecies {
  SimilarSpecies({
    required this.id,
    required this.scientificName,
    required this.commonName,
    required this.similarity,
  });

  final String id;
  final String scientificName;
  final String? commonName;
  final double similarity;

  factory SimilarSpecies.fromJson(Map<String, dynamic> json) => SimilarSpecies(
        id: json['id'] as String,
        scientificName: json['scientific_name'] as String,
        commonName: json['common_name'] as String?,
        similarity: (json['similarity'] as num).toDouble(),
      );
}

/// Resolves related species for the given species id. Calls the
/// `find_similar_species_by_species_id` RPC (added in migration 032)
/// if it exists, otherwise falls back to a taxonomy-based query.
final similarSpeciesProvider =
    FutureProvider.family<List<SimilarSpecies>, String>((ref, speciesId) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final res = await client.rpc(
      'find_similar_species_by_species_id',
      params: {
        'p_species_id': speciesId,
        'p_limit': 5,
        'p_min_sim': 0.65,
      },
    );
    if (res is List && res.isNotEmpty) {
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(SimilarSpecies.fromJson)
          .toList();
    }
  } catch (_) {
    // ignore — fall through to taxonomy fallback.
  }
  // Taxonomy fallback.
  try {
    final res = await client
        .from('species')
        .select('id, scientific_name, common_name, family, genus')
        .or('family.is.not.null,genus.is.not.null')
        .neq('id', speciesId)
        .limit(5);
    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows
        .map(
          (r) => SimilarSpecies(
            id: r['id'] as String,
            scientificName: r['scientific_name'] as String,
            commonName: r['common_name'] as String?,
            similarity: 0.0,
          ),
        )
        .toList();
  } catch (_) {
    return const <SimilarSpecies>[];
  }
});

/// Horizontal carousel of "You may also see" species. Shown at the
/// bottom of the species detail screen.
class SimilarSpeciesCarousel extends ConsumerWidget {
  const SimilarSpeciesCarousel({super.key, required this.speciesId});

  final String speciesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarSpeciesProvider(speciesId));
    return AsyncValueWidget(
      value: similar,
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.travel_explore, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'You may also see',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _SimilarSpeciesCard(item: item);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SimilarSpeciesCard extends StatelessWidget {
  const _SimilarSpeciesCard({required this.item});
  final SimilarSpecies item;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/species/${item.id}'),
        child: SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 124,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.pets, size: 28),
                ),
                const SizedBox(height: 6),
                Text(
                  item.commonName ?? item.scientificName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.scientificName,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}