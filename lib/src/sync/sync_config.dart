import '../core/retry_policy.dart';

class SyncConfig {
  const SyncConfig({
    this.maxConcurrentOperations = 4,
    this.retryPolicy = const RetryPolicy(),
    this.operationTimeout = const Duration(seconds: 30),
    this.syncInterval,
    this.pullInterval,
    this.coalesceOperations = true,
    this.rollbackOnPermanentFailure = false,
    this.retainSyncedOperations = const Duration(minutes: 5),
  });

  /// Bounded worker concurrency (AGENTS.md §29). Independent operations sync
  /// concurrently up to this many at a time; dependent chains still
  /// serialize through the dependency graph regardless of this value, and
  /// two operations on the *same* entity never run in the same batch.
  final int maxConcurrentOperations;

  final RetryPolicy retryPolicy;

  /// Hard ceiling on a single remote call. A `RemoteStore` that hangs
  /// forever would otherwise wedge a queue slot permanently; on expiry the
  /// operation is treated as a retryable [TimeoutFailure]. `null` disables
  /// the ceiling (only sensible if your adapter has its own).
  final Duration? operationTimeout;

  /// Runs a drain on this interval even with no connectivity or queue
  /// change to react to — a safety net for a backend that was unreachable
  /// while the device reported itself online. `null` (default) means
  /// event-driven only.
  final Duration? syncInterval;

  /// Runs [SyncEngine.pullNow] on this interval, for collections whose
  /// remote store implements [PullableRemoteStore]. `null` disables
  /// periodic pulling; you can still call `pullNow()` yourself.
  final Duration? pullInterval;

  /// Collapses redundant queued operations on the same entity before they
  /// ever reach the network — two pending updates become one, a create
  /// followed by a delete cancels both. See [OperationCoalescer].
  final bool coalesceOperations;

  /// When an operation fails permanently, restore the entity's local state
  /// to what it was before the optimistic write, and emit
  /// [RollbackPerformed]. Off by default: silently reverting a user's typing
  /// is a product decision, not a framework default.
  final bool rollbackOnPermanentFailure;

  /// How long a [SyncStatus.synced] operation is kept in the queue for
  /// inspection before being purged. `null` keeps them forever (the queue
  /// then grows without bound — only sensible for a short-lived process).
  final Duration? retainSyncedOperations;
}
