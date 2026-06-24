import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'dead_letter_providers.dart';

/// Banner shown at the top of the Settings screen whenever the local
/// sync queue has parked items (failed-permanently). Tapping the
/// banner opens a dialog with the full list and Retry / Dismiss
/// actions.
class DeadLetterBanner extends ConsumerWidget {
  const DeadLetterBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(deadLetterProvider);
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: const Color(0xFF7F1D1D),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDialog(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items.length == 1
                        ? '1 item could not be synced — tap to view'
                        : '${items.length} items could not be synced — tap to view',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final items = ref.watch(deadLetterProvider);
            final notifier = ref.read(deadLetterProvider.notifier);
            return AlertDialog(
              title: const Text('Unsynced items'),
              content: SizedBox(
                width: double.maxFinite,
                child: items.isEmpty
                    ? const Text('No parked items.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, i) {
                          final item = items[i];
                          return ListTile(
                            leading: const Icon(Icons.error_outline),
                            title: Text(item.type.name),
                            subtitle: Text(
                              DateFormat.yMMMd().add_jm().format(item.createdAt),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: items.isEmpty
                      ? null
                      : () async {
                          await notifier.dismissAll();
                        },
                  child: const Text('Dismiss all'),
                ),
                FilledButton.icon(
                  onPressed: items.isEmpty
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          await notifier.retryAll();
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry all'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}