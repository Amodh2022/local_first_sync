# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`local_first_sync` is a state-management-agnostic, local-first synchronization framework for
Flutter/Dart, built under the product/engineering spec in `.claude/agents/package_create.md`
(AGENTS.md). The competitive research and architecture proposal that spec required before
any implementation lives in `DESIGN.md` — read it first for the domain model, sync state
machine, queue/dependency/conflict design, and the MVP scope decisions that shaped the code.

**This is a pure Dart package** (not a Flutter package, not a melos monorepo): `lib/` has
zero Flutter imports and the pubspec has no runtime dependencies at all, so it works in
Flutter, server, and CLI Dart alike. Use `dart`, not `flutter`, for everything at the repo
root. `example/` is a separate Flutter app that depends on this package by path — use
`flutter` there.

Do not introduce a `dart:io`/`dart:html` import or any runtime dependency in `lib/` without
a deliberate decision: it would drop platform tags on pub.dev (currently the maximum set)
and break the dependency-free claim in the README.

## Commands

- `dart pub get` — install dependencies.
- `dart test` — run the full suite (67 tests).
- `dart test test/sync/sync_engine_test.dart` — run a single test file.
- `dart test --plain-name "a permanently failed operation blocks its dependents"` —
  run a single test by name.
- `dart analyze` — static analysis (`analysis_options.yaml`, based on `package:lints`).
- `dart format .` — required before publishing; pana scores formatting.
- `dart pub publish --dry-run` — publish readiness. Must be warning-free.
- In `example/`: `flutter run`, `flutter test`, and
  `dart run bin/local_first_sync_example.dart` for the console walkthrough.

## Architecture

Public API is exported from `lib/local_first_sync.dart`; everything else lives under `lib/src/`,
organized by responsibility (mirrors `test/`):

- `core/` — `SyncOperation`, `SyncStatus`, `SyncEvent`s, `SyncFailure` types, `RetryPolicy`,
  `Identifiable`. Pure data/enums, no I/O.
- `serialization/` — `Serializer<T>` (explicit encode/decode, no reflection).
- `storage/` — `LocalStore<T>` interface + `InMemoryLocalStore<T>` (test/prototyping only;
  a real adapter like `local_first_sync_drift` is future work, not yet built).
- `remote/` — `RemoteStore<T>` interface, the opt-in `PullableRemoteStore<T>` (pull sync),
  and `InMemoryRemoteStore<T>` (same caveat; a REST adapter is future work).
- `queue/` — `SyncQueue` interface + `InMemorySyncQueue` (tests/prototyping) and
  `PersistentSyncQueue` (write-through to a `SyncOperationStore`; `InMemoryOperationStore`
  and `JsonBlobOperationStore` ship, a real table adapter is yours). Enqueue rejects cyclic
  dependencies via `DependencyGraph.wouldCreateCycle`. `OperationCoalescer` collapses
  redundant queued writes on one entity at enqueue time.
- `dependency/` — `DependencyGraph` (pure functions over a queue snapshot: cycle detection,
  blocked-reason computation) and `TempIdRegistry` (temp-id → server-id mapping + declared-
  reference-field payload rewriting).
- `conflict/` — `ConflictResolver<T>` + built-in `ServerWinsResolver`, `ClientWinsResolver`,
  `LastWriteWinsResolver`, `CustomResolver`.
- `connectivity/` — `ConnectivityMonitor` interface, `ManualConnectivityMonitor`, and
  `ReachabilityConnectivityMonitor` (polls a caller-supplied probe, so "online" means the
  backend answered — core still has no platform connectivity dependency).
- `sync/` — `SyncEngine` (the state machine: drains ready/retry operations with bounded
  concurrency, handles temp-id reassignment + dependent payload rewriting, conflict
  routing, retry/backoff, and permanent-failure → dependent-blocking), `CollectionBinding`
  (type-erased engine-facing surface) / `TypedCollectionBinding<T>` (the concrete wiring of
  a `LocalStore`+`RemoteStore`+`Serializer` into that surface), `SyncConfig`, and
  `SyncState` (the one-object summary `OfflineSync.watchState()` streams). The engine also
  owns queue operation: `pause`/`resume`, `retryOperation`/`retryAllFailed`,
  `cancelOperation`, `purgeCompleted`, and `pullNow`.
- `repository/` — `Collection<T>`, the local-first developer-facing API (`save`, `delete`,
  `get`, `getAll`, `watch`, `watchById`). Writes go to `LocalStore` immediately and
  independently enqueue a `SyncOperation`; callers never wait on the network.
- `inspector/` — `SyncInspector`, a read-only diagnostic view over the queue (counts by
  status, human-readable `explain(operation)`, optional field redaction).
- `local_first_sync_facade.dart` — `OfflineSync`, the single object most apps construct:
  `registerCollection<T>(...)` wires a collection's storage/remote/serializer/conflict
  resolver into both the `Collection` apps use and the engine's binding registry.

### Key design decisions (see DESIGN.md for the reasoning)

- **Dependency-aware sync**: `Collection.save`/`delete` return an `operationId`; pass those
  as `dependsOn` on a later `save` to make one entity's sync wait on another's (e.g.
  `Order` → `OrderItem`). A dependency's permanent failure blocks — never silently drops —
  its dependents, with a human-readable reason surfaced via `SyncInspector.explain`.
- **Temporary IDs**: an entity created offline keeps whatever id the app assigned (e.g.
  `temp_order_1`) until its `create` operation syncs; if the server returns a different id,
  `TempIdRegistry` records the mapping and the engine rewrites any *already-queued*
  dependent operation's declared `referenceFields` to point at the real id. Local rows an
  adapter has already persisted with the old id are **not** automatically rewritten — that
  propagation is left to the `LocalStore` adapter, a known MVP boundary.
- **Coalescing**: `Collection` folds a new write into redundant queued ones for the same
  entity (`SyncConfig.coalesceOperations`, on by default) — N offline edits cost one
  request, create-then-delete costs none. It never touches an operation that is already
  syncing/synced or that another operation depends on.
- **Queue durability**: `PersistentSyncQueue` + a `SyncOperationStore` is what makes a
  force-quit while offline non-destructive; an operation that was `syncing` at crash time
  is restored as `ready` and re-sent under its original `idempotencyKey`.
- **Drain order**: operations sort by `priority` (desc) then strictly FIFO by `createdAt`,
  and two operations on the *same* entity never run in one batch — concurrent writes to one
  record would race and the loser would overwrite the winner.
- **Scope**: push-sync is the core; pull-sync is opt-in per collection via
  `PullableRemoteStore` and never overwrites an entity with unsynced queued work. No CRDTs
  and no state-management adapters (`local_first_sync_bloc`, etc.) yet — see DESIGN.md §10 for
  the staged plan and what's deliberately deferred.
