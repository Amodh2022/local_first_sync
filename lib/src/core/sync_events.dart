import 'sync_errors.dart';
import 'sync_operation.dart';

/// Framework-independent events emitted by [SyncEngine] — AGENTS.md §23.
/// Observable via `SyncEngine.events` / `OfflineSync.events` as a plain
/// `Stream<SyncEvent>`, so any state-management adapter can listen without
/// the core depending on it.
sealed class SyncEvent {
  SyncEvent() : timestamp = DateTime.now();

  final DateTime timestamp;
}

class SyncStarted extends SyncEvent {}

class SyncCompleted extends SyncEvent {
  SyncCompleted({required this.succeeded, required this.failed});

  final int succeeded;
  final int failed;
}

class OperationQueued extends SyncEvent {
  OperationQueued(this.operation);

  final SyncOperation operation;
}

class OperationStarted extends SyncEvent {
  OperationStarted(this.operation);

  final SyncOperation operation;
}

class OperationSucceeded extends SyncEvent {
  OperationSucceeded(this.operation);

  final SyncOperation operation;
}

class OperationFailed extends SyncEvent {
  OperationFailed(this.operation, this.error);

  final SyncOperation operation;
  final SyncFailure error;
}

class OperationBlocked extends SyncEvent {
  OperationBlocked(this.operation, this.reason);

  final SyncOperation operation;
  final String reason;
}

class ConflictDetected extends SyncEvent {
  ConflictDetected(this.operation, this.remoteValue);

  final SyncOperation operation;
  final Object? remoteValue;
}

class RollbackPerformed extends SyncEvent {
  RollbackPerformed(this.operation);

  final SyncOperation operation;
}

/// The queue was paused; no further operations will be attempted until
/// `SyncEngine.resume()`.
class SyncPaused extends SyncEvent {}

class SyncResumed extends SyncEvent {}

class OperationCancelled extends SyncEvent {
  OperationCancelled(this.operation);

  final SyncOperation operation;
}

/// A pull pass finished for one collection — emitted per collection, not
/// once for the whole pass, so a UI can show progress as it lands.
class PullCompleted extends SyncEvent {
  PullCompleted({
    required this.collection,
    required this.applied,
    required this.skipped,
  });

  final String collection;

  /// Records written into the local store from the remote.
  final int applied;

  /// Records the pull left alone because the entity had unsynced local
  /// work queued — pulling would have clobbered it.
  final int skipped;
}

class PullFailed extends SyncEvent {
  PullFailed(this.collection, this.error);

  final String collection;
  final SyncFailure error;
}
