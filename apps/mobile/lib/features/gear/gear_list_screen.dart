import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final gearItemsProvider = FutureProvider<List<GearItem>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final token = supabase.auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/gear'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) throw Exception('Failed to load gear');
  final body = jsonDecode(res.body);
  final list = body is List ? body : (body['data'] as List<dynamic>? ?? []);
  return list
      .map((e) => GearItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

final gearServiceDueProvider = FutureProvider<List<GearItem>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final token = supabase.auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/gear/service-due'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('Failed to load service-due gear (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  final list = body is List ? body : (body['data'] as List<dynamic>? ?? []);
  return list
      .map((e) => GearItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

class GearItem {
  const GearItem({
    required this.id,
    required this.name,
    required this.gearType,
    this.divesSinceService = 0,
    this.serviceDueSoon = false,
  });

  final String id;
  final String name;
  final String gearType;
  final int divesSinceService;
  final bool serviceDueSoon;

  factory GearItem.fromJson(Map<String, dynamic> json) => GearItem(
        id: json['id'] as String,
        name: json['name'] as String,
        gearType: json['gear_type'] as String,
        divesSinceService: (json['dives_since_service'] as num?)?.toInt() ?? 0,
        serviceDueSoon: false,
      );
}

class GearListScreen extends ConsumerWidget {
  const GearListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gearAsync = ref.watch(gearItemsProvider);
    final dueAsync = ref.watch(gearServiceDueProvider);

    return AppScaffold(
      title: 'Gear',
      body: Column(
        children: [
          AsyncValueWidget(
            value: dueAsync,
            isEmpty: (items) => items.isEmpty,
            empty: const SizedBox.shrink(),
            data: (due) => MaterialBanner(
              content: Text('${due.length} item(s) due for service'),
              leading: const Icon(Icons.build, color: AppColors.accent),
              actions: const [SizedBox.shrink()],
            ),
          ),
          Expanded(
            child: AsyncValueWidget(
              value: gearAsync,
              isEmpty: (items) => items.isEmpty,
              empty: const Center(
                child: Text('No gear tracked yet. Add your BCD, regs, wetsuit…'),
              ),
              data: (items) => ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: const Icon(Icons.scuba_diving),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.gearType} · ${item.divesSinceService} dives since service',
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddGear(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddGear(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add gear'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != true || nameController.text.trim().isEmpty) return;

    final supabase = ref.read(supabaseClientProvider);
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) return;

    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/gear'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'gear_type': 'other',
        'name': nameController.text.trim(),
      }),
    );
    ref.invalidate(gearItemsProvider);
    ref.invalidate(gearServiceDueProvider);
  }
}
