import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';

class WaiverSignScreen extends ConsumerStatefulWidget {
  const WaiverSignScreen({super.key, required this.operatorSlug});

  final String operatorSlug;

  @override
  ConsumerState<WaiverSignScreen> createState() => _WaiverSignScreenState();
}

class _WaiverSignScreenState extends ConsumerState<WaiverSignScreen> {
  final _nameController = TextEditingController();
  bool _agreed = false;
  bool _loading = true;
  bool _signing = false;
  String? _error;
  Map<String, dynamic>? _waiver;
  Map<String, dynamic>? _operator;

  @override
  void initState() {
    super.initState();
    _loadWaiver();
  }

  Future<void> _loadWaiver() async {
    final apiBase = const String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:3000/api/v1',
    );
    try {
      final res = await http.get(
        Uri.parse('$apiBase/waivers/operator/${widget.operatorSlug}'),
      );
      if (res.statusCode >= 400) {
        setState(() => _error = 'Waiver not available');
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] ?? body;
        setState(() {
          _operator = data['operator'] as Map<String, dynamic>?;
          _waiver = data['waiver'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sign() async {
    final waiverId = _waiver?['id'] as String?;
    final token = ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (waiverId == null || token == null) {
      setState(() => _error = 'Sign in to complete the waiver');
      return;
    }

    setState(() {
      _signing = true;
      _error = null;
    });

    final apiBase = const String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:3000/api/v1',
    );

    try {
      final res = await http.post(
        Uri.parse('$apiBase/waivers/sign'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'waiver_id': waiverId,
          'signer_name': _nameController.text.trim(),
        }),
      );
      if (res.statusCode >= 400) {
        setState(() => _error = 'Could not sign waiver');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waiver signed successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _signing = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Digital waiver',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _waiver == null
              ? Center(child: Text(_error ?? 'No active waiver'))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      _operator?['name'] as String? ?? widget.operatorSlug,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(_waiver!['title'] as String? ?? 'Liability waiver'),
                    const SizedBox(height: AppSpacing.md),
                    Text(_waiver!['body'] as String? ?? ''),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full legal name',
                      ),
                    ),
                    CheckboxListTile(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      title: const Text('I have read and agree to this waiver'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: _signing || !_agreed
                          ? null
                          : () {
                              if (_nameController.text.trim().length < 2) {
                                setState(() => _error = 'Enter your full name');
                                return;
                              }
                              _sign();
                            },
                      child: Text(_signing ? 'Signing…' : 'Sign waiver'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
    );
  }
}
