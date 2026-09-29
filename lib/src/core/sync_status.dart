/// Lifecycle states for a [SyncOperation].
enum SyncStatus {
  /// Just created, not yet handed to the queue. Transient — operations
  /// enqueued via [Collection] start at [ready] or [blocked].
  @Deprecated('Never set by the engine. Will be removed in 1.0.')
  created,

  /// Reserved for an explicit-hold state that was never built; operations
  /// go straight to [ready] or [blocked].
  @Deprecated('Never set by the engine. Will be removed in 1.0.')
  queued,

  /// Eligible to sync on the next drain.
  ready,

  /// Currently being sent to the remote adapter.
  syncing,

  /// Successfully applied on the backend.
  synced,

  /// Failed with a non-retryable error. Terminal until manual intervention.
  failed,

  /// Failed with a retryable error; waiting for [SyncOperation.nextRetryAt].
  retry,

  /// Waiting on a dependency (see [SyncOperation.dependencyIds]) that has not
  /// yet reached [synced].
  blocked,

  /// The remote value diverged from the local value in a way the configured
  /// [ConflictResolver] had to adjudicate.
  @Deprecated('Never set by the engine. Will be removed in 1.0.')
  conflict,

  /// Explicitly cancelled by the application; never synced.
  cancelled,
}
