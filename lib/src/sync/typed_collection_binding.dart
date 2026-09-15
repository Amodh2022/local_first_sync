import '../conflict/conflict_resolver.dart';
import '../core/identifiable.dart';
import '../core/sync_operation.dart';
import '../remote/remote_store.dart';
import '../serialization/serializer.dart';
import '../storage/local_store.dart';
import 'collection_binding.dart';

/// The concrete [CollectionBinding] for a single `Collection<T>`, wiring its
/// [LocalStore], [RemoteStore] and [Serializer] together.
class TypedCollectionBinding<T extends Identifiable>
    implements CollectionBinding {
  TypedCollectionBinding({
    required this.name,
    required this.localStore,
    required this.remoteStore,
    required this.serializer,
    this.referenceFields = const [],
    this.conflictResolver,
  });

  @override
  final String name;

  final LocalStore<T> localStore;
  final RemoteStore<T> remoteStore;
  final Serializer<T> serializer;

  @override
  final List<String> referenceFields;

  final ConflictResolver<T>? conflictResolver;

  @override
  Future<Map<String, Object?>> remoteCreate(
      Map<String, Object?> payload) async {
    final result = await remoteStore.create(serializer.decode(payload));
    return serializer.encode(result);
  }

  @override
  Future<Map<String, Object?>> remoteUpdate(
    String id,
    Map<String, Object?> payload,
  ) async {
    final result = await remoteStore.update(serializer.decode(payload));
    return serializer.encode(result);
  }

  @override
  Future<void> remoteDelete(String id) => remoteStore.delete(id);

  @override
  Future<String> applyCreateResult(
    String tempId,
    Map<String, Object?> serverPayload,
  ) async {
    final serverItem = serializer.decode(serverPayload);
    if (serverItem.id != tempId) {
      await localStore.reassignId(tempId, serverItem);
    } else {
      await localStore.update(serverItem);
    }
    return serverItem.id;
  }

  @override
  Future<void> applyUpdateResult(
    String id,
    Map<String, Object?> serverPayload,
  ) async {
    await localStore.update(serializer.decode(serverPayload));
  }

  @override
  Future<void> applyDeleteResult(String id) => localStore.delete(id);

  @override
  bool get supportsPull => remoteStore is PullableRemoteStore<T>;

  @override
  Future<PullOutcome> pull({
    required DateTime? since,
    required Set<String> skipEntityIds,
  }) async {
    final pullable = remoteStore;
    if (pullable is! PullableRemoteStore<T>) {
      return const PullOutcome(applied: 0, skipped: 0);
    }
    final remoteItems = await pullable.fetchChanges(since: since);
    var applied = 0;
    var skipped = 0;
    for (final item in remoteItems) {
      // Never let a pull clobber a local write that hasn't reached the
      // backend yet — that write is the user's, and it is still queued.
      if (skipEntityIds.contains(item.id)) {
        skipped++;
        continue;
      }
      final existing = await localStore.getById(item.id);
      if (existing == null) {
        await localStore.insert(item);
      } else {
        await localStore.update(item);
      }
      applied++;
    }
    return PullOutcome(applied: applied, skipped: skipped);
  }

  @override
  Future<void> applyRollback(
    String entityId,
    Map<String, Object?>? payload,
  ) async {
    if (payload == null) {
      await localStore.delete(entityId);
      return;
    }
    final restored = serializer.decode(payload);
    final existing = await localStore.getById(restored.id);
    if (existing == null) {
      await localStore.insert(restored);
    } else {
      await localStore.update(restored);
    }
  }

  @override
  Future<Map<String, Object?>?> resolveConflict(
    SyncOperation operation,
    Object? remoteValue,
  ) async {
    final resolver = conflictResolver;
    if (resolver == null || remoteValue is! Map) return null;
    final local = await localStore.getById(operation.entityId);
    if (local == null) return null;

    final remote = serializer.decode(Map<String, Object?>.from(remoteValue));
    final resolution = resolver.resolve(
      local,
      remote,
      ConflictContext(
        collection: name,
        entityId: operation.entityId,
        operation: operation,
      ),
    );

    switch (resolution.origin) {
      case ConflictOrigin.remote:
        await localStore.update(remote);
        return null;
      case ConflictOrigin.local:
      case ConflictOrigin.merged:
        await localStore.update(resolution.value);
        return serializer.encode(resolution.value);
    }
  }
}
