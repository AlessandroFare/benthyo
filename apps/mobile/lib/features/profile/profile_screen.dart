import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/main_navigation.dart';
import '../../core/widgets/ocean_card.dart';
import '../auth/auth_providers.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final badgesAsync = ref.watch(userBadgesProvider);

    return AppScaffold(
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
                  return const EmptyState(
                    icon: Icons.person_off_outlined,
                    title: 'Profile not found',
                    subtitle: 'Unable to load your profile data.',
                  );
                }
                return ListView(
                  children: [
                    // Ocean gradient header
                    _ProfileHeader(profile: profile),
                    const SizedBox(height: AppSpacing.md),
                    // Stats row
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: _AnimatedStatsRow(profile: profile),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Quick actions
                    SectionHeader(
                      title: 'My Activity',
                      trailing: OutlinedButton.icon(
                        onPressed: () => context.push('/life-list'),
                        icon: const Icon(Icons.list, size: 16),
                        label: const Text('Life list'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _NavItem(
                      icon: Icons.store_outlined,
                      label: 'Dive operators',
                      onTap: () => context.push('/operators'),
                    ),
                    _NavItem(
                      icon: Icons.luggage_outlined,
                      label: 'Trips',
                      onTap: () => context.push('/trips'),
                    ),
                    _NavItem(
                      icon: Icons.scuba_diving_outlined,
                      label: 'Gear & maintenance',
                      onTap: () => context.push('/gear'),
                    ),
                    _NavItem(
                      icon: Icons.public_outlined,
                      label: 'Public logbook',
                      subtitle: 'benthyo.com/u/${profile.username}',
                      onTap: () => context.push('/u/${profile.username}'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Badges
                    SectionHeader(title: 'Badges'),
                    const SizedBox(height: AppSpacing.xs),
                    AsyncValueWidget(
                      value: badgesAsync,
                      isEmpty: (badges) => badges.isEmpty,
                      empty: const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: EmptyState(
                          icon: Icons.military_tech_outlined,
                          title: 'No badges yet',
                          subtitle: 'Complete dives and sightings to earn badges.',
                        ),
                      ),
                      data: (badges) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: badges.asMap().entries.map((entry) {
                            final i = entry.key;
                            final ub = entry.value;
                            final badge = ub.badge;
                            if (badge == null) return const SizedBox.shrink();
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: AppDurations.slow +
                                  Duration(
                                    milliseconds: (i * 60).clamp(0, 600),
                                  ),
                              curve: AppCurves.spring,
                              builder: (context, v, child) => Transform.scale(
                                scale: v,
                                child: Opacity(opacity: v, child: child),
                              ),
                              child: ActionChip(
                                avatar: badge.iconUrl != null
                                    ? CircleAvatar(
                                        backgroundImage:
                                            CachedNetworkImageProvider(
                                          badge.iconUrl!,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.military_tech,
                                        size: 18,
                                      ),
                                label: Text(badge.name),
                                onPressed: () =>
                                    context.push('/badges/${badge.id}'),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(authRepositoryProvider)
                              .signOut();
                          if (context.mounted) context.go('/login');
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
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

// ─── Header ──────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.oceanGradient),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          // Avatar with animated ring
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.0),
            duration: AppDurations.slow,
            curve: AppCurves.spring,
            builder: (context, v, child) =>
                Transform.scale(scale: v, child: child),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glowing ring
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: [AppColors.accent, AppColors.oceanShallow, AppColors.accent],
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.surfaceDark,
                  backgroundImage: profile.avatarUrl != null
                      ? CachedNetworkImageProvider(profile.avatarUrl!)
                      : null,
                  child: profile.avatarUrl == null
                      ? Text(
                          (profile.username as String)[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName ?? profile.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '@${profile.username}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${profile.certificationLevel.dbValue} · ${profile.certificationAgency.dbValue}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (profile.bio != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    profile.bio!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

// ─── Animated stats row ──────────────────────────────────────────────────────

class _AnimatedStatsRow extends StatelessWidget {
  const _AnimatedStatsRow({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total dives',
            value: profile.totalDives as int,
            icon: Icons.water,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            label: 'Sightings',
            value: profile.totalSightings as int? ?? 0,
            icon: Icons.visibility_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return OceanCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: value),
                duration: AppDurations.slow,
                curve: AppCurves.emphasized,
                builder: (_, v, __) => Text(
                  '$v',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Nav item ────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, color: AppColors.accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}
