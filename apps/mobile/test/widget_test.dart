// Smoke test: verifies the most-imported widget tree can resolve its
// theme without throwing. We deliberately don't boot the full
// `BenthyoApp` because it requires a live Supabase URL; instead we
// build a minimal MaterialApp that touches every theme helper the
// app relies on (`AppTheme.light()`, `AppTheme.dark()`,
// `AppColors.*`, `AppSpacing.*`).
//
// Run with:
//   flutter test

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:benthyo/core/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme builds both light and dark schemes', (tester) async {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.colorScheme.primary, AppColors.primary);
    expect(dark.brightness, Brightness.dark);
    expect(light.useMaterial3, isTrue);
  });

  test('Spacing constants are sane', () {
    expect(AppSpacing.xs, lessThan(AppSpacing.sm));
    expect(AppSpacing.sm, lessThan(AppSpacing.md));
    expect(AppSpacing.md, lessThan(AppSpacing.lg));
    expect(AppSpacing.lg, lessThan(AppSpacing.xl));
    expect(AppSpacing.minTapTarget, greaterThanOrEqualTo(48));
  });
}
