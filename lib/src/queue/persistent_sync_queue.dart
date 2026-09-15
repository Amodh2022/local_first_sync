import 'dart:async';

import '../core/sync_operation.dart';
import '../dependency/dependency_graph.dart';
import 'sync_operation_store.dart';
import 'sync_queue.dart';

/// A [SyncQueue] that survives process restarts by writing through to a
/// [SyncOperationStore], while serving reads from an in-memory mirror so the
/// engine's hot path never hits the database.
///
/// This is the queue a shipping app should use. [InMemorySyncQueue] loses
/// everything on restart, which means a user who force-quits the app while
/// offline loses their unsynced writes — the exact failure the package
/// exists to prevent.
///
/// ```dart
/// final queue = await PersistentSyncQueue.open(myStore);
/// final sync = OfflineSync(queue: queue);
/// ```
///
/// Ordering note: writes are serialized through an internal chain, so two
/// concurrent [updateOperation] calls can't interleave into a torn state in
/// the underlying store.
class PersistentSyncQueue implements SyncQueue {
  PersistentSyncQueue._(this._store, this._ops);

  /// Loads any previously persisted operations and returns a ready queue.
  ///
  /// Operations that were mid-flight when the process died come back as
  /// [SyncStatus.ready] and are re-sent under their original
  /// [SyncOperation.idempotencyKey] — see [SyncOperation.fromJson].
  static Future<PersistentSyncQueue> open(SyncOperationStore store) async {
    final rows = await store.readAll();
    final ops = <String, SyncOperation>{};
    for (final row in rows) {
      final op = SyncOperation.fromJson(row);
      ops[op.operationId] = op;
    }
    return PersistentSyncQueue._(store, ops);
  }

  final SyncOperationStore _store;
  final Map<String, SyncOperation> _ops;
  final _changes = StreamController<List<SyncOperation>>.broadcast();

  Future<void> _writes = Future.value();

  /// Serializes store writes without making callers wait on each other's
  /// error handling.
  Future<void> _serialized(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((_) {});
    return next;
  }

  List<SyncOperation> _snapshot() => _ops.values.toList(growable: false);

  void _emit() {
    if (!_changes.isClosed) _changes.add(_snapshot());
  }

  @override
  Future<void> enqueue(SyncOperation operation) async {
    if (DependencyGraph.wouldCreateCycle(_ops.values, operation)) {
      throw CyclicDependencyException(
        'Enqueuing ${operation.operationId} would create a circular '
        'dependency.',
      );
    }
    _ops[operation.operationId] = operation;
    await _serialized(() => _store.write(operation.toJson()));
    _emit();
  }

  @override
  Future<SyncOperation?> getOperation(String operationId) async =>
      _ops[operationId];

  @override
  Future<List<SyncOperation>> all() async => _snapshot();

  @override
  Future<List<SyncOperation>> dependentsOf(String operationId) async =>
      _snapshot().where((op) => op.dependencyIds.contains(operationId)).toList();

  @override
  Future<void> updateOperation(SyncOperation operation) async {
    _ops[operation.operationId] = operation;
    await _serialized(() => _store.write(operation.toJson()));
    _emit();
  }

  @override
  Future<void> removeOperation(String operationId) async {
    if (_ops.remove(operationId) == null) return;
    await _serialized(() => _store.delete(operationId));
    _emit();
  }

  /// Drops every operation, persisted rows included. Intended for sign-out,
  /// where keeping the previous user's unsynced writes would be a data leak.
  Future<void> clear() async {
    _ops.clear();
    await _serialized(_store.clear);
    _emit();
  }

  @override
  Stream<List<SyncOperation>> watchAll() => Stream.multi((controller) {
        controller.add(_snapshot());
        final sub =
            _changes.stream.listen(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  Future<void> dispose() async {
    await _writes;
    await _changes.close();
  }
}
