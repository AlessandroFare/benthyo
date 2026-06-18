// Flutter's Material library exports a `Badge` widget; the project also
// defines a domain `Badge` model in core/models/life_list.dart. We hide
// Material's `Badge` here and import our own model under the `Badge` name.
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/life_list.dart';
import '../../core/supabase/supabase_client.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<List<UserBadge>> fetchBadges(String userId) async {
    final data = await _client
        .from('user_badges')
        .select('*, badges(*)')
        .eq('user_id', userId)
        .order('earned_at', ascending: false);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(UserBadge.fromJson).toList();
  }

  Future<Badge?> fetchBadgeById(String badgeId) async {
    final data =
        await _client.from('badges').select().eq('id', badgeId).maybeSingle();
    if (data == null) return null;
    return Badge.fromJson(data);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final userBadgesProvider = FutureProvider<List<UserBadge>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(profileRepositoryProvider).fetchBadges(user.id);
});

final badgeProvider = FutureProvider.family<Badge?, String>((ref, id) {
  return ref.watch(profileRepositoryProvider).fetchBadgeById(id);
});

enum AppThemeMode { system, light, dark }

class SettingsNotifier extends StateNotifier<AppThemeMode> {
  SettingsNotifier() : super(AppThemeMode.system) {
    _load();
  }

  static const _key = 'theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value != null) {
      state = AppThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AppThemeMode.system,
      );
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppThemeMode>((ref) {
  return SettingsNotifier();
});

final appThemeModeProvider = Provider<ThemeMode>((ref) {
  final setting = ref.watch(settingsProvider);
  return switch (setting) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };
});
