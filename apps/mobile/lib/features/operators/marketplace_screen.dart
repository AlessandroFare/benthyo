import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final marketplaceListingsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/marketplace/listings'));
  if (res.statusCode != 200) {
    throw Exception('Failed to load marketplace listings (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  return body is List
      ? body.cast<Map<String, dynamic>>()
      : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
});

class MarketplaceScreen extends ConsumerWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);

    return AppScaffold(
      title: 'Marketplace',
      body: AsyncValueWidget(
        value: listingsAsync,
        isEmpty: (items) => items.isEmpty,
        empty: const Center(child: Text('No listings yet')),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            final op = item['operator'] as Map<String, dynamic>? ?? {};
            final price = (item['price_cents'] as num? ?? 0) / 100;
            final currency = item['currency'] as String? ?? 'EUR';
            return ListTile(
              title: Text(item['title'] as String? ?? ''),
              subtitle: Text(
                '${op['name'] ?? 'Operator'} · ${item['listing_type']} · '
                '${item['region'] ?? op['country_code'] ?? ''}',
              ),
              trailing: Text('$currency ${price.toStringAsFixed(0)}'),
              onTap: () => _showDetail(context, item),
            );
          },
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> item) {
    final op = item['operator'] as Map<String, dynamic>? ?? {};
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item['title'] as String? ?? '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(op['name'] as String? ?? ''),
            const SizedBox(height: AppSpacing.md),
            Text(item['description'] as String? ?? ''),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () {
                final slug = op['slug'] as String?;
                if (slug != null) context.push('/operators/${op['id']}');
                Navigator.pop(ctx);
              },
              child: const Text('View operator'),
            ),
          ],
        ),
      ),
    );
  }
}
