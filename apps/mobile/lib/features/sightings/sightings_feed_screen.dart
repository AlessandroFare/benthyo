import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animated_fab.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/main_navigation.dart';
import '../../core/widgets/staggered_list_animation.dart';
import '../dive_sites/widgets/species_picker_sheet.dart';
import 'sightings_providers.dart';
import 'suggest_correction_sheet.dart';

/// Polished sightings feed: staggered card list, hero photo, animated
/// confidence chip, animated FAB.
class SightingsFeedScreen extends ConsumerWidget {
  const SightingsFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(sightingsFeedProvider);
    final currentUser = ref.watch(currentUserProvider);
    final dateFormat = DateFormat.yMMMd().add_jm();

    return AppScaffold(
      title: 'Sightings',
      showBack: false,
      floatingActionButton: AnimatedFab(
        tooltip: 'Report a sighting',
        onPressed: () => context.push('/sightings/add'),
        icon: const Icon(Icons.add_a_photo_outlined),
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncValueWidget(
              value: feedAsync,
              isEmpty: (items) => items.isEmpty,
              empty: _EmptyState(
                onReport: () => context.push('/sightings/add'),
              ),
              data: (items) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(sightingsFeedProvider),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xl * 2, // leave space for the FAB
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final s = items[index];
                    return _AnimatedSightingCard(
                      index: index,
                      onTap: () => context.push('/sightings/${s.id}'),
                      onLongPress: currentUser != null && s.userId != currentUser.id
                          ? () async {
                              final species = await SpeciesPickerSheet.pick(context);
                              if (species != null && context.mounted) {
                                await showSuggestCorrectionSheet(
                                  context,
                                  ref,
                                  sightingId: s.id,
                                  proposedSpeciesId: species.id,
                                );
                              }
                            }
                          : null,
                      child: s.isRemoved
                          ? const _RemovedSightingCard()
                          : _SightingCardContent(
                              imageUrl: s.speciesImageUrl,
                              title: s.speciesName ?? s.speciesScientificName ?? 'Unknown',
                              subtitle:
                                  '${s.siteName ?? 'Unknown site'}  •  ${dateFormat.format(s.observedAt)}',
                              confidence: s.confidenceLevel,
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
          const MainNavigationBar(currentIndex: 1),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onReport});
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.18),
                    scheme.primary.withValues(alpha: 0.02),
                  ],
                ),
              ),
              child: Icon(
                Icons.visibility_off,
                size: 48,
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'No sightings yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Log your first underwater observation\nto start your life list.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onReport,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Report first sighting'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedSightingCard extends StatefulWidget {
  const _AnimatedSightingCard({
    required this.index,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final int index;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_AnimatedSightingCard> createState() => _AnimatedSightingCardState();
}

class _AnimatedSightingCardState extends State<_AnimatedSightingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    final delay = Duration(milliseconds: (widget.index.clamp(0, 12)) * 55);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(_opacity);
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(_opacity);
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: ScaleTransition(
          scale: _scale,
          child: _HoverCard(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, this.onTap, this.onLongPress});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

class _SightingCardContent extends StatelessWidget {
  const _SightingCardContent({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.confidence,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final ConfidenceLevel confidence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (chipColor, chipLabel) = switch (confidence) {
      ConfidenceLevel.certain => (AppColors.success, 'Certain'),
      ConfidenceLevel.likely => (scheme.primary, 'Likely'),
      ConfidenceLevel.uncertain => (Colors.amber, 'Uncertain'),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      color: AppColors.surfaceDark,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Hero(
              tag: 'sighting-photo-$title',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.white.withValues(alpha: 0.06),
                            child: const Icon(Icons.pets, color: Colors.white54),
                          ),
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.06),
                          child: const Icon(Icons.pets, color: Colors.white54),
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AnimatedConfidenceChip(color: chipColor, label: chipLabel),
          ],
        ),
      ),
    );
  }
}

class AnimatedConfidenceChip extends StatefulWidget {
  const AnimatedConfidenceChip({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  State<AnimatedConfidenceChip> createState() => _AnimatedConfidenceChipState();
}

class _AnimatedConfidenceChipState extends State<AnimatedConfidenceChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: widget.color.withValues(alpha: 0.45)),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.color,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

/// "Removed" placeholder card for sightings that were soft-deleted on
/// the server. Renders gracefully without crashing on null related rows.
class _RemovedSightingCard extends StatelessWidget {
  const _RemovedSightingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      color: AppColors.surfaceDark,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.remove_circle_outline,
                  color: Colors.white38),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Sighting removed',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'This record is no longer available.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
