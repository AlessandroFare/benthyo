import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/offline/sync_manager.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../auth/auth_providers.dart';
import '../sync/dead_letter_banner.dart';
import 'profile_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _gbifOptIn;
  bool? _digestOptIn;
  bool? _conservationOptIn;
  bool _prefsLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) return;
    final row = await ref.read(supabaseClientProvider).from('users').select(
          'gbif_export_opt_in, weekly_digest_opt_in, conservation_alerts_opt_in',
        ).eq('id', user.id).maybeSingle();
    if (row != null && mounted) {
      setState(() {
        _gbifOptIn = row['gbif_export_opt_in'] as bool? ?? false;
        _digestOptIn = row['weekly_digest_opt_in'] as bool? ?? true;
        _conservationOptIn = row['conservation_alerts_opt_in'] as bool? ?? true;
        _prefsLoading = false;
      });
    }
  }

  Future<void> _patchPref(String field, bool value) async {
    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;
    await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/users/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({field: value}),
    );
    ref.invalidate(userProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider);
    final pendingAsync = ref.watch(pendingSyncCountProvider);
    final pendingItemsAsync = ref.watch(pendingSyncItemsProvider);

    return AppScaffold(
      title: 'Settings',
      body: ListView(
        children: [
          const DeadLetterBanner(),
          const SectionHeader(title: 'Appearance'),
          RadioGroup<AppThemeMode>(
            groupValue: themeMode,
            onChanged: (mode) {
              if (mode != null) {
                ref.read(settingsProvider.notifier).setThemeMode(mode);
              }
            },
            child: Column(
              children: AppThemeMode.values
                  .map(
                    (mode) => RadioListTile<AppThemeMode>(
                      key: ValueKey('theme_${mode.name}'),
                      title: Text(
                        mode.name[0].toUpperCase() + mode.name.substring(1),
                      ),
                      value: mode,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const Divider(),
          const SectionHeader(title: 'Offline sync'),
          AsyncValueWidget(
            value: pendingAsync,
            data: (count) => ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Pending changes'),
              subtitle: Text('$count items in queue'),
              trailing: SizedBox(
                width: 96,
                child: ElevatedButton(
                  onPressed: count == 0
                      ? null
                      : () async {
                          final synced =
                              await ref.read(syncManagerProvider).syncPending();
                          ref.invalidate(pendingSyncCountProvider);
                          ref.invalidate(pendingSyncItemsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Synced $synced items')),
                            );
                          }
                        },
                  child: const Text('Sync now'),
                ),
              ),
            ),
          ),
          AsyncValueWidget(
            value: pendingItemsAsync,
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return Column(
                children: items
                    .map(
                      (item) => ListTile(
                        dense: true,
                        leading: Icon(
                          item.type == SyncEntityType.diveLog
                              ? Icons.book
                              : Icons.visibility,
                        ),
                        title: Text(
                          item.type == SyncEntityType.diveLog
                              ? 'Dive log'
                              : 'Sighting',
                        ),
                        subtitle: Text(
                          'Queued ${item.createdAt.toLocal()} · '
                          '${item.operation.name}',
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const Divider(),
          const SectionHeader(title: 'Notifications & data'),
          if (!_prefsLoading) ...[
            SwitchListTile(
              title: const Text('Weekly email digest'),
              value: _digestOptIn ?? true,
              onChanged: (v) {
                setState(() => _digestOptIn = v);
                _patchPref('weekly_digest_opt_in', v);
              },
            ),
            SwitchListTile(
              title: const Text('Conservation alerts'),
              subtitle: const Text('CR/EN species near your dive regions'),
              value: _conservationOptIn ?? true,
              onChanged: (v) {
                setState(() => _conservationOptIn = v);
                _patchPref('conservation_alerts_opt_in', v);
              },
            ),
            SwitchListTile(
              title: const Text('GBIF export opt-in'),
              subtitle: const Text('Share verified sightings with GBIF'),
              value: _gbifOptIn ?? false,
              onChanged: (v) {
                setState(() => _gbifOptIn = v);
                _patchPref('gbif_export_opt_in', v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Push GBIF export now'),
              onTap: () async {
                final token = ref
                    .read(supabaseClientProvider)
                    .auth
                    .currentSession
                    ?.accessToken;
                if (token == null) return;
                final res = await http.post(
                  Uri.parse('${ApiConfig.baseUrl}/users/me/gbif-export'),
                  headers: {'Authorization': 'Bearer $token'},
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        res.statusCode >= 200 && res.statusCode < 300
                            ? 'Export batch queued'
                            : 'Enable GBIF opt-in first',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
          const Divider(),
          const SectionHeader(title: 'Tools'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Quick log dive'),
            onTap: () => context.push('/dive-logs/quick'),
          ),
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Scan certification card'),
            onTap: () => context.push('/cert-card'),
          ),
          ListTile(
            leading: const Icon(Icons.quiz),
            title: const Text('Species ID quiz'),
            onTap: () => context.push('/species/quiz'),
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('BLE dive computer sync'),
            onTap: () => context.push('/dive-logs/ble'),
          ),
          ListTile(
            leading: const Icon(Icons.dynamic_feed),
            title: const Text('Dive social feed'),
            onTap: () => context.push('/feed'),
          ),
          ListTile(
            leading: const Icon(Icons.storefront),
            title: const Text('Operator marketplace'),
            onTap: () => context.push('/marketplace'),
          ),
          const Divider(),
          const SectionHeader(title: 'Onboarding'),
          ListTile(
            leading: const Icon(Icons.waving_hand),
            title: const Text('Show onboarding intro'),
            subtitle: const Text('Replay the welcome cards'),
            onTap: () => context.push('/onboarding'),
          ),
          const Divider(),
          const SectionHeader(title: 'Data export'),
          ListTile(
            leading: const Icon(Icons.science),
            title: const Text('Darwin Core export'),
            subtitle: const Text(
              'GBIF export runs on a server schedule (not from the app)',
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Verified sightings are exported nightly by the '
                    'darwin-core-export Edge Function for GBIF. '
                    'Operators can download CSV from Supabase Functions logs.',
                  ),
                  duration: Duration(seconds: 6),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.medical_information),
            title: const Text('Medical statement'),
            onTap: () => context.push('/medical'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Benthyo'),
            subtitle: const Text('Version 1.0.0'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Benthyo',
              applicationVersion: '1.0.0',
              applicationLegalese:
                  'B2B-anchored citizen-science platform for scuba diving.\n'
                  'MIT license.',
              children: const [
                SizedBox(height: 12),
                Text(
                  'Benthyo lets you log dives, discover sites, and record '
                  'marine species sightings — data that feeds a GBIF-exportable '
                  'observation layer with contributor attribution.',
                ),
              ],
            ),
          ),
          const Divider(),
          const SectionHeader(title: 'Account'),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Download my data (GDPR)'),
            subtitle: const Text('Receive a JSON file with everything we store about you'),
            onTap: () => _downloadData(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text(
              'Delete my account',
              style: TextStyle(color: Colors.redAccent),
            ),
            subtitle: const Text(
              'Permanently removes your account, sightings, and dive logs.',
            ),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) return;
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/users/me/export'),
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    if (!context.mounted) return;
    if (res.statusCode == 200) {
      await Clipboard.setData(ClipboardData(text: res.body));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Export ready — copied to clipboard (paste to save)'),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: HTTP ${res.statusCode}')),
      );
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete your account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This is permanent. All your dives, sightings, photos, and '
                'personal data will be removed from Benthyo.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Type DELETE to confirm:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: confirmController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'DELETE',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  Navigator.of(ctx).pop(confirmController.text.trim()),
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );

    if (result == null || result != 'DELETE') return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) return;
    final res = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/users/me'),
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'confirm': 'DELETE MY ACCOUNT'}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Sign out and send the user back to the login screen.
      await ref.read(supabaseClientProvider).auth.signOut();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
      context.go('/login');
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Deletion failed: HTTP ${res.statusCode}')),
      );
    }
  }
}
