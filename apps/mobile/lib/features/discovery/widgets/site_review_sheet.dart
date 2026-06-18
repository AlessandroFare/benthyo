import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_theme.dart';

Future<void> submitSiteReview({
  required WidgetRef ref,
  required String siteId,
  required int rating,
  String? body,
  double? visibilityM,
}) async {
  final token = ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
  if (token == null) throw Exception('Sign in to submit a review');

  final res = await http.post(
    Uri.parse('${ApiConfig.baseUrl}/reviews'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'dive_site_id': siteId,
      'rating': rating,
      if (body != null && body.isNotEmpty) 'body': body,
      if (visibilityM != null) 'visibility_m': visibilityM,
    }),
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final detail = res.body.isNotEmpty ? ': ${res.body}' : '';
    throw Exception('Failed to submit review ($res.statusCode$detail)');
  }
}

Future<void> showSiteReviewSheet(
  BuildContext context,
  WidgetRef ref,
  String siteId,
) async {
  var rating = 4;
  final bodyController = TextEditingController();
  final visController = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
      ),
      child: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review this site',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return IconButton(
                  onPressed: () => setState(() => rating = i + 1),
                  icon: Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    color: AppColors.accent,
                  ),
                );
              }),
            ),
            TextField(
              controller: visController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Visibility (m, optional)',
              ),
            ),
            TextField(
              controller: bodyController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Conditions, entry, hazards…',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () async {
                try {
                  await submitSiteReview(
                    ref: ref,
                    siteId: siteId,
                    rating: rating,
                    body: bodyController.text,
                    visibilityM: double.tryParse(visController.text),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Review submitted')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                }
              },
              child: const Text('Submit review'),
            ),
          ],
        ),
      ),
    ),
  );
}
