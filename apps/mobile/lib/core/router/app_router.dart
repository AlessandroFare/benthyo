import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/check_email_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/dive_logs/dive_log_create_screen.dart';
import '../../features/dive_logs/dive_log_detail_screen.dart';
import '../../features/dive_logs/dive_log_import_screen.dart';
import '../../features/dive_logs/dive_log_list_screen.dart';
import '../../features/dive_sites/dive_site_detail_screen.dart';
import '../../features/dive_sites/map_screen.dart';
import '../../features/life_list/life_list_screen.dart';
import '../../features/operators/operator_detail_screen.dart';
import '../../features/operators/operator_list_screen.dart';
import '../../features/operators/waiver_sign_screen.dart';
import '../../features/profile/badge_detail_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/gear/gear_list_screen.dart';
import '../../features/profile/public_profile_screen.dart';
import '../../features/medical/medical_form_screen.dart';
import '../../features/trips/trip_detail_screen.dart';
import '../../features/trips/trip_list_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/sightings/add_sighting_screen.dart';
import '../../features/sightings/sightings_feed_screen.dart';
import '../../features/species/species_browser_screen.dart';
import '../../features/species/species_detail_screen.dart';
import '../../features/species/species_identify_screen.dart';
import '../../features/dive_logs/quick_log_screen.dart';
import '../../features/profile/cert_card_scan_screen.dart';
import '../../features/social/social_feed_screen.dart';
import '../../features/social/messages_screen.dart';
import '../../features/social/chat_screen.dart';
import '../../features/dive_logs/ble_sync_screen.dart';
import '../../features/operators/marketplace_screen.dart';
import '../../features/species/species_quiz_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/onboarding_providers.dart';
import '../../features/bookings/slot_browser_screen.dart';
import '../../features/bookings/booking_create_screen.dart';
import '../../features/bookings/booking_list_screen.dart';
import '../supabase/supabase_client.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileComplete = ref.watch(profileCompleteProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final isLoading = authState.isLoading;

      if (isLoading) {
        return location == '/' ? null : '/';
      }

      final authenticated = ref.read(isAuthenticatedProvider);
      final isAuthRoute =
          location == '/login' ||
          location == '/register' ||
          location.startsWith('/check-email');
      final isPublicRoute = location.startsWith('/u/');
      final isSplash = location == '/';
      final isOnboarding = location == '/onboarding';
      final isProfileSetup = location == '/profile-setup';

      if (isOnboarding) return null;

      if (!authenticated) {
        if (isAuthRoute || isSplash || isPublicRoute) {
          if (isSplash) {
            final completed = await ref.read(onboardingCompletedProvider.future);
            if (!completed) return '/onboarding';
          }
          return null;
        }
        return '/login';
      }

      if (!profileComplete && !isProfileSetup) {
        return '/profile-setup';
      }

      if (profileComplete && (isAuthRoute || isProfileSetup || isSplash)) {
        return '/map';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/check-email',
        builder: (context, state) => CheckEmailScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: '/dive-sites/:id',
        builder: (context, state) => DiveSiteDetailScreen(
          siteId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/species',
        builder: (context, state) => const SpeciesBrowserScreen(),
      ),
      GoRoute(
        path: '/species/quiz',
        builder: (context, state) => const SpeciesQuizScreen(),
      ),
      GoRoute(
        path: '/species/identify',
        builder: (context, state) => SpeciesIdentifyScreen(
          initialQuery: state.uri.queryParameters['q'] ?? '',
          imagePath: state.uri.queryParameters['path'],
        ),
      ),
      GoRoute(
        path: '/species/:id',
        builder: (context, state) => SpeciesDetailScreen(
          speciesId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/sightings',
        builder: (context, state) => const SightingsFeedScreen(),
      ),
      GoRoute(
        path: '/sightings/add',
        builder: (context, state) => AddSightingScreen(
          initialSiteId: state.uri.queryParameters['siteId'],
          initialSpeciesId: state.uri.queryParameters['speciesId'],
          initialPhotoUrl: state.uri.queryParameters['photoUrl'] != null
              ? Uri.decodeComponent(state.uri.queryParameters['photoUrl']!)
              : null,
        ),
      ),
      GoRoute(
        path: '/dive-logs',
        builder: (context, state) => const DiveLogListScreen(),
      ),
      GoRoute(
        path: '/dive-logs/quick',
        builder: (context, state) => QuickLogScreen(
          initialSiteId: state.uri.queryParameters['siteId'],
        ),
      ),
      GoRoute(
        path: '/dive-logs/import',
        builder: (context, state) => const DiveLogImportScreen(),
      ),
      GoRoute(
        path: '/dive-logs/create',
        builder: (context, state) => DiveLogCreateScreen(
          initialSiteId: state.uri.queryParameters['siteId'],
        ),
      ),
      GoRoute(
        path: '/dive-logs/ble',
        builder: (context, state) => const BleSyncScreen(),
      ),
      GoRoute(
        path: '/dive-logs/:id',
        builder: (context, state) => DiveLogDetailScreen(
          logId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/life-list',
        builder: (context, state) => const LifeListScreen(),
      ),
      GoRoute(
        path: '/operators',
        builder: (context, state) => const OperatorListScreen(),
      ),
      GoRoute(
        path: '/operators/:id',
        builder: (context, state) => OperatorDetailScreen(
          operatorId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/waiver/:slug',
        builder: (context, state) => WaiverSignScreen(
          operatorSlug: state.pathParameters['slug']!,
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/badges/:id',
        builder: (context, state) => BadgeDetailScreen(
          badgeId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) => const SocialFeedScreen(),
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) => const MessagesScreen(),
      ),
      GoRoute(
        path: '/messages/:recipientId',
        builder: (context, state) => ChatScreen(
          recipientId: state.pathParameters['recipientId']!,
          conversationId: state.uri.queryParameters['conv'],
        ),
      ),
      GoRoute(
        path: '/marketplace',
        builder: (context, state) => const MarketplaceScreen(),
      ),
      GoRoute(
        path: '/cert-card',
        builder: (context, state) => const CertCardScanScreen(),
      ),
      GoRoute(
        path: '/slots',
        builder: (context, state) => const SlotBrowserScreen(),
      ),
      GoRoute(
        path: '/book/:slotId',
        builder: (context, state) => BookingCreateScreen(
          slotId: state.pathParameters['slotId']!,
        ),
      ),
      GoRoute(
        path: '/bookings',
        builder: (context, state) => const BookingListScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/u/:username',
        builder: (context, state) => PublicProfileScreen(
          username: state.pathParameters['username']!,
        ),
      ),
      GoRoute(
        path: '/gear',
        builder: (context, state) => const GearListScreen(),
      ),
      GoRoute(
        path: '/trips/:id',
        builder: (context, state) => TripDetailScreen(
          tripId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/medical',
        builder: (context, state) => MedicalFormScreen(
          tripId: state.uri.queryParameters['tripId'],
          operatorId: state.uri.queryParameters['operatorId'],
        ),
      ),
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TripListScreen(),
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this.ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(profileCompleteProvider, (_, __) => notifyListeners());
  }

  final Ref ref;
}
