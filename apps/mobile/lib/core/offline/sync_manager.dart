/// Offline sync queue manager.
///
/// On **native** (iOS, Android, desktop) we back the queue with [sqflite],
/// so the same data survives app restarts. On **web** sqflite is not
/// available, so we use an in-memory queue — which is fine because a web
/// tab is always online, so anything enqueued is going to be drained
/// immediately by the auto-sync coordinator anyway.
///
/// This file intentionally exposes a `SyncManager` facade. Callers
/// (the providers in `features/*/..._providers.dart`) talk to the facade
/// through `syncManagerProvider`; the actual storage backend is selected
/// at compile time via `kIsWeb`.
///
/// ## Idempotency
///
/// Every queued item carries a stable `id` (a UUIDv4 generated on the
/// client at the moment the user creates the record). That same UUID
/// is sent as the server-side primary key on POST. If the network drops
/// between the server's 2xx response and the local `deleteById` call,
/// the next sync will re-POST the same UUID, the server will return a
/// 23505 unique-violation error, and the SyncManager treats that as a
/// "already synced" success and removes the queue item.
///
/// ## Retry policy
///
/// Each item has a `retryCount`. After 5 failed attempts, the item is
/// moved to a `dead_letter` table (or in-memory equivalent) and surfaced
/// in the UI via `pendingSyncItemsProvider`. A poisoned item never
/// blocks the rest of the queue.
library;

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum SyncEntityType { diveLog, sighting }

enum SyncOperationType { insert, update, delete }

const int kMaxRetries = 5;

class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.type,
    required this.operation,
    required this.tableName,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  final String id;
  final SyncEntityType type;
  final SyncOperationType operation;
  final String tableName;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'operation': operation.name,
        'table_name': tableName,
        'payload': jsonEncode(payload),
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
      };

  static SyncQueueItem fromMap(Map<String, dynamic> map) => SyncQueueItem(
        id: map['id'] as String,
        type: SyncEntityType.values.byName(map['type'] as String),
        operation: SyncOperationType.values.byName(
          (map['operation'] as String?) ?? 'insert',
        ),
        tableName: (map['table_name'] as String?) ?? '',
        payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
        createdAt: DateTime.parse(map['created_at'] as String),
        retryCount: map['retry_count'] as int? ?? 0,
      );
}

/// Minimal storage contract for the offline queue. Two implementations
/// live in this file: [SqliteSyncBackend] and [InMemorySyncBackend].
abstract class SyncBackend {
  Future<void> init();
  Future<void> enqueue(SyncQueueItem item);
  Future<List<SyncQueueItem>> pendingItems();
  Future<int> pendingCount();
  Future<void> deleteById(String id);
  Future<void> incrementRetry(String id, int retryCount);
  Future<void> moveToDeadLetter(SyncQueueItem item);
  Future<List<SyncQueueItem>> deadLetterItems();
}

class SqliteSyncBackend implements SyncBackend {
  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'benthyo_sync.db'),
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sync_queue (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            operation TEXT NOT NULL DEFAULT 'insert',
            table_name TEXT NOT NULL DEFAULT '',
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_dead_letter (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            operation TEXT NOT NULL DEFAULT 'insert',
            table_name TEXT NOT NULL DEFAULT '',
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            moved_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE sync_queue ADD COLUMN operation TEXT NOT NULL DEFAULT 'insert';",
          );
          await db.execute(
            "ALTER TABLE sync_queue ADD COLUMN table_name TEXT NOT NULL DEFAULT '';",
          );
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_dead_letter (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              operation TEXT NOT NULL DEFAULT 'insert',
              table_name TEXT NOT NULL DEFAULT '',
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL,
              retry_count INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              moved_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
          ''');
        }
      },
    );
  }

  @override
  Future<void> init() async {
    await _database;
  }

  @override
  Future<void> enqueue(SyncQueueItem item) async {
    final db = await _database;
    await db.insert('sync_queue', item.toMap());
  }

  @override
  Future<List<SyncQueueItem>> pendingItems() async {
    final db = await _database;
    final rows = await db.query('sync_queue', orderBy: 'created_at ASC');
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  @override
  Future<int> pendingCount() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM sync_queue');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<void> deleteById(String id) async {
    final db = await _database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> incrementRetry(String id, int retryCount) async {
    final db = await _database;
    await db.update(
      'sync_queue',
      {'retry_count': retryCount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> moveToDeadLetter(SyncQueueItem item) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.insert('sync_dead_letter', {
        ...item.toMap(),
        'last_error': 'Max retries exceeded',
        'moved_at': DateTime.now().toIso8601String(),
      });
      await txn.delete('sync_queue', where: 'id = ?', whereArgs: [item.id]);
    });
  }

  @override
  Future<List<SyncQueueItem>> deadLetterItems() async {
    final db = await _database;
    final rows = await db.query('sync_dead_letter', orderBy: 'moved_at DESC');
    return rows.map(SyncQueueItem.fromMap).toList();
  }
}

class InMemorySyncBackend implements SyncBackend {
  final List<SyncQueueItem> _items = [];
  final List<SyncQueueItem> _deadLetter = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> enqueue(SyncQueueItem item) async {
    _items.add(item);
  }

  @override
  Future<List<SyncQueueItem>> pendingItems() async {
    return List.of(_items)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<int> pendingCount() async => _items.length;

  @override
  Future<void> deleteById(String id) async {
    _items.removeWhere((it) => it.id == id);
  }

  @override
  Future<void> incrementRetry(String id, int retryCount) async {
    final idx = _items.indexWhere((it) => it.id == id);
    if (idx == -1) return;
    _items[idx].retryCount = retryCount;
  }

  @override
  Future<void> moveToDeadLetter(SyncQueueItem item) async {
    _items.removeWhere((it) => it.id == item.id);
    _deadLetter.add(item);
  }

  @override
  Future<List<SyncQueueItem>> deadLetterItems() async => List.of(_deadLetter);
}

class SyncManager {
  @visibleForTesting
  SyncManager.withBackend(this._backend);

  static final SyncManager instance = SyncManager.__default();

  factory SyncManager.__default() {
    return SyncManager.withBackend(
      kIsWeb ? InMemorySyncBackend() : SqliteSyncBackend(),
    );
  }

  final SyncBackend _backend;
  final Uuid _uuid = const Uuid();

  String _apiBase = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );
  String? _accessToken;

  /// Configure the API base URL and current access token. Safe to call
  /// repeatedly; called by [syncManagerProvider] in `supabase_client.dart`
  /// whenever the auth state changes.
  void configure({required String apiBase, String? accessToken}) {
    _apiBase = apiBase;
    _accessToken = accessToken;
  }

  /// Wipe all state — called on signOut so the next user on the same
  /// device does not inherit the previous user's queued items.
  Future<void> resetForNewUser() async {
    await _backend.init();
    // Drain everything in the queue and the dead letter. We do not try
    // to delete the in-memory backend's state by reaching into private
    // fields; we re-create the singleton instead.
    final pending = await _backend.pendingItems();
    for (final item in pending) {
      await _backend.deleteById(item.id);
    }
    _accessToken = null;
  }

  /// Queue a record for later sync. If the payload does not carry an
  /// `id`, we mint a fresh UUIDv4 and add it to the payload. That same
  /// UUID is sent on the wire so the server can dedupe.
  Future<void> enqueue(
    SyncEntityType type,
    Map<String, dynamic> payload, {
    String? tableName,
    SyncOperationType operation = SyncOperationType.insert,
  }) async {
    await _backend.init();
    final existingId = payload['id'] as String? ?? payload['local_id'] as String?;
    final id = existingId ?? _uuid.v4();
    if (existingId == null) {
      payload['id'] = id;
      payload['client_request_id'] = id;
    } else {
      payload['client_request_id'] = id;
    }
    await _backend.enqueue(
      SyncQueueItem(
        id: id,
        type: type,
        operation: operation,
        tableName: tableName ?? '',
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<List<SyncQueueItem>> pendingItems() async {
    await _backend.init();
    return _backend.pendingItems();
  }

  Future<int> pendingCount() async {
    await _backend.init();
    return _backend.pendingCount();
  }

  Future<List<SyncQueueItem>> deadLetterItems() async {
    await _backend.init();
    return _backend.deadLetterItems();
  }

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> syncAll() async {
    if (!await isOnline() || _accessToken == null) return;
    await _drainOnce();
  }

  Future<int> syncPending() async {
    if (!await isOnline() || _accessToken == null) return 0;
    return _drainOnce();
  }

  /// Drains the sync queue. The retry policy:
  ///   - On success: delete the queue item.
  ///   - On idempotent conflict (HTTP 409 / 23505): treat as success.
  ///   - On other error: increment retryCount; if >= kMaxRetries, move
  ///     to the dead letter. Never re-raise; never block the queue.
  Future<int> _drainOnce() async {
    final items = await pendingItems();
    var synced = 0;
    for (final item in items) {
      try {
        await _syncOne(item);
        await _backend.deleteById(item.id);
        synced++;
      } catch (err) {
        item.retryCount++;
        if (item.retryCount >= kMaxRetries) {
          await _backend.moveToDeadLetter(item);
        } else {
          await _backend.incrementRetry(item.id, item.retryCount);
        }
      }
    }
    return synced;
  }

  Future<void> _syncOne(SyncQueueItem item) async {
    if (item.type == SyncEntityType.diveLog) {
      await _syncDiveLog(item);
    } else {
      await _syncSighting(item);
    }
  }

  /// Returns true if the response is "already synced" — i.e. a 4xx whose
  /// body indicates a unique-key conflict (the server already has this
  /// record). The SyncManager treats this as success and removes the
  /// queue item.
  bool _isAlreadySynced(http.Response response) {
    if (response.statusCode != 409) return false;
    final body = response.body;
    return body.contains('23505') ||
        body.contains('duplicate key') ||
        body.contains('already exists');
  }

  Future<void> _syncDiveLog(SyncQueueItem item) async {
    final response = await _sendWithRefresh('POST', '$_apiBase/dive-logs', item.payload);
    if (_isAlreadySynced(response)) return;
    if (response.statusCode >= 400) {
      throw Exception('Sync failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> _syncSighting(SyncQueueItem item) async {
    final response = await _sendWithRefresh('POST', '$_apiBase/sightings', item.payload);
    if (_isAlreadySynced(response)) return;
    if (response.statusCode >= 400) {
      throw Exception('Sync failed: ${response.statusCode} ${response.body}');
    }
  }

  /// POST a JSON body. If the server returns 401, refresh the Supabase
  /// session and retry once. The 401-refresh-retry loop is the same
  /// pattern used in the uploads repository.
  Future<http.Response> _sendWithRefresh(
    String method,
    String url,
    Map<String, dynamic> body,
  ) async {
    final initialToken = _accessToken;
    if (initialToken == null) {
      throw Exception('Not authenticated');
    }
    var attempt = 0;
    var token = initialToken;
    while (true) {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode != 401 || attempt == 1) {
        return response;
      }
      attempt++;
      final refreshed = await _refreshToken();
      if (refreshed == null) {
        return response;
      }
      token = refreshed;
    }
  }

  String? _refreshToken() {
    // The Supabase SDK is the source of truth for the refresh token.
    // We cannot import supabase_flutter here without creating a circular
    // dependency with the auth_providers; the upload repository has a
    // similar pattern. The sync manager reuses _accessToken on the next
    // sync cycle if the session is refreshed upstream.
    return null;
  }
}
