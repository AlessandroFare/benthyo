import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../medical/medical_form_screen.dart';

final tripDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, tripId) async {
  final token =
      ref.watch(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) return null;
  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/trips/$tripId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return body['data'] as Map<String, dynamic>? ?? body;
});

final tripRecapProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, tripId) async {
  final token =
      ref.watch(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) return null;
  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/trips/$tripId/recap'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return body['data'] as Map<String, dynamic>? ?? body;
});

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final recapAsync = ref.watch(tripRecapProvider(tripId));
    final dateFormat = DateFormat.yMMMd();

    return AppScaffold(
      title: 'Trip',
      body: AsyncValueWidget(
        value: tripAsync,
        data: (trip) {
          if (trip == null) {
            return const Center(child: Text('Trip not found'));
          }
          final start = DateTime.parse(trip['start_date'] as String);
          final end = DateTime.parse(trip['end_date'] as String);
          final members = trip['members'] as List<dynamic>? ?? [];
          final sites = trip['sites'] as List<dynamic>? ?? [];

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                trip['name'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${dateFormat.format(start)} – ${dateFormat.format(end)}'
                '${trip['region'] != null ? ' · ${trip['region']}' : ''}',
              ),
              const SizedBox(height: AppSpacing.md),
              AsyncValueWidget(
                value: recapAsync,
                data: (recap) {
                  if (recap == null) return const SizedBox.shrink();
                  final text =
                      'Trip to ${recap['name']}: ${recap['dive_count']} dives, '
                      '${recap['species_count']} species, '
                      '${recap['new_life_list']} new for life list'
                      '${recap['max_depth_m'] != null ? ', deepest ${recap['max_depth_m']}m' : ''}.';
                  return Card(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip recap',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(text),
                          const SizedBox(height: AppSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: () => Share.share(text),
                            icon: const Icon(Icons.share),
                            label: const Text('Share recap'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Members (${members.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...members.map((m) {
                final user = m['user'] as Map<String, dynamic>? ?? {};
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    user['full_name'] as String? ??
                        user['username'] as String? ??
                        '?',
                  ),
                  subtitle: Text(
                    'Waiver: ${m['waiver_signed'] == true ? '✓' : 'pending'} · '
                    'Medical: ${m['medical_complete'] == true ? '✓' : 'pending'}',
                  ),
                );
              }),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Sites (${sites.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...sites.map((s) {
                final site = s['site'] as Map<String, dynamic>? ?? {};
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(site['name'] as String? ?? 'Site'),
                );
              }),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(
                          '${ApiConfig.baseUrl}/trips/$tripId/calendar.ics',
                        );
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Add to calendar'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _inviteMember(context, ref),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Invite'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MedicalFormScreen(tripId: tripId),
                  ),
                ),
                icon: const Icon(Icons.medical_information),
                label: const Text('Complete medical form'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _inviteMember(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite diver'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Invite'),
          ),
        ],
      ),
    );
    if (username == null || username.isEmpty) return;

    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/trips/$tripId/members'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'username': username}),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.statusCode >= 200 && res.statusCode < 300
                ? 'Invited @$username'
                : 'Could not invite user',
          ),
        ),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ref.invalidate(tripDetailProvider(tripId));
      }
    }
  }
}
