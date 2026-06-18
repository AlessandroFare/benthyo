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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: color ?? AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: textColor ?? AppColors.primary,
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
