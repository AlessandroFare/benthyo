import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Pressable card with a subtle scale-down micro-interaction on tap,
/// soft elevation and consistent radius. The building block for list
/// items across the app.
class OceanCard extends StatefulWidget {
  const OceanCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  State<OceanCard> createState() => _OceanCardState();
}

class _OceanCardState extends State<OceanCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final card = AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        margin: widget.margin,
        decoration: BoxDecoration(
          color: widget.gradient == null
              ? (isDark ? AppColors.surfaceDark : Colors.white)
              : null,
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: widget.borderColor ??
                (isDark
                    ? AppColors.borderDark
                    : Colors.black.withValues(alpha: 0.08)),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: AppColors.oceanDeep
                    .withValues(alpha: _pressed ? 0.04 : 0.06),
                blurRadius: _pressed ? 6 : 14,
                offset: Offset(0, _pressed ? 1 : 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );

    if (widget.onTap == null && widget.onLongPress == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!.call();
            },
      child: card,
    );
  }
}

/// Compact pill badge used inside cards (depth, gas mix, counts...).
class OceanBadge extends StatelessWidget {
  const OceanBadge({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? Colors.white : c),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: filled ? Colors.white : c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
