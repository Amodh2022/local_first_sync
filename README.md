# offline_sync

A state-management-agnostic, local-first synchronization framework for Flutter/Dart.
Writes land in local storage immediately and are synced to a backend in the background,
with dependency-ordered operations, temporary-id → server-id rewriting, pluggable conflict
resolution, and a built-in diagnostic Sync Inspector.

> Package status: push-sync is the core; **opt-in pull-sync** landed via `PullableRemoteStore`.
> No CRDT merge — see [`DESIGN.md`](DESIGN.md) for the architecture write-up and staged
> roadmap. `InMemoryLocalStore`/`InMemoryRemoteStore` ship for tests and prototyping; a
> persistent `LocalStore` (e.g. Drift) and a REST `RemoteStore` are what you write before
> shipping — see [Production adapters](#production-adapters-what-you-still-need-to-write).
> The **queue** itself is already crash-safe out of the box via `PersistentSyncQueue`.

## Why

Most offline-first packages give you a local cache and a retry queue. What they don't give you:

- **Dependency-aware sync.** Save an `Order` and its `OrderItem`s while offline; the items
  wait for the order, and if the order's `create` gets a server-assigned id, every queued
  dependent operation has its reference fields rewritten automatically — before it ever hits
  the network.
- **A real reason when something is stuck.** `SyncInspector.explain(operation)` returns a
  human-readable sentence ("BLOCKED: waiting on dependency `op_42`, which failed with...")
  instead of a bare status enum.
- **Zero opinion about your state management.** The core has no Flutter, Bloc, Riverpod, or
  Provider dependency. `Collection<T>.watch()` is a plain `Stream<List<T>>` — wire it into
  whatever you already use.
- **A queue you can actually operate.** Pause and resume it, retry or cancel a single
  operation, purge completed ones, see it in one `SyncState` stream. Most packages give you
  a black box that either drains or doesn't.
- **Redundant work never leaves the device.** Eight offline edits to one record cost one
  request; a record created and deleted before either synced costs none at all.

## Install

```yaml
dependencies:
  offline_sync:
    path: ../offline_sync # or a git/pub dependency once published
```

## Core concepts

| Type | Role |
|---|---|
| `LocalStore<T>` | Your persistence layer (SQLite/Drift/Hive/...). Reads and reactive `watch*` streams always come from here. |
| `RemoteStore<T>` | Your backend client (REST/GraphQL/...). The engine is the *only* caller — app code never touches it directly. |
| `Serializer<T>` | Explicit `encode`/`decode`, no reflection — required so the engine can diff/replay payloads without knowing your model shape. |
| `Collection<T>` | The API you actually call: `save`, `delete`, `get`, `getAll`, `watch`, `watchById`. Local-first — writes never block on the network. |
| `SyncEngine` | Drains the queue with bounded concurrency, applies retries/backoff, resolves conflicts, rewrites temp ids into dependents. |
| `SyncInspector` | Read-only diagnostics: counts by status, `explain(operation)`, optional field redaction for sensitive payloads. |
| `OfflineSync` | The facade that wires the above together; the one object most apps construct. |

## Quick start

```dart
import 'package:offline_sync/offline_sync.dart';

class User implements Identifiable {
  User({required this.id, required this.name});
  @override
  final String id;
  final String name;
}

class UserSerializer implements Serializer<User> {
  @override
  Map<String, Object?> encode(User v) => {'id': v.id, 'name': v.name};
  @override
  User decode(Map<String, Object?> d) => User(id: d['id'] as String, name: d['name'] as String);
}

final sync = OfflineSync(
  config: const SyncConfig(
    maxConcurrentOperations: 4,
    retryPolicy: RetryPolicy(initialDelay: Duration(seconds: 1), maxDelay: Duration(minutes: 5)),
  ),
);

final users = sync.registerCollection<User>(
  name: 'users',
  localStore: MyDriftUserStore(db),   // your LocalStore<User> adapter
  remoteStore: MyRestUserStore(api),  // your RemoteStore<User> adapter
  serializer: UserSerializer(),
);

sync.start(); // reacts to connectivity changes + runs an initial pass

await users.save(User(id: 'u1', name: 'Ada'));   // visible via users.watch() instantly
final ada = await users.get('u1');
users.watch().listen((all) => print('users: $all'));
```

### Dependency-ordered writes + temporary ids

```dart
final orderOpId = await orders.save(Order(id: 'temp_order_1', customerId: 'c1'));
await orderItems.save(
  OrderItem(id: 'temp_item_1', orderId: 'temp_order_1', sku: 'ABC'),
  dependsOn: [orderOpId], // won't sync until the order does
);
```

`orders`'s `RemoteStore` is registered with `referenceFields: ['orderId']` on the
`OrderItem` collection's registration, so once the order's `create` returns a
server-assigned id, `TempIdRegistry` maps `temp_order_1 -> <server id>` and every
still-queued `OrderItem` operation's `orderId` is rewritten before it syncs. See
[`DESIGN.md` §6](DESIGN.md#6-dependency-model) for the exact propagation boundaries
(already-persisted local rows are **not** auto-rewritten — that's an adapter concern).

### Conflict resolution

```dart
sync.registerCollection<User>(
  name: 'users',
  localStore: localStore,
  remoteStore: remoteStore,
  serializer: UserSerializer(),
  conflictResolver: LastWriteWinsResolver<User>((u) => u.updatedAt),
  // or ServerWinsResolver(), ClientWinsResolver(), or a CustomResolver for field-level merges
);
```

### Live sync state (one stream for your whole status UI)

```dart
StreamBuilder<SyncState>(
  stream: sync.watchState(),
  builder: (context, snapshot) {
    final state = snapshot.data ?? const SyncState.initial();
    if (state.isSyncing) return const Text('Syncing…');
    if (!state.isOnline) return Text('Offline · ${state.unsynced} unsynced');
    if (state.failed > 0) return Text('${state.failed} failed — tap to retry');
    return Text('Synced at ${state.lastSyncedAt}');
  },
);
```

`SyncState` carries connectivity, `isSyncing`, `isPaused`, per-status counts
(`pending`/`syncing`/`retrying`/`failed`/`blocked`/`synced`), `unsynced`, `isUpToDate`,
`lastSyncedAt` and `lastError` — no polling, no manual refresh.

### A crash-safe queue

`InMemorySyncQueue` (the default) loses everything on restart, which means a user who
force-quits while offline loses their unsynced writes. `PersistentSyncQueue` writes
through to any storage you have:

```dart
final prefs = await SharedPreferences.getInstance();
final sync = OfflineSync(
  queue: await PersistentSyncQueue.open(
    JsonBlobOperationStore(
      readBlob: () async => prefs.getString('offline_sync.queue'),
      writeBlob: (json) => prefs.setString('offline_sync.queue', json),
    ),
  ),
);
```

For a real table (Drift, sqflite, Isar, Hive), implement `SyncOperationStore`'s four
methods against it — `SyncOperation.toJson`/`fromJson` do the encoding for you. An
operation that was in flight when the process died comes back `ready` and is re-sent
under its original `idempotencyKey`, which is what that key is for.

### Operating the queue

```dart
sync.pause();                          // e.g. on a 401, while you refresh the token
sync.resume();                         // writes kept queuing the whole time
await sync.retryOperation(opId);       // the "Retry" button next to a failed row
await sync.retryAllFailed();           // returns how many were requeued
await sync.cancelOperation(opId);      // dependents are blocked with a reason, not dropped
await sync.purgeCompleted();           // also runs automatically per SyncConfig
```

### Pull sync (opt-in)

Implement `PullableRemoteStore<T>` instead of `RemoteStore<T>` and the engine can bring
remote changes down as well as push local ones up:

```dart
class UserApi implements PullableRemoteStore<User> {
  @override
  Future<List<User>> fetchChanges({DateTime? since}) => _get('/users?since=$since');
  // ...create/update/delete as usual
}

await sync.pullNow();                                  // or SyncConfig(pullInterval: ...)
```

A pull **never overwrites an entity that still has unsynced work queued** — that write is
the user's and it hasn't reached the backend yet. The `PullCompleted` event reports how
many records were applied and how many were skipped for that reason.

### Priority, coalescing and rollback

```dart
await messages.save(msg, priority: 10);   // jumps ahead of 200 queued analytics events

// Coalescing is on by default (SyncConfig.coalesceOperations):
await notes.save(note.copyWith(text: 'a'));
await notes.save(note.copyWith(text: 'ab'));
await notes.save(note.copyWith(text: 'abc'));   // → one request, payload 'abc'

// Opt in to undoing an optimistic write the backend permanently rejected:
OfflineSync(config: const SyncConfig(rollbackOnPermanentFailure: true));
```

Coalescing never touches an operation that is already syncing/synced, or one another
operation depends on.

### Reachability, not "is wifi on"

```dart
final monitor = ReachabilityConnectivityMonitor(
  probe: () async {
    try {
      final res = await http.head(healthUrl).timeout(const Duration(seconds: 5));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  },
)..start();
final sync = OfflineSync(connectivity: monitor);
```

A captive-portal wifi, an expired VPN, or a backend that is simply down all report
"connected" to the OS. Driving sync off that is how a queue ends up in a retry storm.

### Diagnostics

```dart
final inspector = sync.inspector(redactedFields: {'authToken'});
final snapshot = await inspector.snapshot();
print('${snapshot.failed} failed, ${snapshot.blocked} blocked');
for (final op in snapshot.operations) {
  print(inspector.explain(op));
}
inspector.watch().listen((s) => updateSyncBadge(s));
```

## Performance: how to get the most out of it

The engine is built to make the *fast path cheap and the corner cases bounded* — but a few
things are on you as the integrator:

1. **Write a real `LocalStore`, not `InMemoryLocalStore`, for anything beyond tests.**
   `InMemoryLocalStore` holds everything in a `Map` with no indices and no persistence —
   fine for widget tests, wrong for app data. Back `LocalStore<T>` with an indexed database
   (Drift/sqlite3) so `getById`/`watchById` are O(1)/indexed lookups, not linear scans.

2. **Size `SyncConfig.maxConcurrentOperations` to your backend, not your CPU.** It bounds
   concurrent *in-flight network operations*, not local work — 3–6 is reasonable for a
   typical REST backend; raise it only if your backend can actually absorb more parallel
   writes. Dependent operations serialize through the dependency graph regardless of this
   value, so raising it never breaks ordering — it only widens how many independent chains
   drain at once.

3. **Keep `Serializer.encode`/`decode` allocation-light and reflection-free.** They're
   invoked on every `save`, on every retry replay, and on every reference-field rewrite —
   prefer hand-written or `json_serializable`-generated implementations over anything
   reflective (`dart:mirrors` isn't available in Flutter anyway, but ad hoc `toJson`
   re-derivation via `runtimeType` checks is just as costly).

4. **Declare `referenceFields` narrowly.** `TempIdRegistry.rewritePayload` only walks the
   fields you declare per collection — an empty or minimal list means the rewrite pass is a
   no-op fast path (checked before any map copy happens). Don't declare a field as a
   reference unless it actually holds another entity's id.

5. **Tune `RetryPolicy` deliberately.** `initialDelay`/`multiplier`/`maxDelay` govern how
   aggressively a flaky network is hammered; `maxAttempts` (default unbounded) should
   usually be set for anything that isn't safe to retry forever. Throw the specific
   `SyncFailure` subtype from your `RemoteStore` (`NetworkFailure`, `TimeoutFailure`,
   `ServerFailure(statusCode, ...)`, `ValidationFailure`, `AuthFailure`, `ConflictFailure`) —
   the engine's retry/backoff decision is driven entirely by `SyncFailure.retryable`, not by
   inspecting exception messages, so misclassifying an error (e.g. letting a raw `HttpException`
   escape as `UnknownFailure`) either wastes retries on a permanent failure or gives up on a
   transient one.

6. **Never fetch more than you need on the sync hot path.** Don't call `Collection.getAll()`
   inside a loop or a rebuild — subscribe to `watch()`/`watchById()` once and let the stream
   push updates. The engine itself drains the queue by status, not by loading the whole
   entity table.

7. **Batch related writes under one `dependsOn` chain rather than fan-out+poll.** Because
   independent operations already sync concurrently (bounded by `maxConcurrentOperations`),
   there's no need to manually stagger `save()` calls — enqueue them all and let the engine
   parallelize the independent ones while serializing the dependent ones correctly.

8. **Dispose what you construct.** `OfflineSync.dispose()` (and, if you built it directly,
   `ManualConnectivityMonitor.dispose()`) closes the underlying stream controllers — hold
   one `OfflineSync` per app/session, not one per screen.

No throughput numbers are asserted here — none have been benchmarked yet (see
[`DESIGN.md` §8](DESIGN.md#8-performance-strategy)); the guidance above is about correct
usage of the concurrency/indexing knobs the engine actually exposes, not marketing claims.

## Using it in a Clean Architecture app

`offline_sync` naturally slots in as **infrastructure that implements your domain-layer
repository interfaces** — it does not want to *be* your domain layer, and it has no opinion
about your presentation/state-management layer. A typical layering:

```
Presentation (widgets, view-models / BLoC / Riverpod notifiers / controllers)
        │  depends on
Domain (entities, use cases, repository interfaces — pure Dart, no offline_sync import)
        │  implemented by
Data (repository implementations — the only layer that imports offline_sync)
        │  wraps
offline_sync (Collection<T>, OfflineSync, SyncInspector)
        │  backed by
Your LocalStore<T> / RemoteStore<T> adapters (Drift, REST client, ...)
```

The key discipline: **your domain layer never imports `package:offline_sync`.** It defines
its own repository interface in terms of your own entities; the data layer's implementation
is the only place that talks to `Collection<T>`, translating between your domain entities and
the DTOs `Serializer<T>` encodes/decodes.

```dart
// domain/entities/todo.dart — pure Dart, no offline_sync dependency
class Todo {
  const Todo({required this.id, required this.title, required this.done});
  final String id;
  final String title;
  final bool done;
}

// domain/repositories/todo_repository.dart — the port your use cases depend on
abstract interface class TodoRepository {
  Future<void> add(Todo todo);
  Future<void> toggle(Todo todo);
  Stream<List<Todo>> watchAll();
}

// domain/usecases/toggle_todo.dart — orchestration, still offline_sync-free
class ToggleTodo {
  ToggleTodo(this._repo);
  final TodoRepository _repo;
  Future<void> call(Todo todo) => _repo.toggle(todo);
}

// data/models/todo_dto.dart — the offline_sync-facing model
class TodoDto implements Identifiable {
  TodoDto({required this.id, required this.title, required this.done});
  @override
  final String id;
  final String title;
  final bool done;

  Todo toDomain() => Todo(id: id, title: title, done: done);
  factory TodoDto.fromDomain(Todo t) => TodoDto(id: t.id, title: t.title, done: t.done);
}

class TodoDtoSerializer implements Serializer<TodoDto> {
  @override
  Map<String, Object?> encode(TodoDto v) => {'id': v.id, 'title': v.title, 'done': v.done};
  @override
  TodoDto decode(Map<String, Object?> d) =>
      TodoDto(id: d['id'] as String, title: d['title'] as String, done: d['done'] as bool);
}

// data/repositories/offline_sync_todo_repository.dart — the ONLY layer importing offline_sync
class OfflineSyncTodoRepository implements TodoRepository {
  OfflineSyncTodoRepository(this._collection);
  final Collection<TodoDto> _collection; // built via OfflineSync.registerCollection<TodoDto>

  @override
  Future<void> add(Todo todo) => _collection.save(TodoDto.fromDomain(todo));

  @override
  Future<void> toggle(Todo todo) =>
      _collection.save(TodoDto.fromDomain(Todo(id: todo.id, title: todo.title, done: !todo.done)));

  @override
  Stream<List<Todo>> watchAll() =>
      _collection.watch().map((dtos) => dtos.map((d) => d.toDomain()).toList());
}
```

Composition root (wherever you assemble dependencies — a DI container, a `main.dart`
provider tree, etc.):

```dart
final sync = OfflineSync(config: const SyncConfig(maxConcurrentOperations: 4));
final todoCollection = sync.registerCollection<TodoDto>(
  name: 'todos',
  localStore: DriftTodoStore(db),   // adapter, lives in data/ or infra/
  remoteStore: RestTodoStore(api),  // adapter, lives in data/ or infra/
  serializer: TodoDtoSerializer(),
);
sync.start();

final todoRepository = OfflineSyncTodoRepository(todoCollection);
final toggleTodo = ToggleTodo(todoRepository);

// Presentation layer depends on TodoRepository/ToggleTodo, never on offline_sync directly.
```

Why this pays off:

- **Testability.** Domain and presentation tests never construct an `OfflineSync`; they mock
  `TodoRepository`. Data-layer tests exercise `OfflineSyncTodoRepository` against
  `InMemoryLocalStore`/`InMemoryRemoteStore` fakes — no real database or network needed
  (this is exactly how this package's own test suite is structured; see `DESIGN.md` §9).
- **Swappable persistence/transport.** Moving from a REST backend to GraphQL, or from Drift
  to another database, only touches the `LocalStore`/`RemoteStore` adapters — the repository
  contract and everything above it is untouched.
- **State-management independence, twice over.** Because the domain repository interface —
  not `Collection<T>` — is what presentation code depends on, you also get to swap BLoC for
  Riverpod (or add both, for different screens) without touching the data layer at all.
- **The Sync Inspector stays a data/infra concern.** Expose it through a narrow
  domain-facing port (e.g. a `SyncStatusRepository` wrapping `SyncInspector`) if a settings
  screen needs to show sync health — don't leak `SyncInspector`/`SyncOperation` types into
  domain or presentation code.

## Production adapters (what you still need to write)

`InMemoryLocalStore<T>` and `InMemoryRemoteStore<T>` are test/prototyping doubles, not
production adapters (per [`DESIGN.md`](DESIGN.md#3-core-domain-model-mvp)). Before shipping:

- Implement `LocalStore<T>` against real persistence (Drift/sqlite3 is the intended first
  adapter — `offline_sync_drift`, not yet built) so writes/queue state survive app restarts.
- Implement `RemoteStore<T>` against your actual backend, throwing the appropriate
  `SyncFailure` subtype (see [Performance](#performance-how-to-get-the-most-out-of-it) point 5)
  rather than letting raw HTTP exceptions escape.
- Swap `InMemorySyncQueue` for `PersistentSyncQueue` with a real `SyncOperationStore`, or
  unsynced writes die with the process.
- If you don't have a platform connectivity plugin wired up, `ManualConnectivityMonitor`
  works but must be driven explicitly (`setOnline()`/`setOffline()`). For a real app use
  `ReachabilityConnectivityMonitor` with a probe against your own backend, optionally
  re-checked from a `connectivity_plus` stream (device network state is not the same thing
  as "the backend is reachable" — see `DESIGN.md` §8/AGENTS.md §13).

## Development

```bash
flutter pub get
flutter test                                                     # full suite
flutter test test/sync/sync_engine_test.dart                     # one file
flutter test --plain-name "a permanently failed operation blocks its dependents"
flutter analyze
```

The `example/` directory has both a Flutter app (`flutter run`, shows the
PENDING → SYNCING → SYNCED lifecycle with an embedded Sync Inspector) and a plain-Dart
walkthrough of every behavior (`dart run bin/offline_sync_example.dart`).

See [`CLAUDE.md`](CLAUDE.md) for repository layout conventions and
[`DESIGN.md`](DESIGN.md) for the architecture rationale and staged roadmap (CRDT-style
merge and the state-management adapter packages remain out of scope).
