import 'dart:async';

import '../connectivity/connectivity_monitor.dart';
import '../core/sync_errors.dart';
import '../core/sync_events.dart';
import '../core/sync_operation.dart';
import '../core/sync_status.dart';
import '../dependency/dependency_graph.dart';
import '../dependency/temp_id_registry.dart';
import '../queue/sync_queue.dart';
import 'collection_binding.dart';
import 'sync_config.dart';
import 'sync_state.dart';

/// Drives [SyncOperation]s from [SyncStatus.ready]/[SyncStatus.retry] through
/// to [SyncStatus.synced], handling retries, dependency blocking, temporary
/// id reassignment, and conflict resolution. See DESIGN.md §4/§8/§9.
///
/// The engine never talks to a database or a network directly — it only
/// knows about [SyncQueue] and the [CollectionBinding]s registered for each
/// collection, so it works identically regardless of which storage/remote
/// adapters those bindings wrap.
class SyncEngine {
  SyncEngine({
    required SyncQueue queue,
    required ConnectivityMonitor connectivity,
    SyncConfig config = const SyncConfig(),
  })  : _queue = queue,
        _connectivity = connectivity,
        _config = config;

  final SyncQueue _queue;
  final ConnectivityMonitor _connectivity;
  final SyncConfig _config;
  final _bindings = <String, CollectionBinding>{};
  final _eventsController = StreamController<SyncEvent>.broadcast();
  final _runtimeChanges = StreamController<void>.broadcast();
  final TempIdRegistry tempIds = TempIdRegistry();

  StreamSubscription<ConnectivityState>? _connectivitySub;
  StreamSubscription<List<SyncOperation>>? _queueSub;
  Timer? _syncTimer;
  Timer? _pullTimer;
  Timer? _retryTimer;
  Future<void>? _inFlight;
  bool _syncRequestedAgain = false;
  bool _paused = false;
  DateTime? _lastSyncedAt;
  String? _lastError;
  final _lastPulledAt = <String, DateTime>{};

  Stream<SyncEvent> get events => _eventsController.stream;

  SyncConfig get config => _config;

  /// Whether syncing is currently suspended. See [pause].
  bool get isPaused => _paused;

  /// Whether a drain is in flight right now.
  bool get isSyncing => _inFlight != null;

  void registerCollection(CollectionBinding binding) {
    _bindings[binding.name] = binding;
  }

  /// Starts reacting to connectivity changes *and* queue changes, and runs
  /// an initial sync pass. Call [dispose] to stop.
  ///
  /// Without this, `Collection.save`/`delete` only enqueue an operation —
  /// they never call back into the engine — so a write made while already
  /// online would just sit `ready` until something called [syncNow]. After
  /// [start], reacting to `_queue.watchAll()` is what makes that automatic:
  /// every queue change (a fresh enqueue, a status transition, ...) is
  /// offered a drain, which [syncNow] safely coalesces with any drain
  /// already in flight — including the ones the drain's own writes trigger.
  ///
  /// [SyncConfig.syncInterval] and [SyncConfig.pullInterval], if set, add
  /// periodic passes on top of that event-driven behavior.
  void start() {
    _connectivitySub = _connectivity.onStateChanged.listen((state) {
      _notifyRuntimeChange();
      if (state == ConnectivityState.online) {
        unawaited(syncNow());
      }
    });
    _queueSub = _queue.watchAll().listen((_) {
      if (_connectivity.current == ConnectivityState.online) {
        unawaited(syncNow());
      }
    });
    final interval = _config.syncInterval;
    if (interval != null) {
      _syncTimer = Timer.periodic(interval, (_) => unawaited(syncNow()));
    }
    final pullInterval = _config.pullInterval;
    if (pullInterval != null) {
      _pullTimer = Timer.periodic(pullInterval, (_) => unawaited(pullNow()));
    }
    unawaited(syncNow());
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    _pullTimer?.cancel();
    _retryTimer?.cancel();
    await _connectivitySub?.cancel();
    await _queueSub?.cancel();
    await _runtimeChanges.close();
    await _eventsController.close();
  }

  // ---------------------------------------------------------------------
  // Live state
  // ---------------------------------------------------------------------

  /// A point-in-time [SyncState]: queue counts plus runtime facts (in
  /// flight, paused, last fully-synced time).
  Future<SyncState> currentState() async => SyncState.from(
        operations: await _queue.all(),
        connectivity: _connectivity.current,
        isSyncing: isSyncing,
        isPaused: _paused,
        lastSyncedAt: _lastSyncedAt,
        lastError: _lastError,
      );

  /// [currentState] as a stream: emits immediately on listen, then on every
  /// queue change, connectivity change, and pause/resume or drain
  /// transition. This is what a status bar binds to.
  Stream<SyncState> watchState() => Stream.multi((controller) {
        var cancelled = false;
        var pushing = Future<void>.value();

        void push() {
          pushing = pushing.then((_) async {
            if (cancelled) return;
            final state = await currentState();
            if (!cancelled) controller.add(state);
          }).catchError((Object e, StackTrace s) {
            if (!cancelled) controller.addError(e, s);
          });
        }

        final subs = <StreamSubscription<Object?>>[
          _queue.watchAll().listen((_) => push()),
          _runtimeChanges.stream.listen((_) => push()),
          _connectivity.onStateChanged.listen((_) => push()),
        ];
        push();
        controller.onCancel = () async {
          cancelled = true;
          for (final sub in subs) {
            await sub.cancel();
          }
        };
      });

  void _notifyRuntimeChange() {
    if (!_runtimeChanges.isClosed) _runtimeChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // Queue control
  // ---------------------------------------------------------------------

  /// Suspends syncing without touching the queue. Writes keep landing
  /// locally and keep queuing up; nothing is sent until [resume].
  ///
  /// The canonical use is an auth failure: pause, refresh the token, resume —
  /// instead of letting every queued operation burn its retry budget against
  /// a 401.
  void pause() {
    if (_paused) return;
    _paused = true;
    _retryTimer?.cancel();
    _eventsController.add(SyncPaused());
    _notifyRuntimeChange();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _eventsController.add(SyncResumed());
    _notifyRuntimeChange();
    unawaited(syncNow());
  }

  /// Puts a [SyncStatus.failed] (or cancelled, or retry-waiting) operation
  /// back in line immediately, clearing its error and backoff.
  ///
  /// This is the "Retry" button in a sync-status UI. Its retry count is
  /// reset, so the configured [RetryPolicy.maxAttempts] budget starts fresh.
  Future<void> retryOperation(String operationId) async {
    final op = await _queue.getOperation(operationId);
    if (op == null || op.status == SyncStatus.synced) return;
    await _queue.updateOperation(op.copyWith(
      status: SyncStatus.ready,
      retryCount: 0,
      lastError: null,
      nextRetryAt: null,
      blockedReason: null,
      updatedAt: DateTime.now(),
    ));
    await syncNow();
  }

  /// [retryOperation] for every permanently failed operation. Returns how
  /// many were requeued.
  Future<int> retryAllFailed() async {
    final failed = (await _queue.all())
        .where((op) => op.status == SyncStatus.failed)
        .toList();
    for (final op in failed) {
      await _queue.updateOperation(op.copyWith(
        status: SyncStatus.ready,
        retryCount: 0,
        lastError: null,
        nextRetryAt: null,
        updatedAt: DateTime.now(),
      ));
    }
    if (failed.isNotEmpty) await syncNow();
    return failed.length;
  }

  /// Abandons an operation: it will never be sent. Dependents are blocked
  /// with an explicit reason rather than silently dropped, exactly as for a
  /// permanent failure.
  ///
  /// Note this does not undo the local write — call it together with your
  /// own local correction, or enable
  /// [SyncConfig.rollbackOnPermanentFailure] and let a real failure run.
  Future<void> cancelOperation(String operationId) async {
    final op = await _queue.getOperation(operationId);
    if (op == null || op.status == SyncStatus.synced) return;
    final cancelled = op.copyWith(
      status: SyncStatus.cancelled,
      lastError: null,
      nextRetryAt: null,
      updatedAt: DateTime.now(),
    );
    await _queue.updateOperation(cancelled);
    _eventsController.add(OperationCancelled(cancelled));
    await _blockDependents(
      operationId,
      'Dependency ${op.collection}/${op.entityId} was cancelled, so this '
      'operation can never be sent.',
    );
  }

  /// Removes completed operations from the queue. Without this the queue is
  /// an append-only log that grows for the life of the install.
  ///
  /// Called automatically after each drain using
  /// [SyncConfig.retainSyncedOperations]; call it directly to purge sooner.
  /// Only [SyncStatus.synced] and [SyncStatus.cancelled] operations are ever
  /// removed — failed ones stay so they remain visible and retryable.
  Future<int> purgeCompleted({Duration? olderThan}) async {
    final cutoff =
        olderThan == null ? null : DateTime.now().subtract(olderThan);
    final all = await _queue.all();
    final dependedOn = <String>{for (final op in all) ...op.dependencyIds};
    var removed = 0;
    for (final op in all) {
      final completed =
          op.status == SyncStatus.synced || op.status == SyncStatus.cancelled;
      if (!completed) continue;
      if (cutoff != null && op.updatedAt.isAfter(cutoff)) continue;
      // Keep anything still referenced, so `explain` can still name the
      // dependency a blocked operation is waiting on.
      if (dependedOn.contains(op.operationId) &&
          op.status == SyncStatus.cancelled) {
        continue;
      }
      await _queue.removeOperation(op.operationId);
      removed++;
    }
    return removed;
  }

  // ---------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------

  /// Drains the queue once. Safe to call concurrently — a call that arrives
  /// while a drain is already running just requests one more pass after the
  /// current one finishes, rather than running two drains in parallel
  /// (AGENTS.md §29: avoid multiple workers processing the same queue
  /// simultaneously).
  Future<void> syncNow() {
    if (_inFlight != null) {
      _syncRequestedAgain = true;
      return _inFlight!;
    }
    final future = _runUntilQuiescent();
    _inFlight = future;
    _notifyRuntimeChange();
    future.whenComplete(() {
      _inFlight = null;
      _notifyRuntimeChange();
    });
    return future;
  }

  Future<void> _runUntilQuiescent() async {
    do {
      _syncRequestedAgain = false;
      await _drainOnce();
    } while (_syncRequestedAgain);
  }

  Future<void> _drainOnce() async {
    if (_paused) return;
    if (_connectivity.current != ConnectivityState.online) return;

    await _refreshBlockedStatuses();

    var succeeded = 0;
    var failed = 0;
    _eventsController.add(SyncStarted());

    while (!_paused) {
      final batch = _selectBatch(await _queue.all());
      if (batch.isEmpty) break;

      final results = await Future.wait(batch.map(_processOperation));
      for (final ok in results) {
        ok ? succeeded++ : failed++;
      }
      await _refreshBlockedStatuses();
    }

    final remaining = await _queue.all();
    if (!remaining.any((op) => op.isPending)) {
      _lastSyncedAt = DateTime.now();
    }
    _scheduleRetryWakeup(remaining);

    final retention = _config.retainSyncedOperations;
    if (retention != null) await purgeCompleted(olderThan: retention);

    _eventsController.add(SyncCompleted(succeeded: succeeded, failed: failed));
  }

  /// Wakes the engine up when the earliest backoff delay elapses.
  ///
  /// Without this, an operation in [SyncStatus.retry] just sits there with a
  /// `nextRetryAt` in the past until something *else* — a new save, a
  /// connectivity flip, an explicit [syncNow] — happens to trigger a drain.
  /// That turns "retry in 4 seconds" into "retry whenever the app next does
  /// something", which is not a backoff policy at all.
  void _scheduleRetryWakeup(List<SyncOperation> operations) {
    _retryTimer?.cancel();
    if (_paused) return;

    DateTime? earliest;
    for (final op in operations) {
      if (op.status != SyncStatus.retry) continue;
      final at = op.nextRetryAt;
      if (at == null) continue;
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    if (earliest == null) return;

    final delay = earliest.difference(DateTime.now());
    _retryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(syncNow()),
    );
  }

  /// Picks the next operations to run, in drain order.
  ///
  /// Two rules beyond "whatever is ready":
  /// - **Order**: highest [SyncOperation.priority] first, then strict FIFO.
  ///   Without this the queue would drain in whatever order the underlying
  ///   store happened to iterate, and a create could be sent after the
  ///   update that follows it.
  /// - **One operation per entity per batch**: concurrent writes to the same
  ///   record would otherwise race, and the loser would overwrite the
  ///   winner. The runner-up simply waits for the next pass.
  List<SyncOperation> _selectBatch(List<SyncOperation> all) {
    final now = DateTime.now();
    final eligible = all
        .where((op) =>
            op.status == SyncStatus.ready ||
            (op.status == SyncStatus.retry &&
                (op.nextRetryAt == null || !op.nextRetryAt!.isAfter(now))))
        .toList()
      ..sort(SyncOperation.compare);

    final batch = <SyncOperation>[];
    final claimedEntities = <String>{};
    for (final op in eligible) {
      if (batch.length >= _config.maxConcurrentOperations) break;
      if (!claimedEntities.add('${op.collection}/${op.entityId}')) continue;
      batch.add(op);
    }
    return batch;
  }

  Future<T> _withTimeout<T>(Future<T> Function() action) {
    final timeout = _config.operationTimeout;
    if (timeout == null) return action();
    return action().timeout(
      timeout,
      onTimeout: () => throw TimeoutFailure(
        'Remote call exceeded ${_describe(timeout)} and was abandoned; '
        'it will be retried.',
      ),
    );
  }

  /// Sub-second timeouts are common in tests and in latency-sensitive
  /// configs; [Duration.inSeconds] would render them all as `0s`.
  static String _describe(Duration d) =>
      d.inSeconds > 0 ? '${d.inSeconds}s' : '${d.inMilliseconds}ms';

  Future<bool> _processOperation(SyncOperation op) async {
    final binding = _bindings[op.collection];
    if (binding == null) {
      // No adapter registered for this collection — nothing we can do with
      // it yet; leave it as-is rather than guessing.
      return false;
    }

    final syncingOp =
        op.copyWith(status: SyncStatus.syncing, updatedAt: DateTime.now());
    await _queue.updateOperation(syncingOp);
    _eventsController.add(OperationStarted(syncingOp));

    try {
      final payload =
          tempIds.rewritePayload(op.payload, binding.referenceFields);

      switch (op.type) {
        case SyncOperationType.create:
          final result =
              await _withTimeout(() => binding.remoteCreate(payload));
          final finalId = await binding.applyCreateResult(op.entityId, result);
          if (finalId != op.entityId) {
            tempIds.register(op.entityId, finalId);
            await _rewriteDependentPayloads(op.operationId);
          }
        case SyncOperationType.update:
          final result = await _withTimeout(
              () => binding.remoteUpdate(op.entityId, payload));
          await binding.applyUpdateResult(op.entityId, result);
        case SyncOperationType.delete:
          await _withTimeout(() => binding.remoteDelete(op.entityId));
          await binding.applyDeleteResult(op.entityId);
      }

      final synced = syncingOp.copyWith(
          status: SyncStatus.synced, updatedAt: DateTime.now());
      await _queue.updateOperation(synced);
      _eventsController.add(OperationSucceeded(synced));
      return true;
    } on ConflictFailure catch (e) {
      return _handleConflict(syncingOp, e);
    } on SyncFailure catch (e) {
      return _handleFailure(syncingOp, e);
    } catch (e) {
      return _handleFailure(syncingOp, UnknownFailure(e.toString()));
    }
  }

  Future<bool> _handleConflict(SyncOperation op, ConflictFailure error) async {
    _eventsController.add(ConflictDetected(op, error.remoteValue));
    final binding = _bindings[op.collection]!;
    final resolvedPayload =
        await binding.resolveConflict(op, error.remoteValue);

    if (resolvedPayload == null) {
      // Remote value is authoritative and local storage was already updated
      // to match it — this operation's job is done.
      final synced =
          op.copyWith(status: SyncStatus.synced, updatedAt: DateTime.now());
      await _queue.updateOperation(synced);
      return true;
    }

    final retryOp = op.copyWith(
      status: SyncStatus.ready,
      payload: resolvedPayload,
      retryCount: op.retryCount + 1,
      updatedAt: DateTime.now(),
    );
    await _queue.updateOperation(retryOp);
    return false;
  }

  Future<bool> _handleFailure(SyncOperation op, SyncFailure error) async {
    final retryCount = op.retryCount + 1;
    final shouldRetry = _config.retryPolicy.shouldRetry(error, op.retryCount);
    final updated = op.copyWith(
      status: shouldRetry ? SyncStatus.retry : SyncStatus.failed,
      retryCount: retryCount,
      lastError: error.message,
      nextRetryAt: shouldRetry
          ? DateTime.now().add(_config.retryPolicy.delayForAttempt(retryCount))
          : null,
      updatedAt: DateTime.now(),
    );
    await _queue.updateOperation(updated);
    _lastError = error.message;
    _eventsController.add(OperationFailed(updated, error));

    if (!shouldRetry) {
      if (_config.rollbackOnPermanentFailure) {
        await _rollback(updated);
      }
      await _blockDependents(
        op.operationId,
        'Dependency ${op.collection}/${op.entityId} failed permanently: '
        '${error.message}',
      );
    }
    return false;
  }

  /// Undoes the optimistic local write behind a permanently failed
  /// operation, so the UI stops showing data the backend rejected.
  Future<void> _rollback(SyncOperation op) async {
    final binding = _bindings[op.collection];
    if (binding == null) return;
    try {
      await binding.applyRollback(op.entityId, op.rollbackPayload);
      _eventsController.add(RollbackPerformed(op));
    } catch (_) {
      // A failed rollback must not mask the original failure, which is
      // already recorded on the operation.
    }
  }

  Future<void> _rewriteDependentPayloads(String operationId) async {
    for (final dep in await _queue.dependentsOf(operationId)) {
      final binding = _bindings[dep.collection];
      if (binding == null) continue;
      final rewritten =
          tempIds.rewritePayload(dep.payload, binding.referenceFields);
      if (!identical(rewritten, dep.payload)) {
        await _queue.updateOperation(
            dep.copyWith(payload: rewritten, updatedAt: DateTime.now()));
      }
    }
  }

  Future<void> _blockDependents(String operationId, String reason) async {
    for (final dep in await _queue.dependentsOf(operationId)) {
      if (dep.status == SyncStatus.blocked && dep.blockedReason == reason) {
        continue;
      }
      final blocked = dep.copyWith(
        status: SyncStatus.blocked,
        blockedReason: reason,
        updatedAt: DateTime.now(),
      );
      await _queue.updateOperation(blocked);
      _eventsController.add(OperationBlocked(blocked, reason));
    }
  }

  /// Reconciles every operation's [SyncStatus.blocked] state against the
  /// current dependency graph: newly-satisfied dependents become
  /// [SyncStatus.ready] again, newly-unsatisfied ones become
  /// [SyncStatus.blocked] (AGENTS.md §14's recovery example).
  Future<void> _refreshBlockedStatuses() async {
    final all = await _queue.all();
    final reasons = DependencyGraph.blockedReasons(all);
    for (final op in all) {
      final shouldBeBlocked = reasons.containsKey(op.operationId);
      if (shouldBeBlocked &&
          op.status != SyncStatus.blocked &&
          op.status != SyncStatus.syncing &&
          op.status != SyncStatus.synced &&
          op.status != SyncStatus.cancelled) {
        await _queue.updateOperation(op.copyWith(
          status: SyncStatus.blocked,
          blockedReason: reasons[op.operationId],
          updatedAt: DateTime.now(),
        ));
      } else if (!shouldBeBlocked && op.status == SyncStatus.blocked) {
        await _queue.updateOperation(op.copyWith(
          status: SyncStatus.ready,
          blockedReason: null,
          updatedAt: DateTime.now(),
        ));
      }
    }
  }

  // ---------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------

  /// Fetches remote changes into local storage for every registered
  /// collection whose remote store implements [PullableRemoteStore]
  /// (optionally just [collection]).
  ///
  /// Entities with unsynced queued work are skipped, never overwritten — a
  /// pull must not destroy a local write that hasn't reached the backend.
  /// Returns the number of records applied across all collections.
  Future<int> pullNow({String? collection}) async {
    if (_paused) return 0;
    if (_connectivity.current != ConnectivityState.online) return 0;

    final queued = await _queue.all();
    final targets = collection != null
        ? [if (_bindings[collection] != null) _bindings[collection]!]
        : _bindings.values.toList();

    var applied = 0;
    for (final binding in targets) {
      if (!binding.supportsPull) continue;
      final protectedIds = queued
          .where((op) => op.collection == binding.name && op.isPending)
          .map((op) => op.entityId)
          .toSet();
      final since = _lastPulledAt[binding.name];
      final startedAt = DateTime.now();
      try {
        final outcome = await _withTimeout(
          () => binding.pull(since: since, skipEntityIds: protectedIds),
        );
        _lastPulledAt[binding.name] = startedAt;
        applied += outcome.applied;
        _eventsController.add(PullCompleted(
          collection: binding.name,
          applied: outcome.applied,
          skipped: outcome.skipped,
        ));
      } on SyncFailure catch (e) {
        _lastError = e.message;
        _eventsController.add(PullFailed(binding.name, e));
      } catch (e) {
        _lastError = e.toString();
        _eventsController
            .add(PullFailed(binding.name, UnknownFailure(e.toString())));
      }
    }
    _notifyRuntimeChange();
    return applied;
  }

  /// When [pullNow] last succeeded for [collection], or `null` if never.
  DateTime? lastPulledAt(String collection) => _lastPulledAt[collection];
}
