import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/sighting_photo.dart';
import '../../../core/theme/app_theme.dart';
import '../sightings_providers.dart';

/// Horizontal scrollable photo gallery for a single sighting.
///
/// - Loads photos from the `sighting_photos` table via [sightingPhotosProvider].
/// - Falls back gracefully to [fallbackUrls] (from the legacy `photo_urls`
///   column) when no rows exist yet in the new table (e.g. old sightings that
///   pre-date migration 057).
/// - Tapping a photo opens a full-screen lightbox via a hero animation.
class SightingPhotoGallery extends ConsumerWidget {
  const SightingPhotoGallery({
    super.key,
    required this.sightingId,
    this.fallbackUrls = const [],
    this.canDelete = false,
    this.onDeletePhoto,
  });

  final String sightingId;

  /// Photo URLs sourced from the old `sighting.photo_urls` column.
  /// Used as a fallback when the new `sighting_photos` table has no rows.
  final List<String> fallbackUrls;

  /// Whether to show delete icons (only shown on the owner's own sighting).
  final bool canDelete;

  /// Called when the user deletes a photo. Receives the [SightingPhoto] id.
  final ValueChanged<String>? onDeletePhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(sightingPhotosProvider(sightingId));

    return photosAsync.when(
      loading: () => const _GalleryShimmer(),
      error: (_, __) => _FallbackGallery(
        urls: fallbackUrls,
        canDelete: canDelete,
        onDelete: onDeletePhoto,
      ),
      data: (photos) {
        if (photos.isEmpty && fallbackUrls.isEmpty) {
          return const SizedBox.shrink();
        }
        if (photos.isEmpty) {
          return _FallbackGallery(
            urls: fallbackUrls,
            canDelete: canDelete,
            onDelete: onDeletePhoto,
          );
        }
        return _Gallery(
          photos: photos,
          canDelete: canDelete,
          onDelete: onDeletePhoto,
        );
      },
    );
  }
}

// ─── Internal widgets ─────────────────────────────────────────────────────────

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.photos,
    required this.canDelete,
    this.onDelete,
  });

  final List<SightingPhoto> photos;
  final bool canDelete;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return _PhotoThumbnail(
            url: photo.publicUrl,
            heroTag: 'sighting_photo_${photo.id}',
            caption: photo.caption,
            canDelete: canDelete,
            onDelete:
                onDelete != null ? () => onDelete!(photo.id) : null,
          );
        },
      ),
    );
  }
}

class _FallbackGallery extends StatelessWidget {
  const _FallbackGallery({
    required this.urls,
    required this.canDelete,
    this.onDelete,
  });

  final List<String> urls;
  final bool canDelete;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final url = urls[index];
          return _PhotoThumbnail(
            url: url,
            heroTag: 'sighting_photo_url_${url.hashCode}_$index',
            canDelete: false,
          );
        },
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({
    required this.url,
    required this.heroTag,
    this.caption,
    this.canDelete = false,
    this.onDelete,
  });

  final String url;
  final Object heroTag;
  final String? caption;
  final bool canDelete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openLightbox(context),
      child: Stack(
        children: [
          Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: CachedNetworkImage(
                imageUrl: url,
                width: 110,
                height: 110,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 110,
                  height: 110,
                  color: AppColors.surfaceDark,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 110,
                  height: 110,
                  color: AppColors.surfaceDark,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.white30),
                ),
              ),
            ),
          ),
          if (canDelete && onDelete != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openLightbox(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (ctx, animation, _) => FadeTransition(
          opacity: animation,
          child: _Lightbox(url: url, heroTag: heroTag, caption: caption),
        ),
      ),
    );
  }
}

class _Lightbox extends StatelessWidget {
  const _Lightbox({
    required this.url,
    required this.heroTag,
    this.caption,
  });

  final String url;
  final Object heroTag;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Hero(
                    tag: heroTag,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (caption != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      caption!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryShimmer extends StatelessWidget {
  const _GalleryShimmer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, __) => Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}
