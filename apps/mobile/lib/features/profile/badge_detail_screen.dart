import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import 'profile_providers.dart';

class BadgeDetailScreen extends ConsumerWidget {
  const BadgeDetailScreen({super.key, required this.badgeId});

  final String badgeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeAsync = ref.watch(badgeProvider(badgeId));
    final userBadgesAsync = ref.watch(userBadgesProvider);
    final dateFormat = DateFormat.yMMMMd();

    return AppScaffold(
      title: 'Badge',
      body: AsyncValueWidget(
        value: badgeAsync,
        data: (badge) {
          if (badge == null) {
            return const Center(child: Text('Badge not found'));
          }

          final earned = userBadgesAsync.maybeWhen(
            data: (list) =>
                list.where((ub) => ub.badgeId == badgeId).firstOrNull,
            orElse: () => null,
          );

          final tierColor = switch (badge.tier) {
            3 => Colors.amber,
            2 => Colors.grey.shade400,
            _ => const Color(0xFFCD7F32),
          };

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: tierColor.withValues(alpha: 0.2),
                  backgroundImage: badge.iconUrl != null
                      ? CachedNetworkImageProvider(badge.iconUrl!)
                      : null,
                  child: badge.iconUrl == null
                      ? Icon(Icons.military_tech, size: 48, color: tierColor)
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                badge.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                badge.description,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Chip(
                  label: Text(
                    'Tier ${badge.tier} · ${badge.criteriaType.dbValue}',
                  ),
                ),
              ),
              if (earned != null) ...[
                const SizedBox(height: AppSpacing.lg),
                ListTile(
                  leading:
                      const Icon(Icons.check_circle, color: AppColors.success),
                  title: const Text('Earned'),
                  subtitle: Text(dateFormat.format(earned.earnedAt)),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.lg),
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Not yet earned'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
