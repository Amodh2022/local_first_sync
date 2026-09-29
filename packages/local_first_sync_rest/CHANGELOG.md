## 0.1.0

First release.

- `RestRemoteStore<T>`: a `RemoteStore` for a JSON REST collection endpoint on
  `package:http` (`POST /things`, `PUT` or `PATCH /things/{id}`,
  `DELETE /things/{id}`).
- Maps HTTP status codes and transport errors to `local_first_sync`'s
  `SyncFailure` types, so the engine retries what's transient and stops on
  what's permanent. A 409 or 412 carries the server copy for conflict
  resolution. Override `mapFailure` to change the mapping.
- Implements `IdempotentRemoteStore`: each operation's idempotency key goes out
  as an `Idempotency-Key` header and stays the same across retries and
  restarts.
- Honors `Retry-After` (seconds or HTTP date) on 408, 429 and 5xx responses.
  The engine never retries sooner than the server asked.
- Per-request `headers` callback for auth tokens that refresh. Pair it with
  core's `SyncConfig.onAuthFailure` to refresh a token and retry automatically.
- `PullableRestRemoteStore<T>`: opt-in pull sync via `GET /things?since=…`,
  with a configurable parameter name and envelope decoding.
