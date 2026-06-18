import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';

Future<void> showSuggestCorrectionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String sightingId,
  required String proposedSpeciesId,
}) async {
  final reasonController = TextEditingController(text: 'Likely mis-identified');

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Suggest correction'),
      content: TextField(
        controller: reasonController,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Why? (helps improve records)',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final token =
                ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
            if (token == null) return;
            final res = await http.post(
              Uri.parse('${ApiConfig.baseUrl}/corrections'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'sighting_id': sightingId,
                'proposed_species_id': proposedSpeciesId,
                'reason': reasonController.text,
              }),
            );
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    res.statusCode >= 200 && res.statusCode < 300
                        ? 'Correction suggested — thank you'
                        : 'Could not submit correction',
                  ),
                ),
              );
            }
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}
