import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final availableSlotsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final token = supabase.auth.currentSession?.accessToken;
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final headers = <String, String>{};
  if (token != null) headers['Authorization'] = 'Bearer $token';

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/public/slots?from_date=$today'),
    headers: headers,
  );
  if (res.statusCode != 200) return [];
  final body = jsonDecode(res.body) as Map<String, dynamic>?;
  final list = body?['data'] as List<dynamic>? ?? (body != null ? [body] : []);
  return list.cast<Map<String, dynamic>>();
});

class SlotBrowserScreen extends ConsumerWidget {
  const SlotBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotsAsync = ref.watch(availableSlotsProvider);

    return AppScaffold(
      title: 'Book a dive',
      body: AsyncValueWidget(
        value: slotsAsync,
        isEmpty: (slots) => slots.isEmpty,
        empty: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 48, color: AppColors.textSecondary),
              SizedBox(height: AppSpacing.md),
              Text('No available slots right now'),
            ],
          ),
        ),
        data: (slots) => ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            final operator = slot['operator'] as Map<String, dynamic>? ?? {};
            final site = slot['dive_site'] as Map<String, dynamic>?;
            final priceCents = slot['price_cents'] as int? ?? 0;
            final currency = slot['currency'] as String? ?? 'eur';
            final tripDate = slot['trip_date'] as String? ?? '';
            final departAt = slot['depart_at'] as String?;
            final maxCap = slot['max_capacity'] as int? ?? 0;
            final booked = slot['booked_count'] as int? ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site?['name'] as String? ?? slot['site_label'] as String? ?? 'Dive site',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(operator['name'] as String? ?? 'Operator'),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      DateFormat.yMMMd().format(DateTime.parse(tripDate)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (departAt != null)
                      Text(
                        'Depart: ${departAt.split('T')[1].substring(0, 5)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(_formatPrice(priceCents, currency))} · $booked/$maxCap booked',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        FilledButton.tonal(
                          onPressed: booked >= maxCap ? null : () => context.push('/book/${slot['id']}'),
                          child: Text(booked >= maxCap ? 'Full' : 'Book'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatPrice(int cents, String currency) {
    final symbol = currency == 'eur' ? '\u20AC' : currency == 'usd' ? '\$' : '$currency ';
    return '$symbol${(cents / 100).toStringAsFixed(2)}';
  }
}
