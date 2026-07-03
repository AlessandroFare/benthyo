import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Illustrated empty state with an animated entrance (fade + scale).
///
/// Renders the icon inside a soft gradient circle so empty screens still
/// feel designed rather than broken.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppDurations.slow,
        curve: AppCurves.emphasized,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: 0.92 + value * 0.08,
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            AppColors.oceanMid.withValues(alpha: 0.35),
                            AppColors.oceanDeep.withValues(alpha: 0.55),
                          ]
                        : [
                            AppColors.oceanShallow.withValues(alpha: 0.15),
                            AppColors.oceanMid.withValues(alpha: 0.2),
                          ],
                  ),
                ),
                child: Icon(
                  icon,
                  size: 42,
                  color: isDark ? AppColors.accent : AppColors.oceanMid,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
