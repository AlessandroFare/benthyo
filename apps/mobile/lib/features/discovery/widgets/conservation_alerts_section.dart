import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_widget.dart';

final conservationAlertsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token =
      ref.watch(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/users/me/conservation-alerts'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('Failed to load conservation alerts (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  if (body is List) {
    return body.cast<Map<String, dynamic>>();
  }
  return [];
});

class ConservationAlertsSection extends ConsumerWidget {
  const ConservationAlertsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(conservationAlertsProvider);

    return AsyncValueWidget(
      value: alertsAsync,
      isEmpty: (items) => items.isEmpty,
      empty: const SizedBox.shrink(),
      data: (alerts) => Card(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Conservation alerts',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ...alerts.take(3).map(
                    (a) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        a['common_name'] as String? ??
                            a['scientific_name'] as String? ??
                            'Species',
                      ),
                      subtitle: Text(
                        '${a['conservation_status']} · ${a['site_name'] ?? 'Nearby'}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
