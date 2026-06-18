/// Supabase client, Riverpod providers, and offline-sync helpers
/// for the OceanLog mobile app.
///
/// All features import their Supabase / auth / sync state from this file:
///   - `initializeSupabase()`           called once from main()
///   - `supabaseClientProvider`        SupabaseClient singleton
///   - `authStateProvider`             `Stream<AuthState>`
///   - `currentUserProvider`           `User?` (current session user)
///   - `isAuthenticatedProvider`       `bool`
///   - `syncManagerProvider`           SyncManager singleton
///   - `isOnlineProvider`              `Future<bool>` (cached)
///   - `pendingSyncCountProvider`      `Future<int>`
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../offline/sync_manager.dart';

// ---------------------------------------------------------------------------
// Supabase bootstrap
// ---------------------------------------------------------------------------

/// Pulls the Supabase URL + publishable (anon) key from `--dart-define`
/// flags. Sensible defaults point at the local Supabase dev stack that
/// `supabase start` boots.
///
/// Use:
///
///     flutter run \
///       --dart-define=SUPABASE_URL=... \
///       --dart-define=SUPABASE_PUBLISHABLE_KEY=...
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  /// Public / publishable key. In Supabase this is also called the "anon"
  /// key historically — the same JWT, just renamed in supabase_flutter 2.14+
  /// for parity with other services (Clerk, Auth0, etc.). The legacy
  /// `--dart-define=SUPABASE_ANON_KEY=...` name still works as a fallback so
  /// existing CI scripts don't need to change.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  );

  /// Back-compat alias for callers / CI scripts that still pass the old
  /// dart-define name.
  static const String _legacyAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Effective key to pass to the SDK (legacy takes precedence only if it
  /// was explicitly set, so the default above remains the dev fallback).
  static String get effectivePublishableKey =>
      _legacyAnonKey.isNotEmpty ? _legacyAnonKey : publishableKey;

  static String get debugLabel =>
      '${url.replaceAll(RegExp(r'https?://'), '').split('/').first} '
      '(${effectivePublishableKey.length > 12 ? effectivePublishableKey.substring(0, 12) : effectivePublishableKey}…)';
}

bool _supabaseInitialized = false;

/// Initialise the Supabase SDK. Safe to call more than once.
Future<void> initializeSupabase() async {
  if (_supabaseInitialized) return;
  // `supabase_flutter` 2.14 exposes both `publishableKey` (preferred) and
  // the older `anonKey` (deprecated). We always pass `publishableKey`.
  await sb.Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.effectivePublishableKey,
    authOptions: const sb.FlutterAuthClientOptions(
      authFlowType: sb.AuthFlowType.pkce,
    ),
  );
  if (kDebugMode) {
    debugPrint('[supabase] ${SupabaseConfig.debugLabel}');
  }
  _supabaseInitialized = true;
}

/// Top-level convenience getter for the raw client (kept for back-compat
/// with the original file).
sb.SupabaseClient get supabase => sb.Supabase.instance.client;
String? get accessToken =>
    sb.Supabase.instance.client.auth.currentSession?.accessToken;

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// Singleton Supabase client.
final supabaseClientProvider = Provider<sb.SupabaseClient>((ref) {
  return sb.Supabase.instance.client;
});

/// Live auth-state stream from Supabase. The router listens to this to
/// re-evaluate redirects.
final authStateProvider = StreamProvider<sb.AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// The currently signed-in user (or null if signed out / loading).
final currentUserProvider = Provider<sb.User?>((ref) {
  // Watch the auth state stream so the router rebuilds when it changes.
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

/// True when a user is currently signed in.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

// ---------------------------------------------------------------------------
// Offline sync
// ---------------------------------------------------------------------------

/// Singleton SyncManager (uses sqflite under the hood).
final syncManagerProvider = Provider<SyncManager>((ref) {
  final mgr = SyncManager.instance;
  // Whenever the auth state changes, refresh the bearer token so HTTP
  // requests during sync are authenticated.
  ref.listen(authStateProvider, (_, __) {
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    mgr.configure(
      apiBase: const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:3000/api/v1',
      ),
      accessToken: session?.accessToken,
    );
  });
  // Configure once with the current session (if any).
  final session = ref.read(supabaseClientProvider).auth.currentSession;
  mgr.configure(
    apiBase: const String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:3000/api/v1',
    ),
    accessToken: session?.accessToken,
  );
  return mgr;
});

/// Cached "are we online?" check. Invalidated by [connectivityProvider].
final isOnlineProvider = FutureProvider<bool>((ref) async {
  return ref.read(syncManagerProvider).isOnline();
});

/// Live stream of OS-level connectivity transitions.
///
/// Watches `Connectivity().onConnectivityChanged` and exposes the most
/// recent result. Use [isOnlineStreamProvider] for a derived `bool` stream
/// that you can `ref.listen` to.
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) {
    return Connectivity().onConnectivityChanged;
  },
);

/// Convenience: `true` when we currently report *any* non-none connectivity.
final isOnlineStreamProvider = Provider<AsyncValue<bool>>((ref) {
  return ref.watch(connectivityStreamProvider).whenData(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );
});

/// Count of items currently waiting in the offline sync queue.
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  return ref.read(syncManagerProvider).pendingCount();
});

/// Detailed offline queue for settings UI.
final pendingSyncItemsProvider = FutureProvider<List<SyncQueueItem>>((ref) async {
  return ref.read(syncManagerProvider).pendingItems();
});

/// Auto-sync coordinator.
///
/// The spec (docs/architecture.md, "Offline sync path") requires that on
/// connectivity restore the queue drains automatically. This provider
/// wires that up: it subscribes to both the connectivity stream and the
/// auth-state stream and kicks `SyncManager.syncPending()` whenever we
/// transition from offline to online *and* the user is signed in.
///
/// **Web note:** the offline queue is a no-op on web (`SyncManager` uses
/// an in-memory backend there). Connectivity changes are still tracked
/// but `syncPending` always returns 0 because the in-memory queue is
/// drained immediately by the repository's own "queue if offline" path.
/// We therefore no-op the whole coordinator on web to avoid the wasted
/// connectivity stream subscription and to keep the Web bundle smaller.
///
/// Place this in the widget tree (typically at the root of `MaterialApp`)
///
/// ```dart
/// ref.watch(autoSyncCoordinatorProvider);
/// ```
///
/// so the subscription is created and torn down with the app's lifetime.
final autoSyncCoordinatorProvider = Provider<void>((ref) {
  if (kIsWeb) {
    // Web: nothing to do. The user is always online; everything goes
    // straight to the API via the repositories' `isOnline` path.
    return;
  }

  var wasOnline = false;

  // Listen to raw connectivity transitions. We use a Stream subscription
  // rather than `ref.listen` because we want the *previous* value too.
  final connectivitySub = Connectivity().onConnectivityChanged.listen(
    (results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (!isOnline) {
        wasOnline = false;
        return;
      }
      if (!wasOnline) {
        wasOnline = true;
        final user = ref.read(currentUserProvider);
        if (user == null) return;
        // Fire-and-forget; failures bump retryCount in SyncManager.
        ref.read(syncManagerProvider).syncPending().then(
              (_) => ref.invalidate(pendingSyncCountProvider),
            );
      }
    },
  );

  // When the user signs in, also drain the queue immediately (covers the
  // "user installed the app, used it offline, came back online, then
  // signed in" path).
  ref.listen(currentUserProvider, (prev, next) {
    if (prev == null && next != null) {
      ref.read(syncManagerProvider).syncPending().then(
            (_) => ref.invalidate(pendingSyncCountProvider),
          );
    }
  });

  ref.onDispose(connectivitySub.cancel);
});

/// Debug helper – logs every Supabase auth change to the console.
void debugAuthListener(Ref ref) {
  if (!kDebugMode) return;
  ref.listen<AsyncValue<sb.AuthState>>(authStateProvider, (prev, next) {
    next.whenData((state) {
      debugPrint(
        '[auth] event=${state.event} '
        'user=${state.session?.user.id ?? 'none'}',
      );
    });
  });
}
