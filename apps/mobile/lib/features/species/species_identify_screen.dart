import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/species.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/ocean_tag.dart';
import 'species_api_repository.dart';
import 'species_identify_providers.dart';
import 'species_providers.dart';

class SpeciesIdentifyScreen extends ConsumerStatefulWidget {
  const SpeciesIdentifyScreen({
    super.key,
    this.initialQuery = '',
    this.imagePath,
  });

  final String initialQuery;
  final String? imagePath;

  @override
  ConsumerState<SpeciesIdentifyScreen> createState() =>
      _SpeciesIdentifyScreenState();
}

class _SpeciesIdentifyScreenState extends ConsumerState<SpeciesIdentifyScreen> {
  late String _query;
  int _matchIndex = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
  }

  bool get _isPhotoMode =>
      widget.imagePath != null && widget.imagePath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isPhotoMode) {
      final photoAsync =
          ref.watch(speciesPhotoIdentifyProvider(widget.imagePath!));
      return AppScaffold(
        title: 'Photo matches',
        body: AsyncValueWidget(
          value: photoAsync,
          loading: const Center(child: CircularProgressIndicator()),
          data: (result) {
            if (result.matches.isNotEmpty) {
              return _SpeciesMatchView(
                matches: result.matches,
                heroImageUrl: result.imageUrl,
                matchIndex: _matchIndex,
                ai: result.ai,
                created: result.created,
                onMatchIndexChanged: (index) =>
                    setState(() => _matchIndex = index),
              );
            }
            if (result.inatResults.isNotEmpty) {
              return _InatMatchView(
                results: result.inatResults,
                heroImageUrl: result.imageUrl,
                matchIndex: _matchIndex,
                ai: result.ai,
                onMatchIndexChanged: (index) =>
                    setState(() => _matchIndex = index),
              );
            }
            return _EmptyPhotoResult(
              imageUrl: result.imageUrl,
              ai: result.ai,
            );
          },
        ),
      );
    }

    final matchesAsync = ref.watch(speciesSearchProvider(_query));

    return AppScaffold(
      title: 'Best Matches',
      body: AsyncValueWidget(
        value: matchesAsync,
        isEmpty: (matches) => matches.isEmpty,
        empty: const Center(child: Text('No matches found')),
        data: (matches) => _SpeciesMatchView(
          matches: matches,
          matchIndex: _matchIndex,
          onMatchIndexChanged: (index) => setState(() => _matchIndex = index),
        ),
      ),
    );
  }
}

class _SpeciesMatchView extends StatelessWidget {
  const _SpeciesMatchView({
    required this.matches,
    required this.matchIndex,
    required this.onMatchIndexChanged,
    this.heroImageUrl,
    this.ai,
    this.created = false,
  });

  final List<Species> matches;
  final int matchIndex;
  final ValueChanged<int> onMatchIndexChanged;
  final String? heroImageUrl;
  final AiVisionProposal? ai;
  final bool created;

  @override
  Widget build(BuildContext context) {
    final species = matches[matchIndex.clamp(0, matches.length - 1)];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (ai != null) ...[
                _AiBanner(ai: ai!, created: created),
                const SizedBox(height: AppSpacing.lg),
              ],
              _MatchDots(
                count: matches.length.clamp(0, 5),
                activeIndex: matchIndex,
              ),
              const SizedBox(height: AppSpacing.lg),
              _HeroPhoto(
                species: species,
                overrideImageUrl: heroImageUrl,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                species.displayName(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                species.family ?? 'Marine species',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              OceanTagRow(
                tags: [
                  if (species.family != null) OceanTag(label: species.family!),
                  OceanTag(
                    label: species.conservationStatus?.dbValue ?? 'Unknown',
                    color: Colors.blue.withValues(alpha: 0.12),
                    textColor: Colors.blue.shade700,
                  ),
                  if (species.minDepthM != null)
                    OceanTag(
                      label:
                          '${species.minDepthM!.round()}-${species.maxDepthM?.round() ?? '?'}m',
                      color: AppColors.accent.withValues(alpha: 0.12),
                      textColor: AppColors.primary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _InfoCard(
                title: 'Taxonomy',
                rows: [
                  if (species.genus != null) ('Genus', species.genus!),
                  ('Scientific name', species.scientificName),
                  if (species.commonName != null)
                    ('Common name', species.commonName!),
                ],
              ),
              if (species.description != null) ...[
                const SizedBox(height: AppSpacing.md),
                _InfoCard(
                  title: 'Description',
                  body: species.description!,
                ),
              ],
              if (matches.length > 1) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Other matches',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                ...matches.asMap().entries.map(
                      (entry) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage: entry.value.imageUrl != null
                              ? CachedNetworkImageProvider(
                                  entry.value.imageUrl!,
                                )
                              : null,
                          child: entry.value.imageUrl == null
                              ? const Icon(Icons.pets)
                              : null,
                        ),
                        title: Text(entry.value.displayName()),
                        subtitle: Text(
                          entry.value.scientificName,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                        trailing: entry.key == matchIndex
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                              )
                            : null,
                        onTap: () => onMatchIndexChanged(entry.key),
                      ),
                    ),
              ],
            ],
          ),
        ),
        _BottomActions(
          onRetake: () => context.pop(),
          onDetails: () => context.push('/species/${species.id}'),
          onAddToLifeList: () {
            final params = <String, String>{
              'speciesId': species.id,
              if (heroImageUrl != null)
                'photoUrl': Uri.encodeComponent(heroImageUrl!),
            };
            final q = params.entries.map((e) => '${e.key}=${e.value}').join('&');
            context.push('/sightings/add?$q');
          },
        ),
      ],
    );
  }
}

class _InatMatchView extends StatelessWidget {
  const _InatMatchView({
    required this.results,
    required this.matchIndex,
    required this.onMatchIndexChanged,
    this.heroImageUrl,
    this.ai,
  });

  final List<InatIdentification> results;
  final int matchIndex;
  final ValueChanged<int> onMatchIndexChanged;
  final String? heroImageUrl;
  final AiVisionProposal? ai;

  @override
  Widget build(BuildContext context) {
    final hit = results[matchIndex.clamp(0, results.length - 1)];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (ai != null) ...[
                _AiBanner(ai: ai!, created: false),
                const SizedBox(height: AppSpacing.lg),
              ],
              _MatchDots(
                count: results.length.clamp(0, 5),
                activeIndex: matchIndex,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (heroImageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: CachedNetworkImage(
                    imageUrl: heroImageUrl!,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppColors.surfaceDark,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.surfaceDark,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                hit.commonName ?? hit.scientificName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                hit.scientificName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              OceanTagRow(
                tags: [
                  const OceanTag(label: 'iNaturalist AI'),
                  OceanTag(
                    label: '${(hit.confidence * 100).round()}% confidence',
                    color: AppColors.accent.withValues(alpha: 0.12),
                    textColor: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _InfoCard(
                title: 'Not in Benthyo yet',
                body:
                    'This species is not in our catalog yet. You can still log a sighting manually or suggest it to your operator.',
              ),
            ],
          ),
        ),
        _BottomActions(
          onRetake: () => context.pop(),
          onDetails: () {},
          onAddToLifeList: () => context.push('/sightings/add'),
          detailsEnabled: false,
        ),
      ],
    );
  }
}

class _EmptyPhotoResult extends StatelessWidget {
  const _EmptyPhotoResult({this.imageUrl, this.ai});

  final String? imageUrl;
  final AiVisionProposal? ai;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: AppColors.surfaceDark,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceDark,
                  child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (ai != null) ...[
            _AiBanner(ai: ai!, created: false),
            const SizedBox(height: AppSpacing.lg),
          ] else
            const Text('No species matches for this photo'),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => context.pop(),
            child: const Text('Try another photo'),
          ),
        ],
      ),
    );
  }
}

/// Banner that surfaces the AI vision proposal above the catalog matches.
class _AiBanner extends StatelessWidget {
  const _AiBanner({required this.ai, required this.created});

  final AiVisionProposal ai;
  final bool created;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final confidencePct = (ai.confidence * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'AI identification',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                '$confidencePct%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            ai.displayName(locale: locale),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (ai.scientificName != null)
            Text(
              ai.scientificName!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          if (ai.rationale != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              ai.rationale!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (created) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(Icons.add_circle_outline,
                    size: 16, color: AppColors.success),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Added to the Benthyo catalog — details will improve soon.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchDots extends StatelessWidget {
  const _MatchDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index == activeIndex
                ? AppColors.primary
                : AppColors.textSecondary.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({
    required this.species,
    this.overrideImageUrl,
  });

  final Species species;
  final String? overrideImageUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = overrideImageUrl ?? species.imageUrl;

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppColors.surfaceDark,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceDark,
                    child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38),
                  ),
                )
              : Container(
                  height: 240,
                  color: AppColors.surfaceDark,
                  child:
                      const Icon(Icons.image, size: 64, color: Colors.white24),
                ),
        ),
        Positioned(
          bottom: -28,
          child: CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            child: CircleAvatar(
              radius: 30,
              backgroundImage: imageUrl != null
                  ? CachedNetworkImageProvider(imageUrl)
                  : null,
              child: imageUrl == null
                  ? const Icon(Icons.pets, color: AppColors.primary)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    this.rows = const [],
    this.body,
  });

  final String title;
  final List<(String, String)> rows;
  final String? body;

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
          if (body != null)
            Text(body!)
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${row.$1}:',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.onRetake,
    required this.onDetails,
    required this.onAddToLifeList,
    this.detailsEnabled = true,
  });

  final VoidCallback onRetake;
  final VoidCallback onDetails;
  final VoidCallback onAddToLifeList;
  final bool detailsEnabled;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            FloatingActionButton(
              heroTag: 'retake',
              backgroundColor: Colors.amber,
              foregroundColor: AppColors.primary,
              onPressed: onRetake,
              child: const Icon(Icons.photo_camera),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              onPressed: detailsEnabled ? onDetails : null,
              icon: const Icon(Icons.open_in_new),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: onAddToLifeList,
                child: const Text('Add to Life List'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
