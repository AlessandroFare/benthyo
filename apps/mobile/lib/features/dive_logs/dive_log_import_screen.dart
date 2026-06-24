import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../dive_logs/dive_logs_providers.dart';

class DiveLogImportScreen extends ConsumerStatefulWidget {
  const DiveLogImportScreen({super.key});

  @override
  ConsumerState<DiveLogImportScreen> createState() =>
      _DiveLogImportScreenState();
}

class _DiveLogImportScreenState extends ConsumerState<DiveLogImportScreen> {
  bool _loading = false;
  String? _result;

  Future<void> _pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['uddf', 'xml', 'udcf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      setState(() => _result = 'Could not read file bytes');
      return;
    }

    final xml = utf8.decode(bytes);
    final token = ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
    if (token == null) {
      setState(() => _result = 'Sign in to import dives');
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    const apiBase = String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:3000/api/v1',
    );

    try {
      final res = await http.post(
        Uri.parse('$apiBase/dive-logs/import/uddf'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'xml': xml}),
      );

      if (res.statusCode >= 400) {
        setState(() => _result = 'Import failed: ${res.body}');
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final imported = (body['imported'] as int?) ??
            ((body['data'] as Map<String, dynamic>?)?['imported'] as int?) ??
            0;
        ref.invalidate(diveLogsProvider);
        setState(() => _result = 'Imported $imported dives from dive computer');
      }
    } catch (e) {
      setState(() => _result = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Import dives',
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.watch, size: 64, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Dive computer import',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Export UDDF/UDCF from Suunto, Shearwater, Garmin, or MacDive and import your log in one step.',
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _loading ? null : _pickAndImport,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_loading ? 'Importing…' : 'Choose UDDF file'),
            ),
            if (_result != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_result!),
            ],
          ],
        ),
      ),
    );
  }
}
