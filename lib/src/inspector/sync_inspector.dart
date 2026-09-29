import '../connectivity/connectivity_monitor.dart';
import '../core/sync_events.dart';
import '../core/sync_operation.dart';
import '../core/sync_status.dart';
import '../queue/sync_queue.dart';

/// A point-in-time view over the queue, for building an in-app "Sync
/// Inspector" UI.
class SyncInspectorSnapshot {
  const SyncInspectorSnapshot({
    required this.connectivity,
    required this.pending,
    required this.syncing,
    required this.failed,
    required this.blocked,
    required this.synced,
    required this.operations,
  });

  final ConnectivityState connectivity;
  final int pending;
  final int syncing;
  final int failed;
  final int blocked;
  final int synced;

  /// All operations, with any [SyncInspector.redactedFields] blanked out.
  final List<SyncOperation> operations;
}

/// Read-only diagnostics over a [SyncQueue]. Deliberately has no ability to
/// mutate the queue; it only explains what's there.
class SyncInspector {
  SyncInspector({
    required SyncQueue queue,
    required ConnectivityMonitor connectivity,
    this.redactedFields = const {},
    List<SyncEvent> Function()? eventHistory,
  })  : _queue = queue,
        _connectivity = connectivity,
        _eventHistory = eventHistory;

  final SyncQueue _queue;
  final ConnectivityMonitor _connectivity;
  final List<SyncEvent> Function()? _eventHistory;

  /// The engine's recent events, oldest first (see
  /// `SyncConfig.eventHistoryLimit`). Empty for an inspector built without
  /// an event history. Operations inside events are redacted like
  /// [snapshot]'s.
  List<SyncEvent> get recentEvents =>
      (_eventHistory?.call() ?? const <SyncEvent>[]).map(_redactEvent).toList();

  /// The recent events that concern [operationId], oldest first: every
  /// start, failure (with its error), block, conflict and success. The
  /// timeline behind "why did this fail?", where [explain] only describes
  /// the current state.
  List<SyncEvent> historyFor(String operationId) => recentEvents
      .where((e) => operationOf(e)?.operationId == operationId)
      .toList();

  /// The operation an event is about, or `null` for engine-wide events
  /// (sync started/completed, paused/resumed, pulls).
  static SyncOperation? operationOf(SyncEvent event) => switch (event) {
        OperationQueued(:final operation) ||
        OperationStarted(:final operation) ||
        OperationSucceeded(:final operation) ||
        OperationFailed(:final operation) ||
        OperationBlocked(:final operation) ||
        ConflictDetected(:final operation) ||
        RollbackPerformed(:final operation) ||
        OperationCancelled(:final operation) =>
          operation,
        SyncStarted() ||
        SyncCompleted() ||
        SyncPaused() ||
        SyncResumed() ||
        PullCompleted() ||
        PullFailed() =>
          null,
      };

  /// Payload field names to blank out (e.g. `password`, `authToken`) in any
  /// snapshot this inspector produces.
  final Set<String> redactedFields;

  Future<SyncInspectorSnapshot> snapshot() async {
    final ops = (await _queue.all()).map(_redact).toList();
    int count(bool Function(SyncOperation) match) => ops.where(match).length;
    return SyncInspectorSnapshot(
      connectivity: _connectivity.current,
      pending: count((o) =>
          o.status == SyncStatus.ready ||
          o.status == SyncStatus.queued ||
          o.status == SyncStatus.created),
      syncing: count((o) => o.status == SyncStatus.syncing),
      failed: count(
          (o) => o.status == SyncStatus.failed || o.status == SyncStatus.retry),
      blocked: count((o) => o.status == SyncStatus.blocked),
      synced: count((o) => o.status == SyncStatus.synced),
      operations: ops,
    );
  }

  Stream<SyncInspectorSnapshot> watch() =>
      _queue.watchAll().asyncMap((_) => snapshot());

  /// A human-readable explanation for why [operation] hasn't synced yet —
  /// the "Why isn't this synced?" requirement. Never reduces
  /// a failure to a bare "Sync failed."
  String explain(SyncOperation operation) {
    return switch (operation.status) {
      SyncStatus.synced =>
        '${operation.collection}/${operation.entityId} is synced.',
      SyncStatus.blocked =>
        'BLOCKED: ${operation.blockedReason ?? 'waiting on a dependency.'}',
      SyncStatus.failed => 'FAILED permanently after ${operation.retryCount} '
          'attempt(s): ${operation.lastError ?? 'unknown error'}.',
      SyncStatus.retry => 'RETRYING (attempt ${operation.retryCount}): '
          '${operation.lastError ?? 'transient error'}.'
          '${operation.nextRetryAt != null ? ' Next retry at ${operation.nextRetryAt}.' : ''}',
      SyncStatus.syncing => 'Currently syncing to the backend.',
      SyncStatus.conflict => 'A conflict was detected and is being resolved.',
      SyncStatus.cancelled => 'Cancelled; will not sync.',
      SyncStatus.created ||
      SyncStatus.queued ||
      SyncStatus.ready =>
        'Queued, waiting for the next sync pass.',
    };
  }

  SyncEvent _redactEvent(SyncEvent event) {
    if (redactedFields.isEmpty) return event;
    final at = event.timestamp;
    return switch (event) {
      OperationQueued(:final operation) =>
        OperationQueued(_redact(operation), timestamp: at),
      OperationStarted(:final operation) =>
        OperationStarted(_redact(operation), timestamp: at),
      OperationSucceeded(:final operation) =>
        OperationSucceeded(_redact(operation), timestamp: at),
      OperationFailed(:final operation, :final error) =>
        OperationFailed(_redact(operation), error, timestamp: at),
      OperationBlocked(:final operation, :final reason) =>
        OperationBlocked(_redact(operation), reason, timestamp: at),
      ConflictDetected(:final operation, :final remoteValue) =>
        ConflictDetected(_redact(operation), remoteValue, timestamp: at),
      RollbackPerformed(:final operation) =>
        RollbackPerformed(_redact(operation), timestamp: at),
      OperationCancelled(:final operation) =>
        OperationCancelled(_redact(operation), timestamp: at),
      _ => event,
    };
  }

  SyncOperation _redact(SyncOperation op) {
    if (redactedFields.isEmpty) return op;
    final hasAny = redactedFields.any(op.payload.containsKey);
    if (!hasAny) return op;
    final payload = Map<String, Object?>.of(op.payload);
    for (final field in redactedFields) {
      if (payload.containsKey(field)) payload[field] = '<redacted>';
    }
    return op.copyWith(payload: payload);
  }
}
