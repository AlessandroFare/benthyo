import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_widget.dart';

final prepCardProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, siteId) async {
  final res = await http.get(
    Uri.parse('${ApiConfig.baseUrl}/public/sites/$siteId/prep-card'),
  );
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return body['data'] as Map<String, dynamic>? ?? body;
});

class PrepCardSection extends ConsumerWidget {
  const PrepCardSection({super.key, required this.siteId, this.siteSlug});

  final String siteId;
  final String? siteSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prepAsync = ref.watch(prepCardProvider(siteSlug ?? siteId));

    return AsyncValueWidget(
      value: prepAsync,
      data: (prep) {
        if (prep == null) return const SizedBox.shrink();
        final site = prep['site'] as Map<String, dynamic>? ?? {};
        final reviews = prep['recent_reviews'] as List<dynamic>? ?? [];
        final species = prep['recent_species'] as List<dynamic>? ?? [];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pre-dive prep',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${site['total_dives'] ?? 0} logged dives · '
                  '${site['total_species'] ?? 0} species observed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (reviews.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Recent reviews',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  ...reviews.take(3).map((r) {
                    final review = r as Map<String, dynamic>;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(review['body'] as String? ?? 'No notes'),
                      subtitle: Text(
                        '${review['username']} · ${review['rating']}/5',
                      ),
                    );
                  }),
                ],
                if (species.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Spotted recently',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: species.take(6).map((s) {
                      final sp = s as Map<String, dynamic>;
                      return Chip(
                        label: Text(
                          sp['common_name'] as String? ??
                              sp['scientific_name'] as String? ??
                              '?',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () async {
                    final slug = siteSlug ?? siteId;
                    final uri = Uri.parse(
                      '${ApiConfig.webBaseUrl}/embed/site/$slug/prep',
                    );
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share prep card'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
