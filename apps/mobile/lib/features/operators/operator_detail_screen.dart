import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import 'operators_providers.dart';

class OperatorDetailScreen extends ConsumerWidget {
  const OperatorDetailScreen({super.key, required this.operatorId});

  final String operatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operatorAsync = ref.watch(operatorProvider(operatorId));

    return AppScaffold(
      title: 'Operator',
      body: AsyncValueWidget(
        value: operatorAsync,
        data: (op) {
          if (op == null) {
            return const Center(child: Text('Operator not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(op.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              Chip(label: Text(op.operatorType.dbValue)),
              const SizedBox(height: AppSpacing.md),
              if (op.description != null) Text(op.description!),
              if (op.address != null) ...[
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.location_on, color: AppColors.accent),
                  title: Text(op.address!),
                ),
              ],
              if (op.email != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email, color: AppColors.accent),
                  title: Text(op.email!),
                ),
              if (op.phone != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone, color: AppColors.accent),
                  title: Text(op.phone!),
                ),
              if (op.website != null) ...[
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language, color: AppColors.accent),
                  title: SelectableText(op.website!),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
