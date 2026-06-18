import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import 'operators_providers.dart';

class OperatorListScreen extends ConsumerWidget {
  const OperatorListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operatorsAsync = ref.watch(operatorsProvider);

    return AppScaffold(
      title: 'Operators',
      body: AsyncValueWidget(
        value: operatorsAsync,
        isEmpty: (ops) => ops.isEmpty,
        empty: const Center(child: Text('No operators listed')),
        data: (operators) => ListView.separated(
          itemCount: operators.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final op = operators[index];
            return ListTile(
              minVerticalPadding: AppSpacing.sm,
              leading: CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Text(
                  op.name.isNotEmpty ? op.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(op.name),
              subtitle: Text(
                '${op.operatorType.dbValue} · ${op.countryCode ?? '—'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/operators/${op.id}'),
            );
          },
        ),
      ),
    );
  }
}
