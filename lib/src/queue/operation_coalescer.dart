import '../core/sync_operation.dart';
import '../core/sync_status.dart';

/// What [OperationCoalescer] decided to do about a newly-enqueued operation.
class CoalesceResult {
  const CoalesceResult({
    required this.operation,
    this.replaces = const [],
    this.drop = false,
  });

  /// The operation to enqueue (possibly rewritten to absorb an earlier one).
  /// Meaningless when [drop] is true.
  final SyncOperation operation;

  /// Operation ids the new operation supersedes; the caller removes them.
  final List<String> replaces;

  /// The new operation cancels out the queued ones entirely — nothing is
  /// enqueued at all (e.g. create-then-delete while offline: the backend
  /// never knew the record existed, so there is nothing to tell it).
  final bool drop;
}

/// Collapses redundant queued writes on the same entity before they reach
/// the network. Eight offline edits to one note should cost one request on
/// reconnect, not eight.
///
/// Safety rules — a coalesce is only applied when it cannot change observable
/// behavior:
/// - Only operations still eligible to sync are candidates. Anything already
///   [SyncStatus.syncing], [SyncStatus.synced], [SyncStatus.failed] or
///   [SyncStatus.cancelled] is left strictly alone — it may already have
///   reached the backend.
/// - An operation other queued operations depend on is never removed, since
///   removing it would silently orphan its dependents.
/// - The surviving operation keeps the *earliest* [SyncOperation.createdAt]
///   and its dependencies, so FIFO order and the dependency graph are
///   preserved.
class OperationCoalescer {
  OperationCoalescer._();

  static bool _isCoalescable(SyncOperation op) =>
      op.status == SyncStatus.ready ||
      op.status == SyncStatus.queued ||
      op.status == SyncStatus.created ||
      op.status == SyncStatus.retry ||
      op.status == SyncStatus.blocked;

  /// Decides how [incoming] should be merged into [queued] (the full current
  /// queue).
  static CoalesceResult coalesce(
    Iterable<SyncOperation> queued,
    SyncOperation incoming,
  ) {
    final dependedOn = <String>{
      for (final op in queued) ...op.dependencyIds,
    };

    final superseded = queued
        .where((op) =>
            op.collection == incoming.collection &&
            op.entityId == incoming.entityId &&
            op.operationId != incoming.operationId &&
            _isCoalescable(op) &&
            !dependedOn.contains(op.operationId))
        .toList()
      ..sort(SyncOperation.compare);

    if (superseded.isEmpty) return CoalesceResult(operation: incoming);

    final earliest = superseded.first;
    final replaces = superseded.map((op) => op.operationId).toList();
    final mergedDependencies = <String>{
      ...incoming.dependencyIds,
      for (final op in superseded) ...op.dependencyIds,
    }.toList();

    switch (incoming.type) {
      // An update on top of queued writes: if the entity was never created
      // remotely, the surviving operation must stay a `create` carrying the
      // newest payload — otherwise the backend gets a PATCH for a row it
      // has never seen.
      case SyncOperationType.update:
        final becomesCreate =
            superseded.any((op) => op.type == SyncOperationType.create);
        return CoalesceResult(
          operation: _rebuild(
            incoming,
            type: becomesCreate ? SyncOperationType.create : incoming.type,
            createdAt: earliest.createdAt,
            dependencyIds: mergedDependencies,
            // Rolling back to the state before the *first* queued write is
            // what actually restores the user's pre-edit view.
            rollbackPayload: earliest.rollbackPayload,
          ),
          replaces: replaces,
        );

      // A delete on top of a queued create is a no-op for the backend.
      case SyncOperationType.delete:
        final hasQueuedCreate =
            superseded.any((op) => op.type == SyncOperationType.create);
        if (hasQueuedCreate) {
          return CoalesceResult(operation: incoming, replaces: replaces, drop: true);
        }
        return CoalesceResult(
          operation: _rebuild(
            incoming,
            type: SyncOperationType.delete,
            createdAt: earliest.createdAt,
            dependencyIds: mergedDependencies,
            rollbackPayload: earliest.rollbackPayload,
          ),
          replaces: replaces,
        );

      // A create for an entity that already has queued operations means the
      // local store says it doesn't exist — e.g. delete-then-recreate. Leave
      // both in place rather than guess; ordering already handles it.
      case SyncOperationType.create:
        return CoalesceResult(operation: incoming);
    }
  }

  static SyncOperation _rebuild(
    SyncOperation base, {
    required SyncOperationType type,
    required DateTime createdAt,
    required List<String> dependencyIds,
    Map<String, Object?>? rollbackPayload,
  }) =>
      SyncOperation(
        operationId: base.operationId,
        idempotencyKey: base.idempotencyKey,
        collection: base.collection,
        entityId: base.entityId,
        type: type,
        payload: base.payload,
        createdAt: createdAt,
        updatedAt: base.updatedAt,
        retryCount: base.retryCount,
        // Absorbing a blocked operation's dependencies must also absorb its
        // blocked-ness, or the merged operation would sync ahead of them.
        status: dependencyIds.isEmpty || base.status != SyncStatus.ready
            ? base.status
            : SyncStatus.blocked,
        dependencyIds: dependencyIds,
        lastError: base.lastError,
        nextRetryAt: base.nextRetryAt,
        blockedReason: base.blockedReason,
        priority: base.priority,
        rollbackPayload: rollbackPayload ?? base.rollbackPayload,
      );
}
