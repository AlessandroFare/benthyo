import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A scroll-aware hero image: stays anchored while the page scrolls
/// under it, then collapses to a regular app-bar-sized header. Use as
/// the first child of a [CustomScrollView] with [SliverAppBar] for the
/// full effect, or as a regular [Container] if the page uses a list.
class ParallaxHeroPhoto extends StatelessWidget {
  const ParallaxHeroPhoto({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.height = 280,
  });

  final String? imageUrl;
  final String title;
  final String? subtitle;
  final List<Widget> tags;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background photo (parallax) or gradient placeholder.
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.surfaceDark),
              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          // Top gradient so the app-bar text is readable.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),
          // Title block.
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tags.isNotEmpty) ...[
                  Wrap(spacing: AppSpacing.xs, children: tags),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
