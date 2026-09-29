## 0.1.0

First release.

- `LocalFirstDatabase`: a Drift database with three tables: entities, the
  sync queue, and engine metadata. The generated code ships with the package, so
  your app doesn't need build_runner for it.
- `DriftLocalStore<T>`: a persistent `LocalStore` that stores each record as
  its `Serializer<T>` JSON. Many collections can share one table.
  `watchAll`/`watchById` are Drift watch queries, and `reassignId` runs in a
  single transaction.
- `DriftOperationStore`: a `SyncOperationStore` that writes one row per
  operation, for `PersistentSyncQueue`.
- `DriftMetadataStore`: a `SyncMetadataStore` over a third table, so pull
  cursors survive app restarts.
- `DriftTableLocalStore<T, Tbl, Row>`: a base class that implements
  `LocalStore` over your own typed Drift table, for models you want to query
  in SQL. You supply `table`, `idColumn`, `toRow` and `fromRow`, and
  optionally `orderBy`.
