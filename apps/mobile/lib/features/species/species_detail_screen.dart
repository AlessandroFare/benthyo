import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/ocean_tag.dart';
import '../discovery/widgets/seasonal_forecast_card.dart';
import 'similar_species_carousel.dart';
import 'species_providers.dart';

class SpeciesDetailScreen extends ConsumerWidget {
  const SpeciesDetailScreen({super.key, required this.speciesId});

  final String speciesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speciesAsync = ref.watch(speciesProvider(speciesId));

    return AppScaffold(
      title: 'Species',
      body: AsyncValueWidget(
        value: speciesAsync,
        data: (species) {
          if (species == null) {
            return const Center(child: Text('Species not found'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (species.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: CachedNetworkImage(
                        imageUrl: species.imageUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: AppColors.surfaceDark,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.surfaceDark,
                          child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38),
                        ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      species.displayName(),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      species.scientificName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Colors.white70,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OceanTagRow(
                      tags: [
                        if (species.family != null)
                          OceanTag(label: species.family!),
                        if (species.conservationStatus != null)
                          OceanTag(
                            label:
                                'IUCN ${species.conservationStatus!.dbValue}',
                            color: Colors.red.withValues(alpha: 0.1),
                            textColor: Colors.red.shade700,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionCard(
                      title: 'Taxonomy',
                      child: Column(
                        children: [
                          if (species.genus != null)
                            _TaxonomyRow('Genus', species.genus!),
                          _TaxonomyRow(
                            'Scientific Name',
                            species.scientificName,
                          ),
                          if (species.commonName != null)
                            _TaxonomyRow('Common Names', species.commonName!),
                        ],
                      ),
                    ),
                    if (species.imageUrl != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _SectionCard(
                        title: 'Photo Gallery',
                        child: SizedBox(
                          height: 120,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: CachedNetworkImage(
                                  imageUrl: species.imageUrl!,
                                  width: 160,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: AppColors.surfaceDark,
                                    child: const Center(child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: AppColors.surfaceDark,
                                    child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (species.description != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _SectionCard(
                        title: 'Description',
                        child: Text(species.description!),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    SeasonalForecastCard(speciesId: speciesId),
                    const SizedBox(height: AppSpacing.md),
                    SimilarSpeciesCarousel(speciesId: speciesId),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      FloatingActionButton(
                        heroTag: 'identify',
                        backgroundColor: Colors.amber,
                        foregroundColor: AppColors.primary,
                        onPressed: () => context.push(
                          '/species/identify?q=${Uri.encodeComponent(species.scientificName)}',
                        ),
                        child: const Icon(Icons.photo_camera),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,   // <-- aggiunto
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          onPressed: () => context.push('/sightings/add?speciesId=$speciesId'),
                          child: const Text('Add to Life List'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Forza un tema "chiaro" locale per tutto il contenuto della card,
          // così i Text senza colore esplicito (qui e in eventuali child
          // futuri) non ereditano più il bianco del tema dark ambiente.
          DefaultTextStyle.merge(
            style: const TextStyle(color: AppColors.oceanDeep),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _TaxonomyRow extends StatelessWidget {
  const _TaxonomyRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.oceanDeep,   // <-- aggiunto, esplicito e scuro
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
