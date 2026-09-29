# local_first_sync_rest

A REST/HTTP `RemoteStore` for [`local_first_sync`](https://pub.dev/packages/local_first_sync),
built on `package:http`. It does three jobs that every hand-written adapter gets slightly
wrong:

- It **maps HTTP status codes to `SyncFailure`s**, so the sync engine retries a 503 and
  gives up on a 422 instead of guessing.
- It **sends an `Idempotency-Key`** that stays the same across retries and app restarts,
  so a write re-sent after a crash can't be applied twice.
- It **resolves headers on every request**, so a refreshed auth token is picked up on the
  next attempt.

It's pure Dart with no `dart:io` import, so it runs on every platform `package:http` does,
including web.

## Install

```yaml
dependencies:
  local_first_sync: ^0.2.0
  local_first_sync_rest: ^0.1.0
  http: ^1.2.0
```

## Setup

```dart
final sync = OfflineSync();

final todos = sync.registerCollection<Todo>(
  name: 'todos',
  localStore: myPersistentLocalStore, // e.g. DriftLocalStore from local_first_sync_drift
  remoteStore: RestRemoteStore<Todo>(
    client: http.Client(),
    collectionUri: Uri.parse('https://api.example.com/v1/todos'),
    serializer: const TodoSerializer(),
    headers: () async => {'Authorization': 'Bearer ${await auth.accessToken()}'},
  ),
  serializer: const TodoSerializer(),
);
```

| Operation | Request |
|---|---|
| create | `POST /v1/todos` — body is `serializer.encode(item)` |
| update | `PUT /v1/todos/{id}` (pass `updateMethod: 'PATCH'` for PATCH) |
| delete | `DELETE /v1/todos/{id}` — a 404 counts as success |

Create and update responses are decoded with your `Serializer`. When a create comes back
with a server-assigned id, `local_first_sync` moves the local row to that id and rewrites
queued dependents that referenced the temporary id. An empty 2xx body means the server
accepted the item exactly as sent.

## Error mapping

| Response | Thrown as | Engine behavior |
|---|---|---|
| 401, 403 | `AuthFailure` | goes to `SyncConfig.onAuthFailure` if set (see below), otherwise permanent |
| 409, 412 | `ConflictFailure` (`remoteValue` = decoded JSON body) | routed to your `ConflictResolver` |
| 400, 422 | `ValidationFailure` | permanent |
| 408, 429 | `NetworkFailure` | retried with backoff, waiting at least `Retry-After` |
| 5xx | `ServerFailure` | retried with backoff, waiting at least `Retry-After` |
| any other non-2xx | `ServerFailure` | permanent |
| `http.ClientException` | `NetworkFailure` | retried |
| `TimeoutException` | `TimeoutFailure` | retried |
| 2xx body that doesn't decode | `UnknownFailure` | permanent (a retry would get the same body back) |

`Retry-After` is read in both forms, seconds (`120`) and an HTTP date, and becomes the
failure's `retryAfter`. The engine never retries sooner than that, even when its own
backoff would. `RestRemoteStore.parseRetryAfter` is public if you need it in your own
`mapFailure`.

### Expired tokens

Refresh the token in `SyncConfig.onAuthFailure`, and have `headers` read the current one.
The engine then re-sends each rejected request once, and a whole batch of 401s triggers a
single refresh:

```dart
final sync = OfflineSync(
  config: SyncConfig(
    onAuthFailure: (_) async =>
        await auth.refresh() ? AuthRecovery.retry : AuthRecovery.pause,
  ),
);
final todos = sync.registerCollection<Todo>(
  name: 'todos',
  localStore: todoStore,
  remoteStore: RestRemoteStore<Todo>(
    client: http.Client(),
    collectionUri: Uri.parse('https://api.example.com/todos'),
    serializer: const TodoSerializer(),
    headers: () async => {'Authorization': 'Bearer ${await auth.token()}'},
  ),
  serializer: const TodoSerializer(),
);
```

`AuthRecovery.pause` stops syncing and keeps every write queued until you call
`sync.resume()`, for example after the user signs in again.

For conflict resolution, the 409/412 response body should be the server's current copy of
the record, in the shape your `Serializer` decodes.

If your backend uses its own conventions, override `mapFailure`:

```dart
class MyTodoStore extends RestRemoteStore<Todo> {
  MyTodoStore(http.Client client)
      : super(client: client, collectionUri: todosUri, serializer: const TodoSerializer());

  @override
  SyncFailure mapFailure(http.Response response) => response.statusCode == 423
      ? NetworkFailure('record locked, try later')
      : super.mapFailure(response);
}
```

## Idempotency

The engine sends every write through `createWithKey` / `updateWithKey` / `deleteWithKey`,
which add `Idempotency-Key: <operation's idempotencyKey>`. That key belongs to the queued
operation and never changes:

- It's the same on every retry.
- It's the same after a coalesced edit.
- It's the same after the app is killed mid-request and the request is re-sent on the next
  launch.

If your backend remembers keys it has seen and replays the first response for a repeat,
each write is applied exactly once. Use `idempotencyHeader:` to change the header name.

## Pull sync

`PullableRestRemoteStore<T>` also implements `PullableRemoteStore`, so `sync.pullNow()` or
`SyncConfig.pullInterval` fetches remote changes with `GET /v1/todos`, adding
`?since=<ISO-8601 UTC>` after the first successful pull:

```dart
PullableRestRemoteStore<Todo>(
  client: http.Client(),
  collectionUri: Uri.parse('https://api.example.com/v1/todos'),
  serializer: const TodoSerializer(),
  sinceParam: 'updated_after',                          // default: 'since'
  decodeList: (body) => (body! as Map)['data'] as List, // for {"data": [...]} envelopes
);
```

Pull is a separate class so it's opt-in: a plain `RestRemoteStore` never gets a GET from
the engine. A pull never overwrites a record that still has unsynced local changes queued.

## Testing your integration

Pass a `MockClient` from `package:http/testing.dart` as `client`. This package's own tests
do that to run a full `OfflineSync` against a fake backend.
