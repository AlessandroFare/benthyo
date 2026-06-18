import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import 'auth_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// Delay between mount and auto-navigation. Exposed as a static so
  /// widget tests can override it (see `test/widget_test.dart`) and
  /// tests can set it to `Duration.zero` to skip the timer.
  @visibleForTesting
  static Duration navigationDelay = const Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    Future.delayed(navigationDelay, _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final authenticated = ref.read(isAuthenticatedProvider);
    if (!authenticated) {
      context.go('/login');
      return;
    }
    final profile = await ref.read(userProfileProvider.future);
    if (!mounted) return;
    if (profile?.isProfileComplete ?? false) {
      context.go('/map');
    } else {
      context.go('/profile-setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.scuba_diving, size: 72, color: AppColors.accent),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'OceanLog',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            const CircularProgressIndicator(color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
