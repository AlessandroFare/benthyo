import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class OceanTag extends StatelessWidget {
  const OceanTag({
    super.key,
    required this.label,
    this.color,
    this.textColor,
  });

  final String label;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedColor = color ??
        (isDark
            ? AppColors.accent.withValues(alpha: 0.15)
            : AppColors.primary.withValues(alpha: 0.12));
    final resolvedTextColor =
        textColor ?? (isDark ? AppColors.accent : AppColors.primary);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: resolvedTextColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class OceanTagRow extends StatelessWidget {
  const OceanTagRow({super.key, required this.tags});

  final List<OceanTag> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: tags,
    );
  }
}