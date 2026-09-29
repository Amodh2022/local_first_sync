import '../core/identifiable.dart';

/// Database-independent remote access for entities of type [T]. The core
/// makes no assumption about REST/GraphQL/etc; a
/// concrete adapter (`local_first_sync_rest`, ...) implements this.
///
/// Implementations should throw a [SyncFailure] subtype (from
/// `core/sync_errors.dart`) rather than a raw exception, so the [SyncEngine]
/// can make a correct retry decision.
abstract interface class RemoteStore<T extends Identifiable> {
  Future<T> create(T item);

  Future<T> update(T item);

  Future<void> delete(String id);
}

/// An optional capability a [RemoteStore] can add: fetching records the
/// backend has that this device doesn't (or has stale copies of).
///
/// The core is push-only by default — local mutation → queue → remote. Every
/// competing package that offers "bidirectional sync" either owns your
/// backend schema (PowerSync) or generates the fetch for you (Brick,
/// Synquill). Here it stays an explicit, opt-in method on your own adapter,
/// so you keep control of paging, auth, and what "changed since" means for
/// your API.
///
/// The engine calls [fetchChanges] on `pullNow()` / [SyncConfig.pullInterval]
/// and writes the results into the [LocalStore] — except for entities that
/// still have unsynced local operations queued, which it skips rather than
/// overwrite. Pulled records are never re-enqueued for pushing.
abstract interface class PullableRemoteStore<T extends Identifiable>
    implements RemoteStore<T> {
  /// Records created or modified since [since] (the previous successful
  /// pull's timestamp, or `null` on the first pull — return everything).
  ///
  /// Throw a `SyncFailure` subtype on failure, as with the write methods.
  Future<List<T>> fetchChanges({DateTime? since});
}

/// An optional capability a [RemoteStore] can add: receiving each
/// operation's stable [SyncOperation.idempotencyKey] alongside the write.
///
/// The key never changes for the life of an operation — across retries,
/// coalescing, and an app restart that re-sends an operation which was
/// in flight when the process died. Forward it to your backend (typically
/// as an `Idempotency-Key` header) and a re-send can't create a duplicate.
///
/// When a [RemoteStore] implements this, the engine calls the `*WithKey`
/// methods instead of [create]/[update]/[delete].
abstract interface class IdempotentRemoteStore<T extends Identifiable>
    implements RemoteStore<T> {
  Future<T> createWithKey(T item, {required String idempotencyKey});

  Future<T> updateWithKey(T item, {required String idempotencyKey});

  Future<void> deleteWithKey(String id, {required String idempotencyKey});
}
