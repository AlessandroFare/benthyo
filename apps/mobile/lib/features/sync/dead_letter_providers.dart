import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/sync_manager.dart';
import '../../core/supabase/supabase_client.dart';

/// Riverpod providers for the **dead-letter** portion of the sync
/// queue. The active queue state lives next to the [SyncManager] in
/// `core/supabase/supabase_client.dart`; this file owns the failed /
/// parked items surfaced on the Settings screen.

/// Parked (failed-permanently) sync items. Refreshed on demand via
/// [DeadLetterNotifier.refresh].
final deadLetterProvider = StateNotifierProvider<DeadLetterNotifier,
    List<SyncQueueItem>>((ref) {
  return DeadLetterNotifier(ref);
});

class DeadLetterNotifier extends StateNotifier<List<SyncQueueItem>> {
  DeadLetterNotifier(this._ref) : super(const []) {
    refresh();
  }

  final Ref _ref;

  Future<void> refresh() async {
    try {
      final items = await _ref.read(syncManagerProvider).deadLetterItems();
      if (mounted) state = items;
    } catch (err) {
      debugPrint('deadLetter refresh failed: $err');
    }
  }

  /// Retry a single item by triggering a full sync cycle (the backend
  /// server is authoritative about which items to retry). On success
  /// the item drops out of the local dead-letter list.
  Future<bool> retry(SyncQueueItem item) async {
    try {
      await _ref.read(syncManagerProvider).syncAll();
      await refresh();
      return true;
    } catch (err) {
      debugPrint('deadLetter retry failed for ${item.id}: $err');
      return false;
    }
  }

  Future<void> dismiss(SyncQueueItem item) async {
    // Local-only dismissal: filter out of the state. The on-device
    // backend does not store dismissed flags; this is a UI affordance.
    if (mounted) {
      state = state.where((i) => i.id != item.id).toList();
    }
  }

  Future<void> retryAll() async {
    try {
      await _ref.read(syncManagerProvider).syncAll();
    } catch (err) {
      debugPrint('deadLetter retryAll syncAll failed: $err');
    }
    await refresh();
  }

  Future<void> dismissAll() async {
    if (mounted) state = const [];
  }
}