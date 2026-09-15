import '../core/sync_operation.dart';

/// The type-erased surface [SyncEngine] talks to. [SyncOperation.payload] is
/// a plain `Map`, so the engine can process operations across many
/// collections/types without being generic over each one; [Collection]'s
/// registration wires a concrete [TypedCollectionBinding] in behind this.
abstract class CollectionBinding {
  String get name;

  /// Payload field names that may hold another entity's id (or a list of
  /// ids) and therefore need temporary-id rewriting before this operation is
  /// sent.
  List<String> get referenceFields;

  Future<Map<String, Object?>> remoteCreate(Map<String, Object?> payload);

  Future<Map<String, Object?>> remoteUpdate(
    String id,
    Map<String, Object?> payload,
  );

  Future<void> remoteDelete(String id);

  /// Applies a successful create's server response back to local storage,
  /// reassigning [tempId] if the server returned a different id. Returns the
  /// id the record now lives under.
  Future<String> applyCreateResult(
    String tempId,
    Map<String, Object?> serverPayload,
  );

  Future<void> applyUpdateResult(String id, Map<String, Object?> serverPayload);

  Future<void> applyDeleteResult(String id);

  /// Invoked when the remote adapter throws a `ConflictFailure`. Returns a
  /// payload to re-send (having already updated local storage with the
  /// resolution), or `null` if the remote value is authoritative and no
  /// further sync is needed for this operation.
  Future<Map<String, Object?>?> resolveConflict(
    SyncOperation operation,
    Object? remoteValue,
  );

  /// Whether this collection's remote store implements
  /// [PullableRemoteStore], i.e. whether [pull] does anything.
  bool get supportsPull;

  /// Fetches remote changes since [since] and writes them into local
  /// storage, skipping any entity id in [skipEntityIds] (those have unsynced
  /// local work queued and must not be overwritten). Returns how many
  /// records were applied and how many were skipped.
  Future<PullOutcome> pull({
    required DateTime? since,
    required Set<String> skipEntityIds,
  });

  /// Restores the entity's local state to [payload], or deletes it locally
  /// when [payload] is `null` (the entity did not exist before the failed
  /// operation). Used for optimistic-write rollback.
  Future<void> applyRollback(String entityId, Map<String, Object?>? payload);
}

/// The result of one [CollectionBinding.pull].
class PullOutcome {
  const PullOutcome({required this.applied, required this.skipped});

  final int applied;
  final int skipped;
}
