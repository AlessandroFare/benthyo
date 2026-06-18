import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../discovery_providers.dart';

class BuddyFinderSection extends ConsumerWidget {
  const BuddyFinderSection({super.key, required this.siteId});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diversAsync = ref.watch(recentDiversAtSiteProvider(siteId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buddy finder',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Divers who logged here in the last 90 days (opt-in only).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AsyncValueWidget(
              value: diversAsync,
              isEmpty: (list) => list.isEmpty,
              empty: const Text('No recent divers visible at this site yet.'),
              data: (divers) => Column(
                children: divers
                    .map(
                      (d) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage: d.avatarUrl != null
                              ? NetworkImage(d.avatarUrl!)
                              : null,
                          child: d.avatarUrl == null
                              ? Text(
                                  d.username.isNotEmpty
                                      ? d.username[0].toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        title: Text(d.displayName()),
                        subtitle: Text(
                          '@${d.username} · ${d.certLevel.dbValue} · ${d.diveCount} dives',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline),
                              tooltip: 'Message',
                              onPressed: () => context.push('/messages/${d.userId}'),
                            ),
                            Text(
                              '${d.lastDiveDate.year}-${d.lastDiveDate.month.toString().padLeft(2, '0')}-${d.lastDiveDate.day.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
