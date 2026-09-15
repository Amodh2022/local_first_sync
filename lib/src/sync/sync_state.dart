import '../connectivity/connectivity_monitor.dart';
import '../core/sync_operation.dart';
import '../core/sync_status.dart';

/// A single, always-current summary of the sync engine — the one object a
/// status bar / badge / "Synced 2m ago" label needs.
///
/// Unlike [SyncInspectorSnapshot] (a diagnostic view of every operation),
/// this is a small value type built for rebuilding UI on every change, and
/// it includes runtime facts the queue alone can't tell you: whether a drain
/// is in flight, whether syncing is paused, and when the last drain
/// completed with nothing left to push.
class SyncState {
  const SyncState({
    required this.connectivity,
    required this.isSyncing,
    required this.isPaused,
    required this.pending,
    required this.syncing,
    required this.retrying,
    required this.failed,
    required this.blocked,
    required this.synced,
    required this.cancelled,
    this.lastSyncedAt,
    this.lastError,
  });

  const SyncState.initial()
      : connectivity = ConnectivityState.offline,
        isSyncing = false,
        isPaused = false,
        pending = 0,
        syncing = 0,
        retrying = 0,
        failed = 0,
        blocked = 0,
        synced = 0,
        cancelled = 0,
        lastSyncedAt = null,
        lastError = null;

  final ConnectivityState connectivity;

  /// A drain is currently in flight.
  final bool isSyncing;
  final bool isPaused;

  /// Queued and eligible to sync (or waiting for the next pass).
  final int pending;

  /// Currently in flight against the remote.
  final int syncing;

  /// Failed transiently and waiting for a backoff delay to elapse.
  final int retrying;

  /// Failed permanently. Needs `retryOperation` / `retryAllFailed`.
  final int failed;

  /// Waiting on a dependency.
  final int blocked;

  final int synced;
  final int cancelled;

  /// When the queue was last fully drained with no unsynced work left.
  /// `null` means it has never reached that state in this process.
  final DateTime? lastSyncedAt;

  /// The most recent operation failure message, for a status-bar hint.
  final String? lastError;

  bool get isOnline => connectivity == ConnectivityState.online;

  /// Unsynced local work of any kind — the number a "3 unsynced changes"
  /// badge should show.
  int get unsynced => pending + syncing + retrying + failed + blocked;

  bool get hasUnsyncedWork => unsynced > 0;

  /// True when everything local has reached the backend.
  bool get isUpToDate => unsynced == 0;

  SyncState copyWith({
    ConnectivityState? connectivity,
    bool? isSyncing,
    bool? isPaused,
    DateTime? lastSyncedAt,
    String? lastError,
  }) =>
      SyncState(
        connectivity: connectivity ?? this.connectivity,
        isSyncing: isSyncing ?? this.isSyncing,
        isPaused: isPaused ?? this.isPaused,
        pending: pending,
        syncing: syncing,
        retrying: retrying,
        failed: failed,
        blocked: blocked,
        synced: synced,
        cancelled: cancelled,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: lastError ?? this.lastError,
      );

  /// Builds the queue-derived counts from a queue snapshot; the runtime
  /// flags are supplied by the engine.
  factory SyncState.from({
    required Iterable<SyncOperation> operations,
    required ConnectivityState connectivity,
    required bool isSyncing,
    required bool isPaused,
    DateTime? lastSyncedAt,
    String? lastError,
  }) {
    var pending = 0,
        syncing = 0,
        retrying = 0,
        failed = 0,
        blocked = 0,
        synced = 0,
        cancelled = 0;
    for (final op in operations) {
      switch (op.status) {
        case SyncStatus.created:
        case SyncStatus.queued:
        case SyncStatus.ready:
        case SyncStatus.conflict:
          pending++;
        case SyncStatus.syncing:
          syncing++;
        case SyncStatus.retry:
          retrying++;
        case SyncStatus.failed:
          failed++;
        case SyncStatus.blocked:
          blocked++;
        case SyncStatus.synced:
          synced++;
        case SyncStatus.cancelled:
          cancelled++;
      }
    }
    return SyncState(
      connectivity: connectivity,
      isSyncing: isSyncing,
      isPaused: isPaused,
      pending: pending,
      syncing: syncing,
      retrying: retrying,
      failed: failed,
      blocked: blocked,
      synced: synced,
      cancelled: cancelled,
      lastSyncedAt: lastSyncedAt,
      lastError: lastError,
    );
  }

  @override
  String toString() => 'SyncState(${connectivity.name}, '
      'syncing: $isSyncing, paused: $isPaused, pending: $pending, '
      'inFlight: $syncing, retrying: $retrying, failed: $failed, '
      'blocked: $blocked, synced: $synced)';
}
