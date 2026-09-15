# AGENTS.md — offline_sync

## Mission

Build `offline_sync` as a production-quality, high-performance, state-management-agnostic offline-first synchronization framework for Flutter/Dart.

The package must make offline-first data synchronization easy without forcing developers to change their existing architecture.

It must work with:

- BLoC / Cubit
- Riverpod
- Provider
- GetX
- ChangeNotifier
- ValueNotifier
- `setState`
- `StreamBuilder`
- plain Dart
- custom state-management solutions

The core package must never depend on a UI state-management framework.

---

# 1. Non-Negotiable Principles

## 1.1 State-management agnostic

The core must never import:

```text
flutter_bloc
riverpod
provider
getx
```

State-management integrations belong in separate adapter packages.

Target package family:

```text
offline_sync_core
offline_sync_drift
offline_sync_rest

offline_sync_bloc
offline_sync_riverpod
offline_sync_provider
offline_sync_getx
```

The core should expose ordinary Dart APIs, Futures, Streams, interfaces, and typed models.

---

## 1.2 Local-first

Reads should normally come from local storage.

Writes should update local storage immediately whenever possible and enqueue synchronization independently.

Expected flow:

```text
Application
    |
    | save(entity)
    v
Local Store
    |
    +------> Reactive stream ------> UI
    |
    v
Persistent Sync Queue
    |
    v
Sync Engine
    |
    v
Remote Backend
```

The UI must not need to wait for a network request to observe a successful local mutation.

---

## 1.3 Correctness before performance

Performance is critical, but never sacrifice:

1. Data integrity
2. No lost writes
3. No unintended duplicate writes
4. Correct dependency ordering
5. Crash recovery
6. Conflict correctness
7. Transaction safety
8. Predictable eventual synchronization

Do not claim exactly-once delivery unless the backend guarantees it.

Prefer reliable at-least-once delivery combined with idempotency where appropriate.

---

## 1.4 No unnecessary complexity

Do not create abstractions merely because they sound architecturally sophisticated.

Every component must have:

- a clear responsibility
- a reason to exist
- tests
- measurable value

Avoid giant classes, hidden mutable global state, magic strings, and framework coupling.

---

# 2. Competitive Research Before Implementation

Before implementing substantial functionality, research the current pub.dev and GitHub ecosystem.

Investigate existing solutions for:

- offline sync
- local-first architecture
- persistent request queues
- Drift synchronization
- Isar synchronization
- CRDTs
- conflict resolution
- optimistic updates
- connectivity
- background synchronization
- state-management adapters

For each relevant package record:

- purpose
- strengths
- weaknesses
- maintenance status
- API quality
- popularity/downloads if available
- performance characteristics
- missing functionality
- whether we should integrate, differentiate, or avoid it

## Critical rule

Do not build a generic clone of an existing package.

The primary differentiators to investigate are:

1. Sync Inspector
2. Dependency-aware synchronization
3. Temporary IDs
4. Automatic reference replacement
5. Human-readable sync explanations
6. State-management independence
7. Field-level conflict resolution
8. Reactive local-first repositories
9. High-performance queue processing
10. Safe operation coalescing

If research reveals a better differentiation, explain it before changing the architecture.

---

# 3. High-Level Architecture

```text
                         Flutter Application
                                |
             +------------------+------------------+
             |                  |                  |
            BLoC             Riverpod           GetX
             |                  |                  |
             +------------------+------------------+
                                |
                         Repository / Collection
                                |
                     +----------v-----------+
                     |     offline_sync     |
                     |                      |
                     |  Collection<T>       |
                     |  Repository          |
                     |  Sync Engine         |
                     |  Sync Queue          |
                     |  Dependency Graph    |
                     |  Conflict Resolver   |
                     |  Retry Engine        |
                     |  Connectivity        |
                     |  Migration Manager   |
                     |  Event System        |
                     |  Inspector           |
                     +----------+-----------+
                                |
                 +--------------+--------------+
                 |                             |
          Local Storage                  Remote Adapter
                 |                             |
        Drift / future stores          REST / GraphQL / custom
```

---

# 4. Layered Architecture

```text
Presentation
    |
State Management
    |
Repository / Collection API
    |
Synchronization Domain
    |
+-------+-------+-------+-------+
|       |       |       |       |
Queue  Conflict Dependency Retry
|       |       |       |
+-------+-------+-------+-------+
    |
Persistence Abstraction
    |
Local Database
```

Responsibilities must remain separated.

---

# 5. Core Components

The architecture should contain concepts similar to:

```text
OfflineSync
SyncManager
Collection<T>
Repository<T>

LocalStore<T>
RemoteStore<T>
Serializer<T>

SyncOperation
SyncQueue
SyncEngine

SyncStatus
SyncEvent

ConflictResolver
DependencyGraph
RetryPolicy

ConnectivityMonitor
MigrationManager

SyncInspector
```

Names may be improved during implementation.

---

# 6. LocalStore

The core needs a database-independent storage interface.

Conceptual starting point:

```dart
abstract interface class LocalStore<T> {
  Future<T?> getById(String id);

  Future<List<T>> getAll();

  Future<void> insert(T item);

  Future<void> update(T item);

  Future<void> delete(String id);

  Stream<List<T>> watch();

  Stream<T?> watchById(String id);
}
```

Do not copy this API blindly.

Evaluate the need for:

- transactions
- bulk operations
- queries
- pagination
- cursors
- metadata
- change streams
- batch writes
- atomic mutations

The core must remain database-independent.

---

# 7. RemoteStore

The core must not assume REST.

Conceptual API:

```dart
abstract interface class RemoteStore<T> {
  Future<List<T>> fetch();

  Future<T> create(T item);

  Future<T> update(T item);

  Future<void> delete(String id);
}
```

Eventually support adapters for:

- REST
- GraphQL
- custom backends

REST-specific dependencies belong in `offline_sync_rest`.

The core must not require Dio or another HTTP client.

---

# 8. Serialization

Use explicit typed serialization.

Conceptual API:

```dart
abstract interface class Serializer<T> {
  Map<String, dynamic> encode(T value);

  T decode(Map<String, dynamic> data);
}
```

Prefer generated serialization for performance-sensitive applications.

Avoid reflection-heavy serialization on critical paths when generated serialization is practical.

---

# 9. Collection / Repository API

Target a simple developer experience:

```dart
final users = sync.collection<User>('users');

await users.save(user);

final user = await users.get('123');

final allUsers = await users.getAll();

await users.delete('123');

users.watch();

users.watchById('123');
```

The final API must prioritize:

- type safety
- readability
- minimal boilerplate
- testability
- predictable semantics

---

# 10. Sync Queue

Remote mutations that cannot immediately synchronize must become persistent operations.

Operations:

```text
create
update
delete
```

An operation should contain appropriate metadata:

```text
operationId
collection
entityId
operationType
payload
createdAt
updatedAt
retryCount
status
dependencyIds
lastError
nextRetryAt
idempotencyKey
```

The exact schema should be designed carefully.

## Persistent queue requirement

The queue must survive:

- app restart
- process death
- network failure
- server failure
- crashes during synchronization

An in-memory queue is not sufficient.

---

# 11. Sync Operation Lifecycle

A typical lifecycle:

```text
CREATED
   |
   v
QUEUED
   |
   v
READY
   |
   v
SYNCING
   |
 +-----+
 |     |
 v     v
SYNCED FAILED
         |
         v
       RETRY
         |
         v
       READY
```

Other states may include:

```text
BLOCKED
CONFLICT
CANCELLED
```

State transitions must be explicit, deterministic, and persisted safely.

---

# 12. Retry Engine

Use configurable exponential backoff.

Example:

```text
1 sec
2 sec
4 sec
8 sec
16 sec
...
```

with a configurable maximum delay.

Distinguish:

### Retryable

- network unavailable
- timeout
- temporary server failures
- 5xx responses

### Usually non-retryable

- validation errors
- malformed requests
- authorization failures
- forbidden operations

### Special handling

- conflicts
- expired authentication
- dependency failures

Never retry permanent errors forever.

---

# 13. Connectivity

Do not equate Wi-Fi/network connectivity with server reachability.

Represent meaningful states such as:

```text
OFFLINE
NETWORK_AVAILABLE
SERVER_REACHABLE
SYNCING
SYNCED
FAILED
```

Connectivity must be replaceable and testable.

Prefer event-driven sync triggers:

```text
mutation
connectivity restored
app resumed
manual sync
server push event
scheduled sync
```

Avoid unnecessary polling.

---

# 14. Dependency-Aware Synchronization

Operations may depend on other operations.

Example:

```text
CREATE Order
      |
      v
CREATE OrderItem
      |
      v
CREATE Payment
```

If the parent fails:

```text
Order        FAILED
OrderItem    BLOCKED
Payment      BLOCKED
```

After recovery:

```text
Order        SYNCED
OrderItem    READY
Payment      BLOCKED
```

Independent operations should synchronize concurrently when safe.

The dependency system must:

- detect circular dependencies
- prevent invalid ordering
- expose blocking reasons
- recover automatically when dependencies succeed
- work with temporary IDs

---

# 15. Temporary IDs

Offline-created entities need temporary identifiers.

Example:

```text
local ID:
temp_order_123
```

Server returns:

```text
server ID:
98231
```

Maintain:

```text
temp_order_123 -> 98231
```

Update structured references safely.

Example:

```text
Order.id = temp_order_123

OrderItem.orderId = temp_order_123
Payment.orderId = temp_order_123
```

After synchronization:

```text
Order.id = 98231

OrderItem.orderId = 98231
Payment.orderId = 98231
```

Never implement this as naive string replacement.

---

# 16. Conflict Resolution

At minimum investigate:

```text
serverWins
clientWins
lastWriteWins
custom
```

Design the resolver as an extensible abstraction.

Do not claim that every conflict can be automatically resolved.

Conflicts must remain observable.

---

# 17. Field-Level Conflicts

Where practical, support field-level resolution.

Local:

```json
{
  "name": "Amodh",
  "phone": "9999999999"
}
```

Remote:

```json
{
  "name": "Amodh Nadiger",
  "phone": "8888888888"
}
```

Potential resolution:

```text
name  -> server
phone -> client
```

Support custom field-level resolvers where safe.

---

# 18. Optimistic Updates

Local mutations should normally be visible immediately.

If remote synchronization fails, support configurable behavior:

```text
rollback
keepLocal
markConflict
```

Optimistic update logic belongs in the data/synchronization layer, not in a state-management adapter.

---

# 19. Incremental Synchronization

Never synchronize the entire database unnecessarily.

Prefer:

- changed records
- changed fields where supported
- cursors
- timestamps
- version numbers
- server revisions
- change tokens
- delta synchronization

Support backend-specific mechanisms through adapters.

---

# 20. Pull Synchronization

Eventually support changes originating from the server.

Generic flow:

```text
Server
  |
  | changes since cursor X
  v
Sync Engine
  |
  v
Conflict Resolver
  |
  v
Local Store
  |
  v
Reactive UI
```

Persist synchronization cursors safely.

Do not repeatedly download unchanged data.

---

# 21. Reactive Data

Provide APIs such as:

```dart
watchAll()
watchById(id)
watchQuery(...)
watchChanges()
```

Avoid emitting huge collections when only one entity changes.

Bad:

```text
1 entity changed
    |
    v
emit 100,000 entities
```

Prefer:

```text
1 entity changed
    |
    v
emit only relevant change
```

or update the query result efficiently.

---

# 22. State Management Adapters

Adapters should translate core streams/repositories into framework-specific primitives.

Example:

```text
offline_sync_core
        |
        +---- offline_sync_bloc
        +---- offline_sync_riverpod
        +---- offline_sync_provider
        +---- offline_sync_getx
```

The adapters must remain thin.

They must not duplicate synchronization logic.

The same core repository must behave identically regardless of the state-management framework.

---

# 23. Sync Events

Provide framework-independent events such as:

```text
SyncStarted
SyncCompleted
OperationQueued
OperationStarted
OperationSucceeded
OperationFailed
OperationBlocked
ConflictDetected
RollbackPerformed
```

Events should be observable through a lightweight API such as Streams.

---

# 24. Sync Status

Support strongly typed statuses:

```text
idle
offline
queued
syncing
synced
failed
blocked
conflict
```

Where useful expose:

- global status
- collection status
- entity status
- operation status

---

# 25. "Why Isn't This Synced?"

Every failed/blocked operation should provide an actionable explanation.

Example:

```text
Status: BLOCKED

Operation:
UPDATE OrderItem/123

Reason:
Waiting for Order/456 to synchronize.

Dependency:
Order/456

Dependency status:
FAILED

Last error:
HTTP 409 Conflict

Retry count:
4

Next retry:
15:42
```

Expose both:

- machine-readable error data
- human-readable explanation

Never reduce all failures to:

```text
Sync failed.
```

---

# 26. Sync Inspector

The Sync Inspector is a primary product differentiator.

It should expose:

- online/offline state
- queue size
- pending operations
- syncing operations
- failed operations
- blocked operations
- conflicts
- successful operations
- retry counts
- request duration
- errors
- dependencies
- timestamps

Example:

```text
SYNC INSPECTOR

🟢 Online

Pending: 3
Syncing: 1
Failed: 1
Synced: 128

--------------------------------

✓ UPDATE users/123       182ms
✓ CREATE orders/temp_92  421ms
⏳ UPDATE cart/12         waiting
❌ DELETE item/43         401
```

Selecting an operation should reveal diagnostic information.

Sensitive data must be redacted.

Inspector history must be bounded.

Developer diagnostics should be disabled or minimized in production where practical.

---

# 27. Operation Coalescing

Support safe optional optimization.

Example:

```text
UPDATE user 123
UPDATE user 123
UPDATE user 123
UPDATE user 123
```

may become:

```text
UPDATE user 123
```

if semantically safe.

Potential transformation:

```text
CREATE A
UPDATE A
UPDATE A
DELETE A
```

may collapse into a no-op/final delete depending on whether the entity ever reached the server and the configured semantics.

Never coalesce operations when it can change observable backend behavior.

---

# 28. Batching

Where the backend supports it, batch independent operations.

Example:

```text
100 UPDATE operations
        |
        v
1 batched request
```

Batching must be configurable.

Do not batch operations that require strict ordering or dependency sequencing.

---

# 29. Concurrency

Do not maximize HTTP concurrency blindly.

Provide configurable concurrency:

```dart
SyncConfig(
  maxConcurrentOperations: 4,
);
```

Select defaults using benchmarks.

Independent operations may synchronize concurrently.

Dependent operations must preserve ordering.

Avoid multiple workers processing the same queue simultaneously unless explicitly designed and tested.

---

# 30. Crash Recovery

The application can be killed at any moment.

The system must safely recover from:

```text
local write
queue insertion
sync start
remote request
remote success
local acknowledgment
queue deletion
```

Design transaction boundaries carefully.

Use idempotency keys where supported.

Never assume a remote request timed out means the server did not process it.

---

# 31. Database Efficiency

Index frequently queried fields:

```text
entity ID
collection
operation status
retry timestamp
dependency ID
created timestamp
updated timestamp
```

Avoid repeatedly scanning large queues.

Use transactions for related mutations.

Use batch operations where supported.

---

# 32. Memory Efficiency

Do not load large datasets into memory unnecessarily.

Avoid:

```dart
final allUsers = await database.getAll();
```

when only a subset is required.

Support:

- pagination
- cursors
- streaming
- batches
- lazy processing

---

# 33. Backpressure

Consider workloads such as:

```text
100 updates/sec
1,000 updates/sec
```

Prevent unbounded:

- event queues
- stream emissions
- synchronization workers
- memory usage

Consider:

- batching
- safe coalescing
- bounded concurrency
- backpressure

Do not debounce by default if it can alter correctness.

---

# 34. Network Efficiency

Minimize unnecessary network traffic.

Investigate:

- batching
- request deduplication
- operation coalescing
- compression
- incremental sync
- ETags
- conditional requests
- `If-Modified-Since`
- delta synchronization

Backend-specific optimizations belong in adapters.

---

# 35. Serialization Performance

Serialization can become a bottleneck.

Use explicit serializers.

Prefer generated serialization for large/performance-sensitive applications.

Avoid:

- reflection-heavy serialization
- duplicate encoding/decoding
- repeated JSON conversions

Evaluate isolates only for genuinely expensive CPU workloads.

---

# 36. Isolates / Background Work

Do not introduce isolates just because they sound faster.

Isolate communication has overhead.

Consider isolates for:

- very large serialization/deserialization
- expensive migrations
- large conflict calculations
- large payload transformations

Keep small operations on the normal path.

---

# 37. App Startup

Do not make application startup wait unnecessarily for synchronization.

Avoid:

```text
App starts
  |
load entire database
  |
deserialize everything
  |
initialize sync
  |
render UI
```

Prefer:

```text
App starts
  |
render UI
  |
load required local data
  |
initialize synchronization asynchronously
```

Preserve correctness while minimizing startup latency.

---

# 38. Migrations

Offline data must survive application upgrades.

Support schema/data versions.

Example:

Version 1:

```text
User:
  id
  name
```

Version 2:

```text
User:
  id
  name
  phone
```

Provide safe migration hooks and test migrations on realistic datasets.

---

# 39. Security

Never log sensitive values such as:

- authorization headers
- tokens
- passwords
- payment data
- private user data

The inspector must support redaction.

Allow configurable redaction policies.

---

# 40. Performance Is a First-Class Requirement

The package must target:

- large local datasets
- large sync queues
- frequent mutations
- frequent connectivity changes
- large payloads
- high synchronization volume

Do not claim performance without measurements.

The guiding principle is:

```text
Do less work.
Do it incrementally.
Avoid unnecessary allocations.
Use indexed queries.
Batch where safe.
Bound concurrency.
Keep UI work small.
Measure everything.
```

---

# 41. Performance Benchmarking

Create benchmarks for:

### Local operations

```text
1,000 inserts
10,000 inserts
100,000 inserts
```

### Updates

```text
1,000 updates
10,000 updates
```

### Queue

```text
1,000 pending operations
10,000 pending operations
100,000 pending operations
```

### Synchronization

```text
sequential sync
concurrent sync
dependency-aware sync
retry-heavy sync
```

### Serialization

```text
small payload
medium payload
large payload
```

### Reactive updates

```text
1 entity changed
10 entities changed
1,000 entities changed
```

### Startup

Measure:

```text
cold startup
local database initialization
sync initialization
first local data availability
```

---

# 42. Performance Targets

Do not invent benchmark numbers before testing.

Process:

1. Establish a baseline.
2. Benchmark.
3. Identify bottlenecks.
4. Optimize.
5. Benchmark again.
6. Document actual results.

Prefer measurable claims:

```text
42ms -> 17ms
```

over:

```text
extremely fast
```

Every optimization should be justified by measurements.

---

# 43. Test Strategy

Test:

- queue insertion
- queue persistence
- retries
- exponential backoff
- dependency ordering
- dependency failures
- circular dependencies
- temporary IDs
- reference replacement
- conflicts
- field-level conflicts
- rollback
- duplicate operations
- operation coalescing
- app restart recovery
- connectivity transitions
- migrations
- concurrent sync calls
- race conditions
- transaction failures
- large datasets
- large queues

Critical integration scenario:

```text
offline
  |
mutation
  |
app restart
  |
still offline
  |
network returns
  |
sync
  |
verify remote state
  |
verify local state
```

---

# 44. Stress Testing

Test at least:

```text
10,000 entities
100,000 entities
10,000 pending operations
rapid offline/online transitions
repeated app restarts
rapid mutations
large payloads
dependency chains
large conflict sets
```

Do not rely only on small unit-test datasets.

---

# 45. Project Structure

A starting structure:

```text
offline_sync/
│
├── lib/
│   ├── offline_sync.dart
│   │
│   └── src/
│       ├── core/
│       ├── models/
│       ├── repository/
│       ├── collection/
│       ├── storage/
│       ├── remote/
│       ├── sync/
│       ├── queue/
│       ├── conflict/
│       ├── dependency/
│       ├── connectivity/
│       ├── migration/
│       ├── inspector/
│       └── serialization/
│
├── test/
│   ├── core/
│   ├── repository/
│   ├── queue/
│   ├── sync/
│   ├── conflict/
│   ├── dependency/
│   ├── migration/
│   └── integration/
│
├── benchmark/
│   ├── local_store_benchmark.dart
│   ├── queue_benchmark.dart
│   ├── serialization_benchmark.dart
│   ├── sync_benchmark.dart
│   ├── dependency_benchmark.dart
│   ├── conflict_benchmark.dart
│   └── startup_benchmark.dart
│
├── example/
│
├── README.md
├── CHANGELOG.md
├── LICENSE
└── pubspec.yaml
```

Adjust the structure when there is a strong architectural reason.

---

# 46. Dependency Rules

Keep the dependency graph minimal.

Core should ideally depend only on lightweight, necessary Dart packages.

Database implementations belong in adapters.

Network implementations belong in adapters.

State-management integrations belong in adapters.

Do not add a dependency simply to avoid writing a small amount of stable code.

Every dependency must be justified.

---

# 47. API Stability

Once a public API is released:

- avoid unnecessary breaking changes
- use semantic versioning
- deprecate before removing when practical
- document migration paths
- maintain backward compatibility where reasonable

Keep internal implementation details private.

---

# 48. Documentation

Documentation must explain:

1. What the package solves
2. What it does not solve
3. Architecture
4. Installation
5. Basic usage
6. Local-first behavior
7. Sync lifecycle
8. Retry behavior
9. Conflict resolution
10. Dependencies
11. Temporary IDs
12. State-management integrations
13. Performance
14. Security
15. Limitations
16. Troubleshooting
17. Testing
18. Migration/versioning

Provide complete examples.

---

# 49. Development Workflow

Do not generate the entire system in one step.

Use incremental implementation.

## Step 1 — Research

Research the ecosystem and establish the product gap.

Do not write implementation code yet.

## Step 2 — Architecture

Design:

- domain model
- storage abstraction
- remote abstraction
- queue model
- synchronization state machine
- dependency model
- conflict model
- event model

Review the architecture for correctness before coding.

## Step 3 — Core Interfaces

Implement only foundational abstractions.

## Step 4 — Queue

Implement persistent queue semantics.

## Step 5 — Sync Engine

Implement lifecycle, retries, crash recovery, and concurrency control.

## Step 6 — Local Store

Implement the first concrete database adapter.

## Step 7 — Remote Adapter

Implement REST support.

## Step 8 — Advanced Sync

Add:

- temporary IDs
- reference replacement
- dependencies
- conflict resolution
- optimistic updates
- coalescing
- batching

## Step 9 — Inspector

Build the developer debugging experience.

## Step 10 — State-management adapters

Only after the core API is stable.

Start with:

1. BLoC
2. Riverpod

Then evaluate Provider/GetX based on actual demand.

## Step 11 — Benchmarks and optimization

Measure, optimize, measure again.

## Step 12 — Release readiness

Validate:

- tests
- benchmarks
- documentation
- examples
- API stability
- pub.dev quality
- licensing
- changelog

---

# 50. Agent Operating Rules

When working on this repository:

### Always

- understand the existing architecture before modifying it
- inspect relevant files before making assumptions
- preserve public API compatibility where possible
- write tests for behavior changes
- consider performance implications
- consider crash recovery
- consider concurrency
- consider offline/online transitions
- explain important architectural decisions
- keep implementations small and composable

### Never

- blindly copy another package's architecture
- add state-management dependencies to core
- add database/network dependencies unnecessarily
- introduce global mutable state without strong justification
- silently swallow synchronization errors
- retry permanent failures forever
- perform unsafe operation coalescing
- load huge datasets into memory unnecessarily
- claim performance without benchmarks
- sacrifice correctness for speed
- generate huge amounts of code without validating the architecture

---

# 51. Definition of Done

A feature is not complete merely because the code compiles.

A feature is complete when:

- architecture is clear
- API is typed and documented
- edge cases are handled
- failure behavior is defined
- tests exist
- concurrency behavior is considered
- persistence/crash recovery is considered
- performance impact is measured where relevant
- public API is stable
- documentation/examples are updated

---

# 52. First Task for the Coding Agent

Do NOT start implementing the package immediately.

First perform:

## Competitive Research + Architecture Proposal

Research the current ecosystem and produce:

1. Existing package comparison
2. What we should not build
3. Remaining gaps
4. Recommended differentiators
5. Proposed architecture
6. Proposed package boundaries
7. Core domain model
8. Sync state machine
9. Queue model
10. Dependency model
11. Conflict model
12. Performance strategy
13. Testing strategy
14. Proposed MVP scope

Then stop and wait for approval before implementing.

The objective is to build a package that is:

> **Correct, fast, maintainable, framework-independent, developer-friendly, and genuinely differentiated from existing Flutter offline-sync solutions.**
