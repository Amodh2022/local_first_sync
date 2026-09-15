import '../core/sync_operation.dart';

/// Persistent storage for [SyncOperation]s. A real adapter
/// must persist every write in the same transaction as the entity mutation
/// it accompanies — that's what makes crash recovery sound.
///
/// [InMemorySyncQueue] is the reference implementation for tests/prototyping
/// only; it does not survive a process restart.
abstract interface class SyncQueue {
  /// Persists a new operation. Throws [CyclicDependencyException] if
  /// [operation.dependencyIds] would introduce a circular dependency.
  Future<void> enqueue(SyncOperation operation);

  Future<SyncOperation?> getOperation(String operationId);

  /// All operations regardless of status. Callers filter by [SyncStatus] as
  /// needed — kept deliberately simple rather than exposing a query API the
  /// MVP doesn't need yet.
  Future<List<SyncOperation>> all();

  /// Operations whose [SyncOperation.dependencyIds] contains [operationId].
  Future<List<SyncOperation>> dependentsOf(String operationId);

  Future<void> updateOperation(SyncOperation operation);

  Future<void> removeOperation(String operationId);

  Stream<List<SyncOperation>> watchAll();
}
