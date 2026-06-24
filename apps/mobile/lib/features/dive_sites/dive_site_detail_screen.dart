import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/parallax_hero_photo.dart';
import '../discovery/widgets/buddy_finder_section.dart';
import '../discovery/widgets/prep_card_section.dart';
import '../discovery/widgets/site_review_sheet.dart';
import 'dive_sites_providers.dart';

class DiveSiteDetailScreen extends ConsumerWidget {
  const DiveSiteDetailScreen({super.key, required this.siteId});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final siteAsync = ref.watch(diveSiteProvider(siteId));

    return AppScaffold(
      title: 'Dive Site',
      body: AsyncValueWidget(
        value: siteAsync,
        data: (site) {
          if (site == null) {
            return const Center(child: Text('Site not found'));
          }
          final imageUrl = site.metadata['hero_image'] as String?;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                stretch: true,
                backgroundColor: AppColors.surfaceDark,
                flexibleSpace: FlexibleSpaceBar(
                  background: ParallaxHeroPhoto(
                    imageUrl: imageUrl,
                    title: site.name,
                    subtitle: '${site.region ?? 'Unknown'}  •  ${site.countryCode}',
                    tags: [
                      Chip(label: Text(site.difficulty.dbValue)),
                      Chip(label: Text(site.siteType.dbValue)),
                      if (site.verified)
                        const Chip(
                          avatar: Icon(Icons.verified, color: AppColors.success, size: 16),
                          label: Text('Verified'),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _InfoRow(
                      icon: Icons.vertical_align_bottom,
                      label: '${site.depthMin}–${site.depthMax} m depth',
                    ),
                    _InfoRow(
                      icon: Icons.directions_boat,
                      label: site.accessType.dbValue,
                    ),
                    if (site.description != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        site.description!,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push('/dive-logs/create?siteId=$siteId'),
                      icon: const Icon(Icons.add),
                      label: const Text('Log a dive here'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/sightings/add?siteId=$siteId'),
                      icon: const Icon(Icons.visibility),
                      label: const Text('Report sighting'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => showSiteReviewSheet(context, ref, siteId),
                      icon: const Icon(Icons.rate_review),
                      label: const Text('Write a review'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrepCardSection(siteId: siteId, siteSlug: site.slug),
                    const SizedBox(height: AppSpacing.md),
                    BuddyFinderSection(siteId: siteId),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
