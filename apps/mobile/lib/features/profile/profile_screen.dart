import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/citizen_science_impact.dart';
import '../../core/models/dive_log.dart';
import '../../core/models/enums.dart';
import '../../core/models/user_profile.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/main_navigation.dart';
import '../../core/widgets/ocean_card.dart';
import '../auth/auth_providers.dart';
import '../dive_logs/dive_logs_providers.dart';
import '../life_list/life_list_providers.dart';
import '../sightings/sightings_providers.dart';
import 'profile_providers.dart';

// ─── Derived stats provider ───────────────────────────────────────────────────

/// Computes quick stats from the user's dive log list: max depth, total
/// bottom time (minutes), and the current consecutive-day dive streak.
final _profileDiveStatsProvider = Provider((ref) {
  final logsAsync = ref.watch(diveLogsProvider);
  return logsAsync.whenData((logs) {
    if (logs.isEmpty) {
      return _DiveStats(
          maxDepthM: 0, totalMinutes: 0, streakDays: 0, recentLogs: []);
    }

    double maxDepth = 0;
    int totalMin = 0;
    for (final l in logs) {
      if (l.maxDepthM > maxDepth) maxDepth = l.maxDepthM;
      totalMin += l.durationMin;
    }

    // Sort by date ascending to compute streak.
    final sorted = [...logs]
      ..sort((a, b) => a.diveDate.compareTo(b.diveDate));
    final days = sorted
        .map((l) =>
            DateTime(l.diveDate.year, l.diveDate.month, l.diveDate.day))
        .toSet()
        .toList()
      ..sort();

    int streak = 0;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    // Walk backwards from today/yesterday.
    DateTime cursor = days.last == todayDate
        ? todayDate
        : (days.last == todayDate.subtract(const Duration(days: 1))
            ? todayDate.subtract(const Duration(days: 1))
            : null) ??
            DateTime(0);

    if (cursor.year > 1) {
      for (var i = days.length - 1; i >= 0; i--) {
        if (days[i] == cursor) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }

    final recent = (logs.length > 3 ? logs.sublist(0, 3) : logs);

    return _DiveStats(
      maxDepthM: maxDepth,
      totalMinutes: totalMin,
      streakDays: streak,
      recentLogs: recent,
    );
  });
});

class _DiveStats {
  const _DiveStats({
    required this.maxDepthM,
    required this.totalMinutes,
    required this.streakDays,
    required this.recentLogs,
  });

  final double maxDepthM;
  final int totalMinutes;
  final int streakDays;
  final List<DiveLog> recentLogs;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final badgesAsync = ref.watch(userBadgesProvider);
    final lifeListAsync = ref.watch(lifeListProvider);
    final statsAsync = ref.watch(_profileDiveStatsProvider);
    final impactAsync = ref.watch(citizenScienceImpactProvider);

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
                  return const EmptyState(
                    icon: Icons.person_off_outlined,
                    title: 'Profile not found',
                    subtitle: 'Unable to load your profile data.',
                  );
                }

                final speciesCount = lifeListAsync.whenOrNull(
                      data: (ll) => ll.length,
                    ) ??
                    0;

                final stats = statsAsync.whenOrNull(data: (s) => s);

                return ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // ── Ocean gradient header ──
                    _ProfileHeader(
                      profile: profile,
                      streakDays: stats?.streakDays ?? 0,
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 4-stat grid ──
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                      child: _StatsGrid(
                        totalDives: profile.totalDives,
                        speciesCount: speciesCount,
                        maxDepthM: stats?.maxDepthM ?? 0,
                        totalHours:
                            ((stats?.totalMinutes ?? 0) / 60).floorToDouble(),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // ── Recent dives ──
                    if (stats != null && stats.recentLogs.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Recent dives',
                        action: TextButton(
                          onPressed: () => context.push('/dive-logs'),
                          child: const Text('See all'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SizedBox(
                        height: 112,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          itemCount: stats.recentLogs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: AppSpacing.sm),
                          itemBuilder: (ctx, i) => _RecentDiveCard(
                            log: stats.recentLogs[i],
                            index: i,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // ── Citizen science impact banner ──
                    impactAsync.whenOrNull(
                      data: (impact) => impact != null &&
                              impact.totalSightings > 0
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  0,
                                  AppSpacing.md,
                                  AppSpacing.lg),
                              child: _CitizenScienceBanner(impact: impact),
                            )
                          : null,
                    ) ??
                        const SizedBox.shrink(),

                    // ── My Activity ──
                    _SectionHeader(
                      title: 'My Activity',
                      action: OutlinedButton.icon(
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
                      icon: Icons.calendar_today_outlined,
                      label: 'Bookings',
                      onTap: () => context.push('/bookings'),
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

                    // ── Badges ──
                    _SectionHeader(title: 'Badges'),
                    const SizedBox(height: AppSpacing.xs),
                    AsyncValueWidget(
                      value: badgesAsync,
                      isEmpty: (badges) => badges.isEmpty,
                      empty: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm),
                        child: EmptyState(
                          icon: Icons.military_tech_outlined,
                          title: 'No badges yet',
                          subtitle:
                              'Complete dives and sightings to earn badges.',
                        ),
                      ),
                      data: (badges) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md),
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
                                      milliseconds: (i * 60).clamp(0, 600)),
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
                                                badge.iconUrl!),
                                      )
                                    : Icon(
                                        _tierIcon(ub.badge?.tier ?? 1),
                                        size: 18,
                                        color: _tierColor(ub.badge?.tier ?? 1),
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
                          horizontal: AppSpacing.md),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await ref.read(authRepositoryProvider).signOut();
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
          const MainNavigationBar(currentIndex: 5),
        ],
      ),
    );
  }

  IconData _tierIcon(int tier) {
    return switch (tier) {
      3 => Icons.workspace_premium,
      2 => Icons.star,
      _ => Icons.military_tech,
    };
  }

  Color _tierColor(int tier) {
    return switch (tier) {
      3 => const Color(0xFFFFD700), // gold
      2 => const Color(0xFFC0C0C0), // silver
      _ => const Color(0xFFCD7F32), // bronze
    };
  }
}

// ─── Profile header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.streakDays});

  final UserProfile profile;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Ocean gradient background
        Container(
          decoration: const BoxDecoration(gradient: AppColors.oceanGradient),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xl + 8),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animated avatar ring
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.85, end: 1.0),
                    duration: AppDurations.slow,
                    curve: AppCurves.spring,
                    builder: (context, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Sweep gradient ring
                        Container(
                          width: 82,
                          height: 82,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.oceanShallow,
                                AppColors.accent
                              ],
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 37,
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
                              color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 5),
                        // Cert badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                                color:
                                    AppColors.accent.withValues(alpha: 0.5)),
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
                                color: Colors.white70, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // ── Streak pill (shown only when active) ──
              if (streakDays > 0) ...[
                const SizedBox(height: AppSpacing.md),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: AppCurves.spring,
                  builder: (context, v, child) => Transform.scale(
                      scale: v,
                      child: Opacity(opacity: v, child: child)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.18),
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                              color:
                                  AppColors.warning.withValues(alpha: 0.55)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department,
                                color: AppColors.warning, size: 17),
                            const SizedBox(width: 6),
                            Text(
                              '$streakDays-day dive streak',
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Quick-log FAB pinned to top-right of header
        Positioned(
          right: AppSpacing.md,
          bottom: 0,
          child: Transform.translate(
            offset: const Offset(0, 24),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: AppCurves.spring,
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: FloatingActionButton.extended(
                heroTag: 'profile_quick_log',
                onPressed: () => context.push('/dive-logs/quick'),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Quick log',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                elevation: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 4-stat grid ─────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.totalDives,
    required this.speciesCount,
    required this.maxDepthM,
    required this.totalHours,
  });

  final int totalDives;
  final int speciesCount;
  final double maxDepthM;
  final double totalHours;

  @override
  Widget build(BuildContext context) {
    // Reserve space for the FAB that overlaps from the header.
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: 'Dives',
              value: totalDives,
              icon: Icons.water,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.accent
                  : AppColors.oceanMid,   // <-- cambiato da AppColors.accent fisso
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatTile(
              label: 'Species',
              value: speciesCount,
              icon: Icons.biotech_outlined,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatTile(
              label: 'Max depth',
              value: maxDepthM.toInt(),
              unit: 'm',
              icon: Icons.keyboard_double_arrow_down_outlined,
              color: AppColors.oceanMid,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatTile(
              label: 'Hours',
              value: totalHours.toInt(),
              icon: Icons.schedule_outlined,
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return OceanCard(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm + 2, horizontal: AppSpacing.xs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: AppDurations.slow,
            curve: AppCurves.emphasized,
            builder: (_, v, __) => Text(
              unit != null ? '$v$unit' : '$v',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Recent dive card (horizontal scroll) ────────────────────────────────────

class _RecentDiveCard extends StatelessWidget {
  const _RecentDiveCard({required this.log, required this.index});

  final DiveLog log;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final depthColor = AppColors.depthColor(log.maxDepthM);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration:
          AppDurations.base + Duration(milliseconds: index * 80),
      curve: AppCurves.emphasized,
      builder: (context, v, child) => Transform.translate(
        offset: Offset(0, 12 * (1 - v)),
        child: Opacity(opacity: v, child: child),
      ),
      child: OceanCard(
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            depthColor.withValues(alpha: isDark ? 0.18 : 0.08),
            isDark ? AppColors.surfaceDark : Colors.white,
          ],
        ),
        borderColor: depthColor.withValues(alpha: 0.35),
        child: SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: depthColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${log.diveDate.day.toString().padLeft(2, '0')}/'
                    '${log.diveDate.month.toString().padLeft(2, '0')}/'
                    '${log.diveDate.year}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${log.maxDepthM.toStringAsFixed(1)} m',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: depthColor,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${log.durationMin} min',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              // Depth bar
              _DepthBar(depthM: log.maxDepthM, color: depthColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 5-segment bar showing depth relative to 40 m max.
class _DepthBar extends StatelessWidget {
  const _DepthBar({required this.depthM, required this.color});

  final double depthM;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = (depthM / 40).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(
        value: fill,
        minHeight: 4,
        backgroundColor: color.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, 0),
      child: Row(
        children: [
          // Accent bar
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
          ),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ─── Nav item ─────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? AppColors.accent : AppColors.oceanMid;

    return OceanCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, color: iconColor),
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
                      fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (badge != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}

// ─── Citizen science impact banner ────────────────────────────────────────────

class _CitizenScienceBanner extends StatefulWidget {
  const _CitizenScienceBanner({required this.impact});

  final CitizenScienceImpact impact;

  @override
  State<_CitizenScienceBanner> createState() => _CitizenScienceBannerState();
}

class _CitizenScienceBannerState extends State<_CitizenScienceBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppCurves.emphasized));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    // Small delay so it enters after the stats grid settles.
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _share() {
    final impact = widget.impact;
    final parts = <String>[];
    if (impact.inatContributed > 0) {
      parts.add('${impact.inatContributed} to iNaturalist');
    }
    if (impact.gbifContributed > 0) {
      parts.add('${impact.gbifContributed} to GBIF');
    }
    final dbText = parts.isEmpty
        ? 'global ocean biodiversity databases'
        : parts.join(' and ');

    SharePlus.instance.share(
      ShareParams(
        text:
            'I\'ve logged ${impact.totalSightings} marine sightings on benthyo, '
            'contributing $dbText. '
            'Help protect the ocean \u2014 track your dives at benthyo.com',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final impact = widget.impact;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      AppColors.oceanMid.withValues(alpha: 0.45),
                      AppColors.oceanDeep.withValues(alpha: 0.75),
                    ]
                  : [
                      AppColors.oceanShallow.withValues(alpha: 0.12),
                      AppColors.oceanMid.withValues(alpha: 0.22),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? AppColors.accent.withValues(alpha: 0.22)
                  : AppColors.oceanMid.withValues(alpha: 0.35),
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(
                      Icons.public,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your science impact',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.oceanDeep,
                                  ),
                        ),
                        Text(
                          'Contributing to global ocean research',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isDark
                                        ? Colors.white60
                                        : AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Animated headline count ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: impact.totalSightings),
                    duration: AppDurations.slow +
                        const Duration(milliseconds: 200),
                    curve: AppCurves.emphasized,
                    builder: (_, v, __) => Text(
                      '$v',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color:
                                isDark ? AppColors.accent : AppColors.oceanMid,
                            height: 1,
                          ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'marine sightings logged',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.white70
                                : AppColors.oceanDeep,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),

              // ── Platform chips ──
              if (impact.hasContributed) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (impact.inatContributed > 0)
                      _ImpactChip(
                        label: 'iNaturalist',
                        count: impact.inatContributed,
                        color: const Color(0xFF74AC00),
                      ),
                    if (impact.gbifContributed > 0)
                      _ImpactChip(
                        label: 'GBIF',
                        count: impact.gbifContributed,
                        color: const Color(0xFFE1932C),
                      ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Enable data sharing in Settings to contribute to '
                  'iNaturalist and GBIF.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Colors.white54
                            : AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // ── Share button ──
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Share your impact'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDark ? AppColors.accent : AppColors.oceanMid,
                    side: BorderSide(
                      color: isDark
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : AppColors.oceanMid.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
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

/// A small pill chip showing a platform name and how many sightings were
/// contributed to that platform.
class _ImpactChip extends StatelessWidget {
  const _ImpactChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$count to $label',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dive stats model ─────────────────────────────────────────────────────────

// (Unused arc painter kept for potential future use — removed to keep
// the file lean. The streak logic above is the primary addition.)
