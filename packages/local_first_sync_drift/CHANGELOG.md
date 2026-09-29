## 0.1.0

First release.

- `LocalFirstDatabase`: a Drift database with two tables, one for entities
  and one for the sync queue. The generated code ships with the package, so
  your app doesn't need build_runner for it.
- `DriftLocalStore<T>`: a persistent `LocalStore` that stores each record as
  its `Serializer<T>` JSON. Many collections can share one table.
  `watchAll`/`watchById` are Drift watch queries, and `reassignId` runs in a
  single transaction.
- `DriftOperationStore`: a `SyncOperationStore` that writes one row per
  operation, for `PersistentSyncQueue`.
