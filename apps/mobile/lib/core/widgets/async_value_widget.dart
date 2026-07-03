import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'empty_state.dart';

class AsyncValueWidget<T> extends StatelessWidget {
  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
    this.empty,
    this.isEmpty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final Widget Function(Object error, StackTrace stack)? error;
  final Widget? empty;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () =>
          loading ??
          const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
      error: (err, stack) =>
          error?.call(err, stack) ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Something went wrong',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
      data: (d) {
        if (isEmpty != null && isEmpty!(d)) {
          return empty ??
              const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing here yet',
                subtitle: 'When there is something to show, it will appear here.',
              );
        }
        return data(d);
      },
    );
  }
}
