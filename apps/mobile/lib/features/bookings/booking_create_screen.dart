import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';

class BookingCreateScreen extends ConsumerStatefulWidget {
  const BookingCreateScreen({super.key, required this.slotId});

  final String slotId;

  @override
  ConsumerState<BookingCreateScreen> createState() => _BookingCreateScreenState();
}

class _BookingCreateScreenState extends ConsumerState<BookingCreateScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _book() async {
    final token = ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) {
      context.go('/login');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/bookings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'slot_id': widget.slotId}),
      );

      if (res.statusCode >= 400) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _error = body['message'] as String? ?? 'Booking failed');
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final stripeData = data['stripe'] as Map<String, dynamic>?;

      if (stripeData != null && stripeData['client_secret'] != null) {
        setState(() => _result = {'stripe': stripeData, 'booking_id': data['booking_id']});
      } else {
        setState(() => _result = {'confirmed': true, 'booking_id': data['booking_id']});
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Confirm booking',
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.scuba_diving, size: 64, color: AppColors.accent),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Ready to book this dive?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Your spot will be reserved. Payment is processed securely via Stripe.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_result != null) ...[
              const Icon(Icons.check_circle, size: 64, color: AppColors.success),
              const SizedBox(height: AppSpacing.md),
              const Text('Booking confirmed!', textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => context.go('/bookings'),
                child: const Text('View my bookings'),
              ),
            ] else ...[
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.error)),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton(
                onPressed: _loading ? null : _book,
                child: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm & pay'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
