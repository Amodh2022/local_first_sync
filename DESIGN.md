# offline_sync — Competitive Research & Architecture Proposal

Status: **Step 1–2 deliverable per `.claude/agents/package_create.md` §49/§52.**
This document is a research + architecture proposal only. No implementation code has
been written yet, per the agent's explicit rule: *"Do NOT start implementing the
package immediately... Then stop and wait for approval before implementing."*

---

## 1. Existing package comparison

| Package | Approach | Queue/retry | Conflict resolution | Dependency ordering | Temp IDs | Inspector | Maintenance |
|---|---|---|---|---|---|---|---|
| **brick_offline_first** (greenbits) | SQLite local store, code-gen repositories, REST/GraphQL providers | SQLite-backed request queue, resent on reconnect | None built-in (app-defined) | No | No | No | Mature but slow-moving (~10mo since last publish), 116 likes |
| **PowerSync** | Server-managed sync streams (Postgres/MySQL/MongoDB/SQL Server) → client SQLite mirror | Managed upload queue on client | Built-in, but backend-driven (needs PowerSync Service + specific DB) | Not exposed to app | Not applicable (server owns IDs) | Has a web dashboard, not embeddable in-app | Commercial, actively developed, but locks you into their hosted service + supported DBs |
| **syncly_flutter** | Durable SQLite outbox + pluggable `SyncTransport` | Persisted exponential backoff, idempotency keys | server/local/lastWrite/merge/manual | Not mentioned | Not mentioned | Not mentioned | Very new (v0.1.0, 23 days old, 117 downloads) |
| **synclayer** | Isar-based collections + background sync engine | Retry + ordering in "Queue Manager" | last-write-wins/server/client + custom merge | Partial ("operation ordering") but not dependency-graph-aware | Not documented | Not documented | Actively marketed, but "approaching production ready", failing tests, single verified publisher, unproven |
| **pocketsync_flutter** | SQLite + Socket.IO real-time propagation | Not documented (no backoff mentioned) | LWW/server/client/custom | No | No | No | Alpha, explicitly "not reliable for production", 93 downloads |
| **offline_sync_engine** | Vector-clock CRDT merge, adapter-based local/cloud sources | Log-replay based, idempotent apply | Deterministic CRDT merge (dominant-wins / field merge) | Implicit via vector clocks, not app-visible | Not documented | Not documented | New, small, adapters only sketched |
| **dynos_sync** | Claims 50k+ writes/sec, delta-pulls | Not verified | Not documented | Not documented | Not documented | Not documented | Marketing-heavy pub description, unverified claims |
| Existing pub.dev **`offline_sync`** | Generic offline-first data manager | Basic | Basic | No | No | No | 34 likes — **name collision to be aware of**, not a technical concern |

### What we should NOT build
- A code-generation-first framework like Brick (`@OfflineFirst` annotations, generated repositories). It's powerful but couples the framework to build_runner and a specific serialization story, and none of our target adapters need that to work well.
- A hosted/managed sync service like PowerSync. That's a legitimate but entirely different product (infra + billing), not a Dart package.
- A CRDT-only engine. CRDTs solve automatic merge for specific data shapes but hide a lot of complexity from the developer and don't help with dependency-ordered REST operations (an `Order` → `OrderItem` → `Payment` chain isn't naturally CRDT-shaped). We should support pluggable conflict resolvers, not force CRDT semantics.

### Remaining ecosystem gaps (validated by the table above)
1. **No package combines dependency-aware queue ordering with temporary-ID reference rewriting.** Every competitor either ignores this (Brick, PocketSync, SyncLayer) or hides it inside CRDT semantics (offline_sync_engine).
2. **No package ships a real, in-app Sync Inspector.** PowerSync has a web dashboard tied to their hosted service; nobody else has anything.
3. **No package is state-management-agnostic by explicit design.** All competitors assume you use their repository/collection API directly; none document BLoC/Riverpod/Provider/GetX adapters as first-class, separately-versioned packages.
4. **"Why isn't this synced?" style human-readable diagnostics do not exist anywhere in this list.** Failures are generally exposed as raw exceptions or status enums only.
5. **Field-level conflict resolution is claimed by several (synclayer, syncly) but dependency-graph-aware conflict propagation (parent fails → block children, expose reason) is undocumented everywhere.**

### Recommended differentiators (in priority order)
1. **Dependency-aware synchronization** with automatic temporary-ID reference replacement — the clearest, most defensible technical gap.
2. **Sync Inspector** as an embeddable, in-app diagnostic surface (not just a status enum) — directly addresses gap #2/#4.
3. **True state-management independence** as a hard architectural constraint (core has zero Flutter/state-mgmt deps), with thin, separately versioned adapter packages — addresses gap #3.
4. **Human-readable "why isn't this synced" explanations** surfaced through the same event/inspector system.
5. Field-level conflict resolution and safe operation coalescing as secondary differentiators — competitive parity with synclayer/syncly, done more carefully (with correctness guarantees the others don't document).

We will **not** try to out-perform PowerSync's managed sync-stream model or out-CRDT offline_sync_engine — those are different bets. Our bet is: **best-in-class queue correctness (dependencies, temp IDs, crash recovery) + best-in-class developer visibility (inspector, explanations) + genuine framework neutrality.**

---

## 2. Proposed architecture

Package family (per AGENTS.md §1.1 — this repo will initially build **only** `offline_sync_core` and, once stable, `offline_sync_drift` + `offline_sync_rest`; the state-management adapters come later per the phased workflow):

```
offline_sync_core     — pure Dart, zero Flutter/state-mgmt deps
offline_sync_drift    — Drift-backed LocalStore implementation
offline_sync_rest     — REST-backed RemoteStore implementation

offline_sync_bloc / _riverpod / _provider / _getx  — later, thin adapters
```

Given this repo is a single Flutter project (not yet a melos/monorepo), the MVP will
live under `lib/src/...` as described in AGENTS.md §45, structured so it can be
extracted into a `packages/offline_sync_core` melos workspace later without an API
rewrite — i.e. we keep Drift/REST-specific code physically isolated from day one even
before it is split into separate pub packages.

### Layering (per AGENTS.md §4)

```
Presentation
    |
State Management            (out of scope for MVP)
    |
Repository / Collection API  (Collection<T>)
    |
Synchronization Domain       (SyncEngine)
    |
+-------+-------+-------+-------+
|       |       |       |       |
Queue  Conflict Dependency Retry
|       |       |       |
+-------+-------+-------+-------+
    |
Persistence Abstraction       (LocalStore<T>)
    |
Local Database                (Drift adapter, later)
```

---

## 3. Core domain model (MVP)

```dart
abstract interface class LocalStore<T> {
  Future<T?> getById(String id);
  Future<List<T>> getAll();
  Future<void> insert(T item);
  Future<void> update(T item);
  Future<void> delete(String id);
  Stream<List<T>> watchAll();
  Stream<T?> watchById(String id);
}

abstract interface class RemoteStore<T> {
  Future<T> create(T item);
  Future<T> update(T item);
  Future<void> delete(String id);
  // fetch()/pull sync deferred to a later milestone (§20 Pull Synchronization)
}

abstract interface class Serializer<T> {
  Map<String, dynamic> encode(T value);
  T decode(Map<String, dynamic> data);
}

class Collection<T> {
  Future<T?> get(String id);
  Future<List<T>> getAll();
  Future<void> save(T item);      // insert-or-update, local-first
  Future<void> delete(String id);
  Stream<List<T>> watch();
  Stream<T?> watchById(String id);
}
```

`Collection<T>` is the only object most apps touch. It writes to `LocalStore<T>`
synchronously-from-the-caller's-perspective (immediately visible via `watch()`), then
enqueues a `SyncOperation` — it never talks to `RemoteStore<T>` directly.

### MVP scope decision
`fetch()`/pull-sync and CRDT-style merge are explicitly **out of MVP scope** (per
AGENTS.md §20, deferred). MVP is push-sync only: local mutation → queue → remote.
Pull sync is a separate milestone once the push path is proven correct and benchmarked.

---

## 4. Sync state machine

```
CREATED → QUEUED → READY → SYNCING → SYNCED
                                   ↘ FAILED → RETRY → READY
READY → BLOCKED (dependency not yet synced) → READY (on dependency success)
any non-terminal → CANCELLED (explicit app action only)
SYNCING → CONFLICT (resolver invoked; outcome re-enters READY or SYNCED)
```

Rules:
- Transitions are computed by `SyncEngine`, persisted by `SyncQueue` in the same
  local transaction as any queue mutation — never held only in memory.
- `FAILED` only transitions to `RETRY` for retryable errors (§12); non-retryable
  errors terminate at `FAILED` and must be surfaced via the Inspector/event stream
  for manual handling — never retried forever.

---

## 5. Queue model

```dart
class SyncOperation {
  final String operationId;      // stable across retries
  final String idempotencyKey;   // sent to backend, dedupes at-least-once delivery
  final String collection;
  final String entityId;         // may be a temporary ID
  final SyncOperationType type;  // create | update | delete
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  DateTime updatedAt;
  int retryCount;
  SyncStatus status;
  List<String> dependencyIds;    // other operationIds this depends on
  String? lastError;
  DateTime? nextRetryAt;
}
```

- Persisted via `LocalStore`'s own database (same Drift/SQLite instance as entity
  data) so entity write + queue insert happen in one transaction — this is the
  crash-recovery guarantee from AGENTS.md §30.
- Indexed on: `status`, `nextRetryAt`, `collection`, `entityId`, `dependencyIds`
  (AGENTS.md §31).

---

## 6. Dependency model

- Each `SyncOperation` optionally lists `dependencyIds`.
- `DependencyGraph` is a pure in-memory/query-derived view over the queue table — it
  is not separately persisted state that can drift from the queue.
- Cycle detection runs at enqueue time (reject/flag, never silently accept a cycle).
- On dependency `FAILED`, dependents transition `READY → BLOCKED` with a recorded
  reason (`dependencyId`, dependency's `lastError`) surfaced through §25's
  human-readable explanation format.
- Temporary IDs: a `TempIdRegistry` maps `tempId → serverId` once a `create`
  operation succeeds. Before syncing a dependent operation, its payload is passed
  through a reference-rewrite step that walks *declared* foreign-key fields (the app
  declares which fields are references, e.g. via `Serializer` metadata or explicit
  config) — never naive string replacement, since a temp ID could coincidentally
  match unrelated payload text.

---

## 7. Conflict model

```dart
abstract interface class ConflictResolver<T> {
  ConflictResolution<T> resolve(T local, T remote, ConflictContext context);
}
```

- Built-in strategies: `serverWins`, `clientWins`, `lastWriteWins` (needs a
  reconcilable timestamp/version field — documented as a requirement, not assumed).
  `custom` takes an app-supplied resolver.
- Field-level resolution is modeled as a `custom` resolver that returns a per-field
  merged value; the core does not special-case field-level merge, keeping the
  abstraction single-purpose (AGENTS.md §17).
- Every conflict, resolved or not, emits a `ConflictDetected` event (AGENTS.md §23)
  — conflicts are never silently swallowed even when auto-resolved.

---

## 8. Performance strategy

- Bounded worker concurrency (`SyncConfig.maxConcurrentOperations`), default chosen
  from benchmarks (not guessed) once the engine exists.
- Independent operations sync concurrently; dependent chains preserve order via the
  dependency graph, not via a global lock.
- No `getAll()`-style full-table loads on the sync hot path — queue draining uses
  indexed, paginated queries (`status = READY ORDER BY createdAt LIMIT N`).
- Reactive streams diff at the entity/query level, not by re-emitting entire
  collections (AGENTS.md §21).
- Benchmarks land in `benchmark/` per AGENTS.md §41 before any performance claim is
  written in docs; no numbers are asserted in this document because none have been
  measured yet.

---

## 9. Testing strategy

Unit-level (per AGENTS.md §43), organized to mirror `lib/src/`:
`test/queue`, `test/sync`, `test/dependency`, `test/conflict`, `test/repository`,
plus `test/integration` for the canonical scenario:
offline mutation → app restart → still offline → network returns → sync →
verify remote + local state match.

Stress scenarios (AGENTS.md §44) are tracked but scheduled after the MVP unit suite
is green — no benchmark/stress work happens before correctness is established.

---

## 10. Proposed MVP scope (Step 3–6 of AGENTS.md §49)

In order, each step gated on the previous one's tests passing:

1. **Core interfaces**: `LocalStore<T>`, `RemoteStore<T>`, `Serializer<T>`,
   `Collection<T>`, `SyncOperation`, `SyncStatus`, `SyncEvent` — no behavior yet.
2. **In-memory `LocalStore`** (test double) + **`Collection<T>`** wired to it, so the
   local-first read/write/watch path is provable before persistence exists.
3. **Persistent `SyncQueue`** semantics (enqueue, dequeue-by-status, transactional
   insert) — using an in-memory fake persistence first, real Drift table later.
4. **`SyncEngine`** lifecycle: state machine, retry/backoff, bounded concurrency —
   against an in-memory `RemoteStore` fake, so behavior is testable without a
   database or network.
5. **Dependency graph + temporary IDs** on top of the engine.
6. **Conflict resolver abstraction** with built-in strategies.
7. Only then: **`offline_sync_drift`** (real persistence) and **`offline_sync_rest`**
   (real network) as the first concrete adapters — per AGENTS.md §49 Steps 6–7.
8. **Sync Inspector** (read-only view over engine/queue state + event log).

State-management adapters (BLoC, Riverpod) are explicitly deferred to after the core
API is stable, per AGENTS.md §49 Step 10 — not part of this MVP.

---

## Next step

Per AGENTS.md §52, this is the point to **stop and get approval** before writing any
implementation code. Please confirm:

1. The differentiator priorities in §1 (dependency-aware sync + temp IDs, then
   Sync Inspector, then state-mgmt neutrality, then human-readable explanations).
2. The MVP scope in §10 (push-sync only, no CRDT, no pull-sync yet, no
   state-management adapters yet).
3. Whether to start building in-place under `lib/src/` in this single-package repo,
   or set up a melos monorepo now (`packages/offline_sync_core`, etc.) before writing
   any code.

Once confirmed, implementation proceeds incrementally per §10 above, one gated step
at a time.
