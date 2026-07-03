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

final socialFeedProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/feed?limit=40'));
  if (res.statusCode != 200) {
    throw Exception('Failed to load feed (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  return body is List
      ? body.cast<Map<String, dynamic>>()
      : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
});

class SocialFeedScreen extends ConsumerWidget {
  const SocialFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(socialFeedProvider);
    final dateFormat = DateFormat.yMMMd().add_jm();

    return AppScaffold(
      title: 'Dive feed',
      actions: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline),
          onPressed: () => context.push('/messages'),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _composePost(context, ref),
        child: const Icon(Icons.edit),
      ),
      body: AsyncValueWidget(
        value: feedAsync,
        isEmpty: (items) => items.isEmpty,
        empty: const Center(child: Text('No posts yet — share your first dive highlight')),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(socialFeedProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final post = items[index];
              final user = post['user'] as Map<String, dynamic>? ?? {};
              final site = post['site'] as Map<String, dynamic>?;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['full_name'] as String? ??
                            user['username'] as String? ??
                            'Diver',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (site != null)
                        Text(
                          site['name'] as String? ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(post['body'] as String? ?? ''),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        dateFormat.format(
                          DateTime.parse(post['created_at'] as String),
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _composePost(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share dive highlight'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'What did you see today?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (result != true || controller.text.trim().isEmpty) return;

    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/feed'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'body': controller.text.trim()}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Post failed (${res.statusCode})');
      }
      ref.invalidate(socialFeedProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Highlight posted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post: $e')),
        );
      }
    }
  }
}
