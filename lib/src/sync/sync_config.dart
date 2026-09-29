import '../core/retry_policy.dart';
import '../core/sync_errors.dart';

/// What the engine should do with an operation the backend rejected with an
/// [AuthFailure]. Returned by [SyncConfig.onAuthFailure].
enum AuthRecovery {
  /// Credentials were refreshed: send the operation again. If that retry is
  /// rejected with another [AuthFailure], the operation fails permanently
  /// rather than looping.
  retry,

  /// Stop syncing until the app calls `resume()`, for example after the
  /// user signs in again. The operation goes back in line without using up
  /// a retry.
  pause,

  /// Fail the operation permanently, as if no handler were configured.
  fail,
}

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
    this.onAuthFailure,
    this.rewriteLocalReferences = true,
    this.eventHistoryLimit = 100,
  }) : assert(eventHistoryLimit >= 0, 'eventHistoryLimit must be >= 0');

  /// Bounded worker concurrency. Independent operations sync
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

  /// Called when a remote call fails with an [AuthFailure] (such as an
  /// HTTP 401), before the operation is marked failed. Typically it
  /// refreshes the access token and returns [AuthRecovery.retry].
  ///
  /// When several operations in one batch hit the same expired token, the
  /// handler runs once and they all share its result. `null` (the default)
  /// keeps the old behavior: an [AuthFailure] fails the operation
  /// permanently.
  ///
  /// ```dart
  /// SyncConfig(onAuthFailure: (_) async {
  ///   final ok = await auth.refresh();
  ///   return ok ? AuthRecovery.retry : AuthRecovery.pause;
  /// })
  /// ```
  final Future<AuthRecovery> Function(AuthFailure failure)? onAuthFailure;

  /// When a server assigns a real id to an entity created under a temporary
  /// one, also rewrite the declared reference fields of rows *already in
  /// local storage* that still point at the temporary id (not just queued
  /// operations, which are always rewritten).
  ///
  /// Costs one scan of each collection that declares `referenceFields`, per
  /// create whose id changes. Turn it off if your `LocalStore` already
  /// propagates id changes itself.
  final bool rewriteLocalReferences;

  /// How many recent `SyncEvent`s the engine keeps for
  /// `SyncInspector.recentEvents` / `historyFor`. `0` disables the history.
  final int eventHistoryLimit;
}
