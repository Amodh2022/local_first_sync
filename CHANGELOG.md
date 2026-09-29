## 0.2.0

- **Idempotency keys reach the backend.** New opt-in `IdempotentRemoteStore<T>`:
  when a remote store implements it, the engine calls `createWithKey`/
  `updateWithKey`/`deleteWithKey` with the operation's `idempotencyKey`, which
  is stable across retries, coalescing and restarts. Before this, the key was
  persisted but never passed to the remote store, so a write re-sent after a
  crash could be applied twice.
- `InMemoryRemoteStore` implements `IdempotentRemoteStore`. A repeated key
  returns the first result without applying the write again, and
  `receivedIdempotencyKeys`/`appliedWrites` expose what happened to tests.
- **Breaking (only if you implement `CollectionBinding` yourself):**
  `remoteCreate`/`remoteUpdate`/`remoteDelete` take an optional named
  `idempotencyKey`. Apps that use `OfflineSync.registerCollection` are
  unaffected.
- First-party adapters: `local_first_sync_drift` (persistent `LocalStore` and
  `SyncOperationStore` on Drift) and `local_first_sync_rest` (`RemoteStore` on
  `package:http`). They are published as separate packages, so this package
  still has no runtime dependencies.

## 0.1.0

First release. Local-first sync for Dart and Flutter: writes land in local
storage immediately and are pushed to a backend in the background.

- **Local-first API.** `Collection<T>` with `save`/`delete`/`get`/`getAll`/
  `watch`/`watchById`. Writes never block on the network.
- **Dependency-aware queue.** Pass an earlier operation's id as `dependsOn` and
  the dependent waits for it. A dependency that fails permanently *blocks* its
  dependents — never silently drops them — with a human-readable reason.
- **Temporary ids.** When the server assigns a different id on create, queued
  dependents have their declared `referenceFields` rewritten before they send.
- **Crash-safe queue.** `PersistentSyncQueue` writes through to any
  `SyncOperationStore`; an operation interrupted mid-flight is re-sent under its
  original idempotency key.
- **Pull sync (opt-in).** Implement `PullableRemoteStore` and call `pullNow()`.
  A pull never overwrites an entity that still has unsynced local work queued.
- **Operation coalescing.** N offline edits to one record cost one request;
  create-then-delete before either syncs costs none.
- **Queue control.** `pause`/`resume`, `retryOperation`, `retryAllFailed`,
  `cancelOperation`, `purgeCompleted`, plus retention of completed operations.
- **Ordering guarantees.** Priority first, then strict FIFO; two operations on
  the same entity never run concurrently.
- **Retry policy** with exponential backoff, jitter, a per-operation timeout,
  and a timer that actually fires when the backoff elapses.
- **Conflict resolution.** `ServerWins`, `ClientWins`, `LastWriteWins`, and
  `CustomResolver` for field-level merges.
- **Optimistic rollback** (opt-in) when the backend permanently rejects a write.
- **`SyncState`** — one stream for a status bar: connectivity, in-flight,
  per-status counts, `lastSyncedAt`, `lastError`.
- **`SyncInspector`** — read-only diagnostics with a plain-English
  `explain(operation)` and optional payload redaction.

Ships with in-memory `LocalStore`/`RemoteStore` implementations for tests and
prototyping. Production adapters (Drift, REST) are yours to write — see the
README.
