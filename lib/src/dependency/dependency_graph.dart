import '../core/sync_operation.dart';
import '../core/sync_status.dart';

/// Thrown by [SyncQueue.enqueue] when the new operation's dependencies would
/// form a cycle. Never silently accepted.
class CyclicDependencyException implements Exception {
  CyclicDependencyException(this.message);

  final String message;

  @override
  String toString() => 'CyclicDependencyException: $message';
}

/// Pure functions over a queue snapshot — deliberately not a persisted data
/// structure of its own, so it can never drift from the queue it describes
/// (DESIGN.md §6).
class DependencyGraph {
  DependencyGraph._();

  /// Whether adding [candidate] to [existing] would create a circular
  /// dependency chain (including a self-dependency).
  static bool wouldCreateCycle(
    Iterable<SyncOperation> existing,
    SyncOperation candidate,
  ) {
    final byId = {for (final op in existing) op.operationId: op};
    byId[candidate.operationId] = candidate;

    final visiting = <String>{};
    final visited = <String>{};

    bool visit(String id) {
      if (visited.contains(id)) return false;
      if (visiting.contains(id)) return true;
      visiting.add(id);
      final op = byId[id];
      if (op != null) {
        for (final dep in op.dependencyIds) {
          if (visit(dep)) return true;
        }
      }
      visiting.remove(id);
      visited.add(id);
      return false;
    }

    return visit(candidate.operationId);
  }

  /// For every operation in [all] that has at least one dependency not yet
  /// [SyncStatus.synced], returns a human-readable reason keyed by
  /// [SyncOperation.operationId].
  static Map<String, String> blockedReasons(Iterable<SyncOperation> all) {
    final byId = {for (final op in all) op.operationId: op};
    final reasons = <String, String>{};
    for (final op in all) {
      for (final depId in op.dependencyIds) {
        final dep = byId[depId];
        if (dep == null || dep.status == SyncStatus.synced) continue;
        final detail =
            dep.lastError != null ? ', last error: ${dep.lastError}' : '';
        reasons[op.operationId] = 'Waiting for ${dep.collection}/'
            '${dep.entityId} (status: ${dep.status.name}$detail).';
        break;
      }
    }
    return reasons;
  }
}
