import '../core/id_generator.dart';
import '../core/identifiable.dart';
import '../core/sync_operation.dart';
import '../core/sync_status.dart';
import '../queue/operation_coalescer.dart';
import '../queue/sync_queue.dart';
import '../serialization/serializer.dart';
import '../storage/local_store.dart';

/// The developer-facing, local-first API. Reads always come
/// from [LocalStore]; writes update it immediately and independently enqueue
/// a [SyncOperation] — callers never wait on the network to observe a
/// mutation.
///
/// ```dart
/// final users = sync.registerCollection<User>(...);
/// await users.save(user);
/// final user = await users.get('123');
/// users.watch();
/// ```
class Collection<T extends Identifiable> {
  Collection({
    required this.name,
    required LocalStore<T> localStore,
    required SyncQueue queue,
    required Serializer<T> serializer,
    bool coalesceOperations = true,
  })  : _localStore = localStore,
        _queue = queue,
        _serializer = serializer,
        _coalesce = coalesceOperations;

  final String name;
  final LocalStore<T> _localStore;
  final SyncQueue _queue;
  final Serializer<T> _serializer;
  final bool _coalesce;

  Future<T?> get(String id) => _localStore.getById(id);

  Future<List<T>> getAll() => _localStore.getAll();

  Stream<List<T>> watch() => _localStore.watchAll();

  Stream<T?> watchById(String id) => _localStore.watchById(id);

  /// Inserts or updates [item] locally (visible to [watch]/[watchById]
  /// immediately) and enqueues the corresponding remote operation.
  ///
  /// Pass [dependsOn] — [SyncOperation.operationId]s returned by earlier
  /// [save]/[delete]
  /// calls — when this entity structurally depends on another one still
  /// syncing (e.g. an `OrderItem` referencing an `Order`'s id). Temporary ids
  /// get rewritten into these dependents once the dependency resolves.
  ///
  /// [priority] raises this write above the rest of the backlog: a message
  /// send at priority 10 goes out before 200 queued analytics events, no
  /// matter which was written first. Equal priorities stay strictly FIFO.
  ///
  /// Returns the new operation's id.
  Future<String> save(
    T item, {
    List<String> dependsOn = const [],
    int priority = 0,
  }) async {
    final existing = await _localStore.getById(item.id);
    final type =
        existing == null ? SyncOperationType.create : SyncOperationType.update;
    // Captured before the local write, so a permanent failure can put the
    // entity back the way the user last saw it synced.
    final rollbackPayload =
        existing == null ? null : _serializer.encode(existing);
    if (existing == null) {
      await _localStore.insert(item);
    } else {
      await _localStore.update(item);
    }
    return _enqueue(
      type,
      item.id,
      _serializer.encode(item),
      dependsOn,
      priority,
      rollbackPayload,
    );
  }

  /// Returns the new operation's id.
  Future<String> delete(
    String id, {
    List<String> dependsOn = const [],
    int priority = 0,
  }) async {
    final existing = await _localStore.getById(id);
    final rollbackPayload =
        existing == null ? null : _serializer.encode(existing);
    await _localStore.delete(id);
    return _enqueue(
      SyncOperationType.delete,
      id,
      const {},
      dependsOn,
      priority,
      rollbackPayload,
    );
  }

  Future<String> _enqueue(
    SyncOperationType type,
    String entityId,
    Map<String, Object?> payload,
    List<String> dependencyIds,
    int priority,
    Map<String, Object?>? rollbackPayload,
  ) async {
    final now = DateTime.now();
    final operationId = generateOperationId();
    var operation = SyncOperation(
      operationId: operationId,
      idempotencyKey: operationId,
      collection: name,
      entityId: entityId,
      type: type,
      payload: payload,
      createdAt: now,
      updatedAt: now,
      status: dependencyIds.isEmpty ? SyncStatus.ready : SyncStatus.blocked,
      dependencyIds: dependencyIds,
      priority: priority,
      rollbackPayload: rollbackPayload,
    );

    if (!_coalesce) {
      await _queue.enqueue(operation);
      return operationId;
    }

    // Fold this write into any redundant ones already queued for the same
    // entity, so a burst of offline edits costs one request, not N.
    final result = OperationCoalescer.coalesce(await _queue.all(), operation);
    for (final supersededId in result.replaces) {
      await _queue.removeOperation(supersededId);
    }
    if (result.drop) return operationId;
    operation = result.operation;
    await _queue.enqueue(operation);
    return operationId;
  }
}
