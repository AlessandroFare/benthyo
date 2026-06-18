import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/user_profile.dart';
import '../../core/offline/sync_manager.dart';
import '../../core/supabase/supabase_client.dart';

class SignUpResult {
  const SignUpResult({
    required this.needsEmailConfirmation,
    this.user,
  });

  final bool needsEmailConfirmation;
  final User? user;
}

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? username,
    String? fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (username != null) 'username': username,
        if (fullName != null) 'full_name': fullName,
      },
      emailRedirectTo: _authRedirectUrl,
    );

    return SignUpResult(
      needsEmailConfirmation: response.session == null,
      user: response.user,
    );
  }

  Future<void> resendSignupConfirmation(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: _authRedirectUrl,
    );
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _authRedirectUrl,
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async {
    // DD-3.1: clear the offline queue before signing out so the next
    // user on this device doesn't see the previous user's pending items.
    await SyncManager.instance.resetForNewUser();
    await _client.auth.signOut();
  }

  Future<UserProfile?> fetchProfile(String userId) async {
    final data =
        await _client.from('users').select().eq('id', userId).maybeSingle();
    if (data == null) return null;
    return UserProfile.fromJson(data);
  }

  Future<UserProfile> updateProfile({
    required String userId,
    required String username,
    String? fullName,
    String? bio,
    required String certificationLevel,
    required String certificationAgency,
  }) async {
    final data = await _client
        .from('users')
        .update({
          'username': username,
          'full_name': fullName,
          'bio': bio,
          'certification_level': certificationLevel,
          'certification_agency': certificationAgency,
        })
        .eq('id', userId)
        .select()
        .single();
    return UserProfile.fromJson(data);
  }

  /// Where Supabase redirects after email confirmation or OAuth.
  /// On web this must match an entry in Supabase → Authentication → URL configuration.
  static String get _authRedirectUrl {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return const String.fromEnvironment(
      'AUTH_REDIRECT_URL',
      defaultValue: 'io.oceanlog.app://login-callback',
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).fetchProfile(user.id);
});

final profileCompleteProvider = Provider<bool>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile.maybeWhen(
    data: (p) => p?.isProfileComplete ?? false,
    orElse: () => false,
  );
});
