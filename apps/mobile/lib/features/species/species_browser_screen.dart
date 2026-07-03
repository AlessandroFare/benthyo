import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/main_navigation.dart';
import '../../core/widgets/ocean_card.dart';
import '../../core/widgets/shimmer_skeleton.dart';
import '../../core/widgets/staggered_list_animation.dart';
import 'species_providers.dart';

class SpeciesBrowserScreen extends ConsumerStatefulWidget {
  const SpeciesBrowserScreen({super.key});

  @override
  ConsumerState<SpeciesBrowserScreen> createState() =>
      _SpeciesBrowserScreenState();
}

class _SpeciesBrowserScreenState extends ConsumerState<SpeciesBrowserScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openIdentify() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      context.push('/species/identify?q=${Uri.encodeComponent(query)}');
    } else {
      context.push('/species/identify');
    }
  }

  Future<void> _identifyFromPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    unawaited(
      context.push(
        '/species/identify?path=${Uri.encodeComponent(file.path)}',
      ),
    );
  }

  Future<void> _identifyFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    unawaited(
      context.push(
        '/species/identify?path=${Uri.encodeComponent(file.path)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speciesAsync = _query.isEmpty
        ? ref.watch(speciesListProvider)
        : ref.watch(speciesSearchProvider(_query));

    return AppScaffold(
      title: 'Species',
      showBack: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.photo_camera_outlined),
          tooltip: 'Identify from camera',
          onPressed: _identifyFromPhoto,
        ),
        IconButton(
          icon: const Icon(Icons.photo_library_outlined),
          tooltip: 'Identify from gallery',
          onPressed: _identifyFromGallery,
        ),
      ],
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search or identify species...',
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
              onSubmitted: (_) => _openIdentify(),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: AsyncValueWidget(
              value: speciesAsync,
              loading: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: 8,
                itemBuilder: (_, __) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ShimmerSkeleton(
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                  ),
                ),
              ),
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: Icons.travel_explore_outlined,
                title: _query.isNotEmpty
                    ? 'No species match "$_query"'
                    : 'No species yet',
                subtitle: 'Try identifying from a photo with the AI engine.',
                cta: 'Identify from photo',
                onCta: _identifyFromPhoto,
              ),
              data: (species) => StaggeredListAnimation(
                children: species.map((s) {
                  return _SpeciesCard(
                    key: ValueKey(s.id),
                    displayName: s.displayName(),
                    scientificName: s.scientificName,
                    imageUrl: s.imageUrl,
                    onTap: () => context.push('/species/${s.id}'),
                  );
                }).toList(),
              ),
            ),
          ),
          const MainNavigationBar(currentIndex: 3),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _identifyFromPhoto,
        icon: const Icon(Icons.photo_camera),
        label: const Text('Identify'),
      ),
    );
  }
}

class _SpeciesCard extends StatelessWidget {
  const _SpeciesCard({
    super.key,
    required this.displayName,
    required this.scientificName,
    this.imageUrl,
    this.onTap,
  });

  final String displayName;
  final String scientificName;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OceanCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Species thumbnail
          Hero(
            tag: 'species-img-$displayName',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 52,
                height: 52,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => ShimmerSkeleton(
                          child: Container(color: Colors.white),
                        ),
                        errorWidget: (_, __, ___) => _PlaceholderIcon(),
                      )
                    : _PlaceholderIcon(),
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
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  scientificName,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.oceanMid.withValues(alpha: 0.2),
      child: const Icon(Icons.set_meal_outlined, color: AppColors.textSecondary),
    );
  }
}
