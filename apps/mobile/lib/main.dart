import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/map/dive_map_tile_cache.dart';
import 'core/router/app_router.dart';
import 'core/router/page_transitions.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/profile_providers.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.tracesSampleRate = 0.1;
      },
      appRunner: () async {
        await initializeSupabase();
        await DiveMapTileCache.initialize();
        runApp(const ProviderScope(child: OceanLogApp()));
      },
    );
    return;
  }

  await initializeSupabase();
  await DiveMapTileCache.initialize();
  runApp(const ProviderScope(child: OceanLogApp()));
}

class OceanLogApp extends ConsumerWidget {
  const OceanLogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoSyncCoordinatorProvider);

    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    final lightTheme = AppTheme.light().copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: FadeUpPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpPageTransitionsBuilder(),
        },
      ),
    );
    final darkTheme = AppTheme.dark().copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: FadeUpPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpPageTransitionsBuilder(),
        },
      ),
    );

    return MaterialApp.router(
      title: 'OceanLog',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      themeAnimationCurve: Curves.easeOutCubic,
      themeAnimationDuration: const Duration(milliseconds: 220),
    );
  }
}
