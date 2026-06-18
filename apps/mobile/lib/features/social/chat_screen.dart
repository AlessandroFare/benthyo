import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.recipientId,
    this.conversationId,
  });

  final String recipientId;
  final String? conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _conversationId;
  RealtimeChannel? _channel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _resolveConversationId();
    await _loadMessages();
    _subscribeRealtime();
  }

  Future<void> _resolveConversationId() async {
    if (_conversationId != null) return;

    final supabase = ref.read(supabaseClientProvider);
    final me = supabase.auth.currentUser?.id;
    if (me == null) return;

    final other = widget.recipientId;
    final a = me.compareTo(other) < 0 ? me : other;
    final b = me.compareTo(other) < 0 ? other : me;

    final row = await supabase
        .from('buddy_conversations')
        .select('id')
        .eq('participant_a', a)
        .eq('participant_b', b)
        .maybeSingle();

    if (row != null && mounted) {
      setState(() => _conversationId = row['id'] as String);
    }
  }

  Future<void> _loadMessages() async {
    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null || _conversationId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/conversations/$_conversationId/messages'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200 && mounted) {
      final body = jsonDecode(res.body);
      final list = body is List ? body : (body['data'] as List<dynamic>? ?? []);
      setState(() {
        _messages = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
      _scrollToBottom();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    final convId = _conversationId;
    if (convId == null) return;

    final supabase = ref.read(supabaseClientProvider);
    _channel?.unsubscribe();

    _channel = supabase
        .channel('buddy-chat-$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'buddy_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty) return;

            final id = record['id'] as String?;
            if (id != null && _messages.any((m) => m['id'] == id)) return;

            setState(() {
              _messages = [..._messages, Map<String, dynamic>.from(record)];
            });
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/messages'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'recipient_id': widget.recipientId,
        'body': text,
      }),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      _controller.clear();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? body;
      final convId = data['conversation_id'] as String?;

      if (convId != null && convId != _conversationId) {
        setState(() => _conversationId = convId);
        _subscribeRealtime();
      }

      // Realtime delivers the insert; fallback reload if channel not ready.
      if (_channel == null) await _loadMessages();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(supabaseClientProvider).auth.currentUser?.id;

    return AppScaffold(
      title: 'Chat',
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final mine = msg['sender_id'] == me;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(msg['body'] as String? ?? ''),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
