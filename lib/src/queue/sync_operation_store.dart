import 'dart:convert';

import '../core/sync_operation.dart';

/// The persistence seam under [PersistentSyncQueue].
///
/// The competing packages all hardcode this to SQLite (Brick keeps its
/// request queue in a second SQLite file; Synquill uses Drift). This core
/// deliberately doesn't depend on a database at all, so the same queue
/// semantics work over Drift, Isar, sqflite, Hive, SharedPreferences, or a
/// plain file — you implement these four methods.
///
/// A conforming implementation must be durable before its `Future`
/// completes: the whole point of the queue is that a crash between "the
/// local write happened" and "the server acknowledged it" loses nothing.
abstract interface class SyncOperationStore {
  /// Every persisted operation, as written by [write]. Called once when the
  /// queue is opened.
  Future<List<Map<String, Object?>>> readAll();

  Future<void> write(Map<String, Object?> operation);

  Future<void> delete(String operationId);

  Future<void> clear();
}

/// Non-durable [SyncOperationStore] for tests — the queue it backs behaves
/// exactly like a persistent one within a single process.
class InMemoryOperationStore implements SyncOperationStore {
  InMemoryOperationStore([Map<String, Map<String, Object?>>? initial])
      : _rows = {...?initial};

  final Map<String, Map<String, Object?>> _rows;

  @override
  Future<List<Map<String, Object?>>> readAll() async => _rows.values.toList();

  @override
  Future<void> write(Map<String, Object?> operation) async {
    _rows[operation['operationId']! as String] = operation;
  }

  @override
  Future<void> delete(String operationId) async => _rows.remove(operationId);

  @override
  Future<void> clear() async => _rows.clear();
}

/// A [SyncOperationStore] over any key–value store that can hold one string,
/// which is the cheapest real persistence a Flutter app already has:
///
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// final queue = await PersistentSyncQueue.open(
///   JsonBlobOperationStore(
///     readBlob: () async => prefs.getString('local_first_sync.queue'),
///     writeBlob: (json) => prefs.setString('local_first_sync.queue', json),
///   ),
/// );
/// ```
///
/// It rewrites the whole blob on every change, so it is appropriate for
/// queues of tens-to-hundreds of operations, not tens of thousands — for
/// those, implement [SyncOperationStore] against a real table with a
/// per-row write.
class JsonBlobOperationStore implements SyncOperationStore {
  JsonBlobOperationStore({required this.readBlob, required this.writeBlob});

  /// Reads the previously written blob, or `null` on first run.
  final Future<String?> Function() readBlob;

  /// Persists the blob. Must be durable before the future completes.
  final Future<void> Function(String json) writeBlob;

  final _rows = <String, Map<String, Object?>>{};
  var _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await readBlob();
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw) as List<Object?>;
    for (final row in decoded) {
      final map = Map<String, Object?>.from(row! as Map);
      _rows[map['operationId']! as String] = map;
    }
  }

  Future<void> _flush() => writeBlob(jsonEncode(_rows.values.toList()));

  @override
  Future<List<Map<String, Object?>>> readAll() async {
    await _ensureLoaded();
    return _rows.values.toList();
  }

  @override
  Future<void> write(Map<String, Object?> operation) async {
    await _ensureLoaded();
    _rows[operation['operationId']! as String] = operation;
    await _flush();
  }

  @override
  Future<void> delete(String operationId) async {
    await _ensureLoaded();
    if (_rows.remove(operationId) != null) await _flush();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _rows.clear();
    await _flush();
  }
}

/// Convenience: the JSON rows for a list of operations.
List<Map<String, Object?>> encodeOperations(Iterable<SyncOperation> ops) =>
    ops.map((op) => op.toJson()).toList();
