import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';

class CertCardScanScreen extends ConsumerStatefulWidget {
  const CertCardScanScreen({super.key});

  @override
  ConsumerState<CertCardScanScreen> createState() => _CertCardScanScreenState();
}

class _CertCardScanScreenState extends ConsumerState<CertCardScanScreen> {
  final _textController = TextEditingController();
  Map<String, dynamic>? _parsed;
  bool _loading = false;

  Future<void> _parse() async {
    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/cert-cards/parse'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'raw_text': _textController.text}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _parsed = jsonDecode(res.body) as Map<String, dynamic>);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final token =
        ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) return;

    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/cert-cards'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'raw_text': _textController.text}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.statusCode >= 200 && res.statusCode < 300
                  ? 'Certification saved'
                  : 'Could not save certification',
            ),
          ),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          Navigator.pop(context);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Scan cert card',
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const Text(
            'Paste OCR text from your PADI/SSI card photo, or type cert details.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _textController,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Card text',
              hintText: 'PADI Open Water Diver\nCert No: 12345678',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _loading ? null : _parse,
            child: const Text('Parse fields'),
          ),
          if (_parsed != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Agency: ${_parsed!['agency'] ?? '—'}'),
            Text('Level: ${_parsed!['cert_level'] ?? '—'}'),
            Text('Number: ${_parsed!['cert_number'] ?? '—'}'),
            Text('Instructor: ${_parsed!['instructor_name'] ?? '—'}'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _loading ? null : _save,
              child: const Text('Save to profile'),
            ),
          ],
        ],
      ),
    );
  }
}
