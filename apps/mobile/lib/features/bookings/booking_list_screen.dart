import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final myBookingsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/bookings'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('Failed to load bookings (${res.statusCode})');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>?;
  final list = body?['data'] as List<dynamic>? ?? [];
  return list.cast<Map<String, dynamic>>();
});

class BookingListScreen extends ConsumerWidget {
  const BookingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return AppScaffold(
      title: 'My bookings',
      body: AsyncValueWidget(
        value: bookingsAsync,
        isEmpty: (list) => list.isEmpty,
        empty: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_note, size: 48, color: AppColors.textSecondary),
              SizedBox(height: AppSpacing.md),
              Text('No bookings yet'),
              SizedBox(height: AppSpacing.sm),
              Text('Browse available dive slots to book your next trip.'),
            ],
          ),
        ),
        data: (bookings) => ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final b = bookings[index];
            final slot = b['slot'] as Map<String, dynamic>? ?? {};
            final operator = b['operator'] as Map<String, dynamic>? ?? {};
            final status = b['status'] as String? ?? 'unknown';
            final tripDate = slot['trip_date'] as String? ?? '';
            final siteName = slot['site_label'] as String? ?? 'Dive site';
            final price = b['price_cents'] as int? ?? 0;

            final statusColor = switch (status) {
              'confirmed' => AppColors.success,
              'pending_payment' => AppColors.textSecondary,
              'cancelled' => AppColors.error,
              _ => AppColors.textSecondary,
            };

            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: Icon(Icons.scuba_diving, color: statusColor),
                title: Text(siteName),
                subtitle: Text(
                  '${operator['name'] ?? 'Operator'} · '
                  '${tripDate.isNotEmpty ? DateFormat.yMMMd().format(DateTime.parse(tripDate)) : ''}\n'
                  '${status.replaceAll('_', ' ')} · ${price > 0 ? '\u20AC${(price / 100).toStringAsFixed(2)}' : 'Free'}',
                ),
                trailing: status == 'pending_payment'
                    ? TextButton(
                        onPressed: () => _cancelBooking(context, ref, b['id'] as String),
                        child: const Text('Cancel'),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _cancelBooking(BuildContext context, WidgetRef ref, String bookingId) async {
    final token = ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/cancel'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      ref.invalidate(myBookingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking cancelled')),
        );
      }
    }
  }
}
