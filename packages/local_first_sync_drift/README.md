# local_first_sync_drift

[Drift](https://pub.dev/packages/drift) persistence for
[`local_first_sync`](https://pub.dev/packages/local_first_sync):

- **`DriftLocalStore<T>`**: a persistent `LocalStore`, so your data survives app
  restarts.
- **`DriftOperationStore`**: a `SyncOperationStore` for `PersistentSyncQueue`, so
  unsynced writes survive a force-quit. It writes one row per operation, so a
  queue of thousands costs no more per change than a queue of ten.

Both use one `LocalFirstDatabase` that ships with its generated code. Your app
doesn't need build_runner or a table definition for each model, because the
`Serializer<T>` you already give `OfflineSync` is all this package needs.

## Install

```yaml
dependencies:
  local_first_sync: ^0.2.0
  local_first_sync_drift: ^0.1.0
  drift_flutter: ^0.2.0 # Flutter apps; see "Choosing an executor"
```

## Setup

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_drift/local_first_sync_drift.dart';

final db = LocalFirstDatabase(driftDatabase(name: 'local_first_sync'));

final sync = OfflineSync(
  queue: await PersistentSyncQueue.open(DriftOperationStore(db)),
);

final todos = sync.registerCollection<Todo>(
  name: 'todos',
  localStore: DriftLocalStore(db, collection: 'todos', serializer: const TodoSerializer()),
  remoteStore: myTodoRemoteStore, // e.g. RestRemoteStore from local_first_sync_rest
  serializer: const TodoSerializer(),
);
```

Create one `LocalFirstDatabase` when the app starts and share it between every
store. Give each collection its own `collection:` name. Using the same name you
pass to `registerCollection` keeps things easy to follow.

## Choosing an executor

`LocalFirstDatabase` takes any Drift `QueryExecutor`, and this package itself
doesn't import any platform code:

| Platform | Executor |
|---|---|
| Flutter (mobile, desktop, web) | `driftDatabase(name: ...)` from [`drift_flutter`](https://pub.dev/packages/drift_flutter) |
| Dart VM, CLI or server | `NativeDatabase(File(...))` from `package:drift/native.dart` |
| Tests | `NativeDatabase.memory()` |
| Web without Flutter | `WasmDatabase.open(...)` from `package:drift/wasm.dart` |

## How data is stored

| Table | Columns |
|---|---|
| `local_first_entities` | `collection`, `id`, `json`, `updated_at`; primary key `(collection, id)` |
| `local_first_operations` | `operation_id` (primary key), `json` (the `SyncOperation.toJson` output) |

`insert` and `update` both upsert. `getAll`/`watchAll` return records in the
order they were inserted, the same as `InMemoryLocalStore`.

**Limitation:** a record's fields are stored as a JSON string, not as columns,
so you can't filter or index by a field in SQL. Load the collection with
`getAll`/`watchAll` and filter in Dart. If a model needs heavy querying,
implement `LocalStore<T>` against your own typed Drift table instead. The
interface has only eight methods.

**Temporary ids:** when the server gives a record a different id,
`reassignId` swaps the local row in one transaction. Other rows that
*reference* the old id, such as an `orderId` field in another collection, are
not rewritten locally. The core rewrites only operations that are still
queued (see the core README).

## Schema changes

`LocalFirstDatabase.schemaVersion` is 1. A future version of this package that
changes the schema will include its own migration.
