/// A `package:http` [RemoteStore] for `local_first_sync`.
///
/// [RestRemoteStore] pushes creates/updates/deletes to a JSON REST endpoint,
/// forwards each operation's idempotency key, and translates HTTP status
/// codes into the `SyncFailure` subtypes the sync engine uses to decide
/// whether to retry. [PullableRestRemoteStore] adds opt-in pull sync.
library;

export 'src/rest_remote_store.dart';
