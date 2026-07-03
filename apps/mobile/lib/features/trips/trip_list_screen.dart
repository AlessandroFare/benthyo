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

final tripsProvider = FutureProvider<List<TripSummary>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final token = supabase.auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/trips'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) throw Exception('Failed to load trips');
  final body = jsonDecode(res.body) as dynamic;
  final list = body is List ? body : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ?? []);
  return list
      .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
      .toList();
});

class TripSummary {
  const TripSummary({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.region,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String? region;

  factory TripSummary.fromJson(Map<String, dynamic> json) => TripSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        region: json['region'] as String?,
      );
}

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsProvider);
    final dateFormat = DateFormat.yMMMd();

    return AppScaffold(
      title: 'Trips',
      body: AsyncValueWidget(
        value: tripsAsync,
        isEmpty: (trips) => trips.isEmpty,
        empty: const Center(
          child: Text(
            'Plan a group trip — collect waivers, share itinerary, track gear.',
          ),
        ),
        data: (trips) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: trips.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final trip = trips[index];
            return ListTile(
              title: Text(trip.name),
              subtitle: Text(
                '${dateFormat.format(trip.startDate)} – ${dateFormat.format(trip.endDate)}'
                '${trip.region != null ? ' · ${trip.region}' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/trips/${trip.id}'),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createTrip(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createTrip(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController(text: 'Dive trip');
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 7);
    final end = start.add(const Duration(days: 6));

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New trip'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Trip name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result != true) return;

    final supabase = ref.read(supabaseClientProvider);
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) return;

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/trips'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': nameController.text.trim(),
        'start_date': start.toIso8601String().split('T').first,
        'end_date': end.toIso8601String().split('T').first,
      }),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      ref.invalidate(tripsProvider);
    }
  }
}
