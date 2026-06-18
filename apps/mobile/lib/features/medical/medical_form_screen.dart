import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final medicalTemplateProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/medical/template'));
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return body['data'] as Map<String, dynamic>? ?? body;
});

class MedicalFormScreen extends ConsumerStatefulWidget {
  const MedicalFormScreen({super.key, this.tripId, this.operatorId});

  final String? tripId;
  final String? operatorId;

  @override
  ConsumerState<MedicalFormScreen> createState() => _MedicalFormScreenState();
}

class _MedicalFormScreenState extends ConsumerState<MedicalFormScreen> {
  final _nameController = TextEditingController();
  final Map<String, bool> _answers = {};
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit(String templateId, List<dynamic> questions) async {
    setState(() => _submitting = true);
    try {
      final token =
          ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
      if (token == null) throw Exception('Sign in required');

      final answers = questions.map((q) {
        final map = q as Map<String, dynamic>;
        final id = map['id'] as String;
        return {'id': id, 'value': _answers[id] ?? false};
      }).toList();

      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/medical/submit'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'template_id': templateId,
          'signer_name': _nameController.text.trim(),
          if (widget.tripId != null) 'trip_id': widget.tripId,
          if (widget.operatorId != null) 'operator_id': widget.operatorId,
          'answers': answers,
        }),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Submit failed');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medical form signed')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templateAsync = ref.watch(medicalTemplateProvider);

    return AppScaffold(
      title: 'Medical statement',
      body: AsyncValueWidget(
        value: templateAsync,
        data: (template) {
          if (template == null) {
            return const Center(child: Text('Template unavailable'));
          }
          final questions = template['schema'] as List<dynamic>? ?? [];
          final hasYes = _answers.values.any((v) => v);

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                template['title'] as String? ?? 'Medical statement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Answer honestly. Any "yes" means consult a dive physician before diving.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              ...questions.map((q) {
                final map = q as Map<String, dynamic>;
                final id = map['id'] as String;
                return SwitchListTile(
                  title: Text(map['text'] as String? ?? id),
                  value: _answers[id] ?? false,
                  onChanged: (v) => setState(() => _answers[id] = v),
                );
              }),
              if (hasYes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'You answered yes to at least one question — see a dive doctor before diving.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _submitting || _nameController.text.trim().length < 2
                    ? null
                    : () => _submit(template['id'] as String, questions),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign & submit'),
              ),
            ],
          );
        },
      ),
    );
  }
}
