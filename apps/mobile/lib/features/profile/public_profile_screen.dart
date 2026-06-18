import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/api_config.dart';
import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import 'public_profile_providers.dart';

class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logbookAsync = ref.watch(publicLogbookProvider(username));
    final dateFormat = DateFormat.yMMMd();

    return AppScaffold(
      title: '@$username',
      body: AsyncValueWidget(
        value: logbookAsync,
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Profile not found'));
          }
          final profile = data.profile;
          final verification = data.verification;
          final level = verification?.level ?? 1;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage: profile.avatarUrl != null
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null
                        ? Text(username[0].toUpperCase())
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.fullName ?? username,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text('@$username'),
                        Text(
                          '${profile.certificationLevel.dbValue} · ${profile.totalDives} dives',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Chip(
                label: Text('Verification level $level'),
                avatar: const Icon(Icons.verified, size: 18),
              ),
              if (!data.isPublic)
                const ListTile(
                  leading: Icon(Icons.lock),
                  title: Text('Logbook is private'),
                )
              else ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Recent dives',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...data.dives.map(
                  (d) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(dateFormat.format(d.diveDate)),
                    trailing: Text('${d.maxDepthM.toInt()} m'),
                    subtitle: Text('${d.durationMin} min'),
                  ),
                ),
                if (data.lifeList.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Life list (${data.lifeList.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ...data.lifeList.take(10).map(
                        (e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.commonName ?? e.scientificName),
                          subtitle: Text(e.scientificName),
                        ),
                      ),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Share: ${ApiConfig.baseUrl.replaceAll('/api/v1', '')}/u/$username',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}
