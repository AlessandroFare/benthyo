import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../auth/auth_providers.dart';
import '../../core/widgets/main_navigation.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final badgesAsync = ref.watch(userBadgesProvider);

    return AppScaffold(
      title: 'Profile',
      showBack: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push('/settings'),
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: AsyncValueWidget(
              value: profileAsync,
              data: (profile) {
                if (profile == null) {
                  return const Center(child: Text('Profile not found'));
                }
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundImage: profile.avatarUrl != null
                              ? CachedNetworkImageProvider(profile.avatarUrl!)
                              : null,
                          child: profile.avatarUrl == null
                              ? Text(
                                  profile.username[0].toUpperCase(),
                                  style: const TextStyle(fontSize: 28),
                                )
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.fullName ?? profile.username,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              Text('@${profile.username}'),
                              Text(
                                '${profile.certificationLevel.dbValue} · ${profile.certificationAgency.dbValue}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (profile.bio != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(profile.bio!),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        _StatCard(
                          label: 'Total dives',
                          value: '${profile.totalDives}',
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.push('/life-list'),
                            child: const Text('Life list'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ListTile(
                      leading: const Icon(Icons.store),
                      title: const Text('Dive operators'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/operators'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.luggage),
                      title: const Text('Trips'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/trips'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.scuba_diving),
                      title: const Text('Gear & maintenance'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/gear'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.public),
                      title: const Text('Public logbook'),
                      subtitle: Text('benthyo.com/u/${profile.username}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/u/${profile.username}'),
                    ),
                    const Divider(),
                    Text(
                      'Badges',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AsyncValueWidget(
                      value: badgesAsync,
                      isEmpty: (badges) => badges.isEmpty,
                      empty: const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Text('No badges earned yet'),
                      ),
                      data: (badges) => Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: badges.map((ub) {
                          final badge = ub.badge;
                          if (badge == null) return const SizedBox.shrink();
                          return ActionChip(
                            avatar: badge.iconUrl != null
                                ? CircleAvatar(
                                    backgroundImage: CachedNetworkImageProvider(
                                      badge.iconUrl!,
                                    ),
                                  )
                                : const Icon(Icons.military_tech, size: 18),
                            label: Text(badge.name),
                            onPressed: () =>
                                context.push('/badges/${badge.id}'),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton(
                      onPressed: () async {
                        await ref.read(authRepositoryProvider).signOut();
                        if (context.mounted) context.go('/login');
                      },
                      child: const Text('Sign out'),
                    ),
                  ],
                );
              },
            ),
          ),
          const MainNavigationBar(currentIndex: 4),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
