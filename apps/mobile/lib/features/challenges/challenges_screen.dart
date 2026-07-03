import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/main_navigation.dart';
import 'challenges_providers.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(monthlyLeaderboardProvider);
    final currentUser = ref.watch(currentUserProvider);
    final monthLabel =
        DateFormat('MMMM yyyy').format(DateTime.now());

    return AppScaffold(
      showBack: false,
      title: 'Monthly Challenge',
      body: Column(
        children: [
          Expanded(
            child: leaderboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Could not load leaderboard',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Check your connection and try again.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () =>
                    ref.invalidate(monthlyLeaderboardProvider),
              ),
            ],
          ),
        ),
        data: (entries) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _ChallengeHeader(monthLabel: monthLabel),
            ),
            if (entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(monthLabel: monthLabel),
              )
            else ...[
              // Podium — top 3
              if (entries.length >= 3)
                SliverToBoxAdapter(
                  child: _Podium(
                    entries: entries.take(3).toList(),
                    currentUserId: currentUser?.id,
                  ),
                ),
              // Full ranked list
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                sliver: SliverList.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isMe = entry.userId == currentUser?.id;
                    return _LeaderboardRow(
                      entry: entry,
                      isCurrentUser: isMe,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
            ),
          ),
          const MainNavigationBar(currentIndex: 4),
        ],
      ),
    );
  }
}

// ─── Header card ─────────────────────────────────────────────────────────────

class _ChallengeHeader extends StatelessWidget {
  const _ChallengeHeader({required this.monthLabel});

  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.oceanGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined,
                  color: AppColors.accent, size: 28),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Most species this month',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            monthLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Log dives, report sightings, and climb the leaderboard. '
            'The ranking resets at the start of each month.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Podium ──────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, this.currentUserId});

  final List<LeaderboardEntry> entries;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    // Visual podium order: 2nd — 1st — 3rd
    final orderedIndices = entries.length == 3 ? [1, 0, 2] : [0];
    final heights = [160.0, 200.0, 130.0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(orderedIndices.length, (i) {
          final entry = entries[orderedIndices[i]];
          final isMe = entry.userId == currentUserId;
          final barHeight = heights[i];
          final rankColors = [
            const Color(0xFFADB5BD), // silver (2nd)
            const Color(0xFFFFCC00), // gold   (1st)
            const Color(0xFFCD7F32), // bronze (3rd)
          ];

          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Avatar(
                  url: entry.avatarUrl,
                  username: entry.username,
                  size: orderedIndices[i] == 0 ? 52 : 40,
                  highlight: isMe,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  entry.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight:
                            isMe ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
                Text(
                  '${entry.speciesCount} sp.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: rankColors[i].withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.sm),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '#${entry.rank}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Row ─────────────────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.isCurrentUser,
  });

  final LeaderboardEntry entry;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isCurrentUser
          ? AppColors.accent.withValues(alpha: 0.06)
          : null,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '#${entry.rank}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _rankColor(entry.rank),
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _Avatar(url: entry.avatarUrl, username: entry.username, size: 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isCurrentUser
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                ),
                if (entry.newToLifelist > 0)
                  Text(
                    '+${entry.newToLifelist} new species',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.success),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.speciesCount}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                'species',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                'You',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFCC00);
      case 2:
        return const Color(0xFFADB5BD);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return AppColors.textSecondary;
    }
  }
}

// ─── Shared avatar ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    this.url,
    required this.username,
    this.size = 40,
    this.highlight = false,
  });

  final String? url;
  final String username;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final initials = username.isNotEmpty
        ? username[0].toUpperCase()
        : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: highlight
            ? Border.all(color: AppColors.accent, width: 2)
            : null,
      ),
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.oceanMid,
        backgroundImage: url != null ? NetworkImage(url!) : null,
        child: url == null
            ? Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.38,
                ),
              )
            : null,
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.monthLabel});

  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.surfing,
                size: 64, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No dives logged yet this month',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Report a sighting or log a dive to appear on the $monthLabel leaderboard.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
