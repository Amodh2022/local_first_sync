/// Lifecycle states for a [SyncOperation].
enum SyncStatus {
  /// Just created, not yet handed to the queue. Transient — operations
  /// enqueued via [Collection] start at [ready] or [blocked].
  created,

  /// Persisted in the queue but not yet eligible to sync (reserved for
  /// future explicit-hold use cases; MVP goes straight to ready/blocked).
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
  conflict,

  /// Explicitly cancelled by the application; never synced.
  cancelled,
}
