import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final conversationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token =
      ref.watch(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) return [];

  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/conversations'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('Failed to load conversations (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  return body is List
      ? body.cast<Map<String, dynamic>>()
      : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
});

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final convAsync = ref.watch(conversationsProvider);

    return AppScaffold(
      title: 'Messages',
      body: AsyncValueWidget(
        value: convAsync,
        isEmpty: (items) => items.isEmpty,
        empty: const Center(
          child: Text('No conversations yet — message a buddy from a dive site'),
        ),
        data: (items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final conv = items[index];
            final otherId = conv['participant_a'] == userId
                ? conv['participant_b'] as String
                : conv['participant_a'] as String;
            return ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Conversation'),
              subtitle: Text(
                conv['last_message_at'] != null
                    ? DateTime.parse(conv['last_message_at'] as String).toLocal().toString()
                    : 'No messages yet',
              ),
              onTap: () => context.push('/messages/$otherId?conv=${conv['id']}'),
            );
          },
        ),
      ),
    );
  }
}
