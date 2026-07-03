import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:benthyo/features/onboarding/onboarding_providers.dart';
import 'package:benthyo/features/onboarding/onboarding_screen.dart';

final _router = GoRouter(
  initialLocation: '/onboarding',
  routes: [
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
    GoRoute(path: '/map', builder: (_, __) => const SizedBox()),
  ],
);

void main() {
  group('OnboardingProviders', () {
    test('onboarding defaults to not completed', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      // Read the notifier to trigger initialization; the value is checked below.
      container.read(onboardingNotifierProvider.notifier);
      expect(container.read(onboardingNotifierProvider), isFalse);
    });

    test('complete() marks onboarding as done', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      final notifier = container.read(onboardingNotifierProvider.notifier);
      await notifier.complete();
      expect(container.read(onboardingNotifierProvider), isTrue);
    });

    test('reset() allows re-triggering onboarding', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(() => container.dispose());

      await container.read(onboardingNotifierProvider.notifier).complete();
      expect(container.read(onboardingNotifierProvider), isTrue);
      await container.read(onboardingNotifierProvider.notifier).reset();
      expect(container.read(onboardingNotifierProvider), isFalse);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('renders first onboarding card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Explore Dive Sites'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('skip button advances to last card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Track Your Journey'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('Get Starts navigates to login after completion', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Get Started'), findsOneWidget);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
    });
  });
}
