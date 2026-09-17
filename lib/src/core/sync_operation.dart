import 'sync_status.dart';

enum SyncOperationType { create, update, delete }

const Object _unset = Object();

/// A single queued mutation awaiting synchronization. Immutable — every
/// state transition produces a new instance via [copyWith], which the
/// [SyncQueue] persists in place of the old one.
class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.idempotencyKey,
    required this.collection,
    required this.entityId,
    required this.type,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.retryCount = 0,
    this.status = SyncStatus.ready,
    this.dependencyIds = const [],
    this.lastError,
    this.nextRetryAt,
    this.blockedReason,
    this.priority = 0,
    this.rollbackPayload,
  });

  /// Stable identity of this operation, independent of the entity it acts on
  /// (an entity may have several operations queued over its lifetime).
  final String operationId;

  /// Sent to the backend so at-least-once delivery can be de-duplicated.
  final String idempotencyKey;

  final String collection;

  /// The entity's id at enqueue time — may be a temporary id for a `create`
  /// that hasn't synced yet (see [TempIdRegistry]).
  final String entityId;

  final SyncOperationType type;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int retryCount;
  final SyncStatus status;

  /// Other operations' ids that must reach [SyncStatus.synced]
  /// before this one is eligible to sync.
  final List<String> dependencyIds;

  final String? lastError;
  final DateTime? nextRetryAt;

  /// Human-readable reason this operation is [SyncStatus.blocked], set by the
  /// engine.
  final String? blockedReason;

  /// Higher values drain first. Operations of equal priority stay strictly
  /// FIFO by [createdAt], so a queue with all-default priorities behaves
  /// exactly like a plain outbox.
  final int priority;

  /// The entity's encoded state *before* this operation's local mutation, or
  /// `null` if the entity did not exist (i.e. this is a `create`). Captured
  /// by [Collection] so the engine can undo an optimistic local write whose
  /// operation later fails permanently — see
  /// [SyncConfig.rollbackOnPermanentFailure].
  final Map<String, Object?>? rollbackPayload;

  /// Whether this operation will never be attempted again without explicit
  /// intervention (`SyncEngine.retryOperation`).
  bool get isTerminal =>
      status == SyncStatus.synced ||
      status == SyncStatus.failed ||
      status == SyncStatus.cancelled;

  /// Whether this operation still represents unsynced local work.
  bool get isPending => !isTerminal;

  SyncOperation copyWith({
    Map<String, Object?>? payload,
    DateTime? updatedAt,
    int? retryCount,
    SyncStatus? status,
    int? priority,
    Object? lastError = _unset,
    Object? nextRetryAt = _unset,
    Object? blockedReason = _unset,
    Object? rollbackPayload = _unset,
  }) {
    return SyncOperation(
      operationId: operationId,
      idempotencyKey: idempotencyKey,
      collection: collection,
      entityId: entityId,
      type: type,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      dependencyIds: dependencyIds,
      priority: priority ?? this.priority,
      lastError:
          identical(lastError, _unset) ? this.lastError : lastError as String?,
      nextRetryAt: identical(nextRetryAt, _unset)
          ? this.nextRetryAt
          : nextRetryAt as DateTime?,
      blockedReason: identical(blockedReason, _unset)
          ? this.blockedReason
          : blockedReason as String?,
      rollbackPayload: identical(rollbackPayload, _unset)
          ? this.rollbackPayload
          : rollbackPayload as Map<String, Object?>?,
    );
  }

  /// A JSON-compatible representation, so a [SyncQueue] adapter can persist
  /// the queue across process restarts without knowing this class's shape.
  /// Payloads must themselves be JSON-encodable — the same
  /// constraint [Serializer.encode] already implies.
  Map<String, Object?> toJson() => {
        'operationId': operationId,
        'idempotencyKey': idempotencyKey,
        'collection': collection,
        'entityId': entityId,
        'type': type.name,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'retryCount': retryCount,
        'status': status.name,
        'dependencyIds': dependencyIds,
        'lastError': lastError,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
        'blockedReason': blockedReason,
        'priority': priority,
        'rollbackPayload': rollbackPayload,
      };

  /// Inverse of [toJson].
  ///
  /// An operation that was [SyncStatus.syncing] when the process died is
  /// restored as [SyncStatus.ready]: the request may or may not have reached
  /// the backend, so it is re-sent under its original [idempotencyKey],
  /// which is exactly what that key is for.
  factory SyncOperation.fromJson(Map<String, Object?> json) {
    final status = SyncStatus.values.byName(json['status']! as String);
    return SyncOperation(
      operationId: json['operationId']! as String,
      idempotencyKey: json['idempotencyKey']! as String,
      collection: json['collection']! as String,
      entityId: json['entityId']! as String,
      type: SyncOperationType.values.byName(json['type']! as String),
      payload: Map<String, Object?>.from(json['payload']! as Map),
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      retryCount: (json['retryCount'] as int?) ?? 0,
      status: status == SyncStatus.syncing ? SyncStatus.ready : status,
      dependencyIds:
          (json['dependencyIds'] as List?)?.cast<String>().toList() ?? const [],
      lastError: json['lastError'] as String?,
      nextRetryAt: json['nextRetryAt'] != null
          ? DateTime.parse(json['nextRetryAt']! as String)
          : null,
      blockedReason: json['blockedReason'] as String?,
      priority: (json['priority'] as int?) ?? 0,
      rollbackPayload: json['rollbackPayload'] != null
          ? Map<String, Object?>.from(json['rollbackPayload']! as Map)
          : null,
    );
  }

  /// Drain order: highest [priority] first, then strict FIFO by [createdAt],
  /// then by [SyncOperation.operationId] so the order is total and stable across restarts
  /// (two operations can share a timestamp).
  static int compare(SyncOperation a, SyncOperation b) {
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    final byAge = a.createdAt.compareTo(b.createdAt);
    if (byAge != 0) return byAge;
    return a.operationId.compareTo(b.operationId);
  }

  @override
  String toString() =>
      'SyncOperation($operationId, $collection/$entityId, $type, $status)';
}
