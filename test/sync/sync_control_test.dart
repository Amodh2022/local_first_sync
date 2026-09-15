import 'dart:async';

import 'package:test/test.dart';
import 'package:local_first_sync/local_first_sync.dart';

import '../support/test_models.dart';

void main() {
  late InMemoryLocalStore<TestUser> localStore;
  late ManualConnectivityMonitor connectivity;

  setUp(() {
    localStore = InMemoryLocalStore<TestUser>();
    connectivity = ManualConnectivityMonitor(initial: ConnectivityState.online);
  });

  OfflineSync build({
    SyncConfig config = const SyncConfig(),
    RemoteStore<TestUser>? remoteStore,
  }) {
    final sync = OfflineSync(connectivity: connectivity, config: config);
    sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localStore,
      remoteStore: remoteStore ?? InMemoryRemoteStore<TestUser>(),
      serializer: const TestUserSerializer(),
    );
    addTearDown(sync.dispose);
    return sync;
  }

  group('pause / resume', () {
    test('a paused engine queues writes but sends nothing', () async {
      final remote = InMemoryRemoteStore<TestUser>();
      final sync = build(remoteStore: remote);
      final users = sync.collection<TestUser>('users');

      sync.pause();
      await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();

      expect(remote.peek('1'), isNull);
      expect(await users.get('1'), isNotNull,
          reason: 'pausing sync must never affect local reads');
      expect((await sync.state()).isPaused, isTrue);

      sync.resume();
      await sync.syncNow();
      expect(remote.peek('1')?.name, 'Amodh');
    });

    test('pause and resume emit events', () async {
      final sync = build();
      final events = <SyncEvent>[];
      final sub = sync.events.listen(events.add);
      addTearDown(sub.cancel);

      sync.pause();
      sync.resume();
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<SyncPaused>(), hasLength(1));
      expect(events.whereType<SyncResumed>(), hasLength(1));
    });
  });

  group('manual queue control', () {
    test('retryOperation requeues a permanently failed operation', () async {
      var shouldFail = true;
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (_, item) =>
            shouldFail ? const ValidationFailure('rejected') : null,
      );
      final sync = build(remoteStore: remote);
      final users = sync.collection<TestUser>('users');

      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();
      expect((await sync.queue.getOperation(opId))!.status, SyncStatus.failed);

      shouldFail = false;
      await sync.retryOperation(opId);

      expect(remote.peek('1')?.name, 'Amodh');
    });

    test('retryAllFailed requeues every failure and reports the count',
        () async {
      var shouldFail = true;
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (_, item) =>
            shouldFail ? const ValidationFailure('rejected') : null,
      );
      final sync = build(remoteStore: remote);
      final users = sync.collection<TestUser>('users');

      await users.save(TestUser(id: '1', name: 'A'));
      await users.save(TestUser(id: '2', name: 'B'));
      await sync.syncNow();
      expect((await sync.state()).failed, 2);

      shouldFail = false;
      expect(await sync.retryAllFailed(), 2);
      expect((await sync.state()).failed, 0);
      expect(remote.peek('1'), isNotNull);
      expect(remote.peek('2'), isNotNull);
    });

    test('cancelOperation stops the send and blocks dependents with a reason',
        () async {
      final remote = InMemoryRemoteStore<TestUser>();
      final sync = build(remoteStore: remote);
      final users = sync.collection<TestUser>('users');

      sync.pause();
      final parentId = await users.save(TestUser(id: '1', name: 'Parent'));
      final childId = await users
          .save(TestUser(id: '2', name: 'Child'), dependsOn: [parentId]);

      await sync.cancelOperation(parentId);
      sync.resume();
      await sync.syncNow();

      expect(remote.peek('1'), isNull);
      final child = await sync.queue.getOperation(childId);
      expect(child!.status, SyncStatus.blocked);
      expect(sync.inspector().explain(child), contains('cancelled'));
    });

    test('purgeCompleted removes synced operations but keeps failures',
        () async {
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (_, item) =>
            item?.id == '2' ? const ValidationFailure('rejected') : null,
      );
      final sync = build(
        remoteStore: remote,
        config: const SyncConfig(retainSyncedOperations: null),
      );
      final users = sync.collection<TestUser>('users');

      await users.save(TestUser(id: '1', name: 'Fine'));
      await users.save(TestUser(id: '2', name: 'Doomed'));
      await sync.syncNow();
      expect(await sync.queue.all(), hasLength(2));

      expect(await sync.purgeCompleted(), 1);
      final remaining = await sync.queue.all();
      expect(remaining.single.entityId, '2');
      expect(remaining.single.status, SyncStatus.failed,
          reason: 'a failure must stay visible and retryable');
    });

    test('retention purges synced operations automatically after a drain',
        () async {
      final sync = build(
        config: const SyncConfig(retainSyncedOperations: Duration.zero),
      );
      await sync
          .collection<TestUser>('users')
          .save(TestUser(id: '1', name: 'A'));
      await sync.syncNow();

      expect(await sync.queue.all(), isEmpty,
          reason: 'without retention the queue grows forever');
    });
  });

  group('ordering', () {
    test('higher priority drains first', () async {
      final order = <String>[];
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (op, item) {
          if (item != null) order.add(item.id);
          return null;
        },
      );
      final sync = build(
        remoteStore: remote,
        config: const SyncConfig(maxConcurrentOperations: 1),
      );
      final users = sync.collection<TestUser>('users');

      sync.pause();
      await users.save(TestUser(id: 'low', name: 'Low'));
      await users.save(TestUser(id: 'urgent', name: 'Urgent'), priority: 10);
      await users.save(TestUser(id: 'normal', name: 'Normal'));
      sync.resume();
      await sync.syncNow();

      expect(order.first, 'urgent');
      expect(order.sublist(1), ['low', 'normal'],
          reason: 'equal priorities stay strictly FIFO');
    });

    test('two operations on the same entity never run in one batch', () async {
      final remote = _TrackingRemoteStore<TestUser>(
        latency: const Duration(milliseconds: 20),
      );
      final sync = build(remoteStore: remote);

      // Coalescing is off here so both writes really do reach the queue.
      final raw = Collection<TestUser>(
        name: 'users',
        localStore: localStore,
        queue: sync.queue,
        serializer: const TestUserSerializer(),
        coalesceOperations: false,
      );
      sync.pause();
      await raw.save(TestUser(id: '1', name: 'First'));
      await raw.save(TestUser(id: '1', name: 'Second'));
      sync.resume();
      await sync.syncNow();

      expect(remote.calls, 2);
      expect(remote.maxConcurrentPerEntity, 1,
          reason: 'concurrent writes to one record would race, and the '
              'loser would overwrite the winner');
    });
  });

  group('failure handling', () {
    test('a hung remote call times out and is retried, not wedged', () async {
      final remote = _HangingRemoteStore<TestUser>();
      final sync = build(
        remoteStore: remote,
        config: const SyncConfig(
          operationTimeout: Duration(milliseconds: 50),
          retryPolicy: RetryPolicy(jitter: 0),
        ),
      );
      final opId = await sync
          .collection<TestUser>('users')
          .save(TestUser(id: '1', name: 'A'));
      await sync.syncNow();

      final op = await sync.queue.getOperation(opId);
      expect(op!.status, SyncStatus.retry);
      expect(op.lastError, contains('abandoned'));
    });

    test('a backed-off retry fires on its own when the delay elapses',
        () async {
      var failures = 0;
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (op, item) {
          if (failures >= 1) return null;
          failures++;
          return const NetworkFailure('connection reset');
        },
      );
      final sync = build(
        remoteStore: remote,
        config: const SyncConfig(
          retryPolicy: RetryPolicy(
            initialDelay: Duration(milliseconds: 100),
            jitter: 0,
          ),
        ),
      );
      final opId = await sync
          .collection<TestUser>('users')
          .save(TestUser(id: '1', name: 'Amodh'));

      await sync.syncNow();
      expect((await sync.queue.getOperation(opId))!.status, SyncStatus.retry);

      // Nothing else touches the engine — no save, no connectivity change,
      // no syncNow. The backoff deadline itself has to wake it up. Polled
      // rather than slept on a fixed margin, so a loaded machine makes this
      // slower, never flaky.
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (remote.peek('1') == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(remote.peek('1')?.name, 'Amodh',
          reason: 'otherwise "retry in 200ms" really means "retry whenever '
              'the app next happens to do something"');
    });

    test('rollback restores the previous local value on permanent failure',
        () async {
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (op, item) =>
            op == 'update' ? const ValidationFailure('name too long') : null,
      );
      final sync = build(
        remoteStore: remote,
        config: const SyncConfig(rollbackOnPermanentFailure: true),
      );
      final users = sync.collection<TestUser>('users');

      await users.save(TestUser(id: '1', name: 'Good'));
      await sync.syncNow();
      await users.save(TestUser(id: '1', name: 'Rejected'));

      final events = <SyncEvent>[];
      final sub = sync.events.listen(events.add);
      addTearDown(sub.cancel);
      await sync.syncNow();

      expect((await users.get('1'))!.name, 'Good',
          reason: 'the UI must stop showing data the backend rejected');
      expect(events.whereType<RollbackPerformed>(), hasLength(1));
    });

    test('a create rejected permanently rolls back to not existing', () async {
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (_, item) => const ValidationFailure('rejected'),
      );
      final sync = build(
        remoteStore: remote,
        config: const SyncConfig(rollbackOnPermanentFailure: true),
      );
      final users = sync.collection<TestUser>('users');

      await users.save(TestUser(id: '1', name: 'Never valid'));
      await sync.syncNow();

      expect(await users.get('1'), isNull);
    });
  });

  group('SyncState', () {
    test('tracks the local-then-synced lifecycle', () async {
      connectivity.setOffline();
      final remote = InMemoryRemoteStore<TestUser>();
      final sync = build(remoteStore: remote);
      final users = sync.collection<TestUser>('users');

      expect((await sync.state()).isUpToDate, isTrue);

      await users.save(TestUser(id: '1', name: 'Amodh'));
      final offlineState = await sync.state();
      expect(offlineState.pending, 1);
      expect(offlineState.unsynced, 1);
      expect(offlineState.isUpToDate, isFalse);
      expect(offlineState.lastSyncedAt, isNull);

      connectivity.setOnline();
      await sync.syncNow();

      final syncedState = await sync.state();
      expect(syncedState.unsynced, 0);
      expect(syncedState.isUpToDate, isTrue);
      expect(syncedState.lastSyncedAt, isNotNull);
    });

    test('watchState emits immediately and on every change', () async {
      connectivity.setOffline();
      final sync = build();
      final states = <SyncState>[];
      final sub = sync.watchState().listen(states.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      expect(states, isNotEmpty);
      expect(states.last.unsynced, 0);

      await sync
          .collection<TestUser>('users')
          .save(TestUser(id: '1', name: 'A'));
      await Future<void>.delayed(Duration.zero);

      expect(states.last.unsynced, 1,
          reason: 'a badge bound to this stream updates without polling');
    });
  });

  group('RetryPolicy', () {
    test('jitter keeps delays within the configured spread', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 10),
        multiplier: 1,
        jitter: 0.2,
      );
      for (var i = 0; i < 50; i++) {
        final delay = policy.delayForAttempt(1).inMilliseconds;
        expect(delay, inInclusiveRange(8000, 12000));
      }
    });

    test('jitter: 0 is fully deterministic', () {
      const policy = RetryPolicy(initialDelay: Duration(seconds: 1), jitter: 0);
      expect(policy.delayForAttempt(3), const Duration(seconds: 8));
    });
  });
}

/// Records how many calls for the same entity id overlap in time.
class _TrackingRemoteStore<T extends Identifiable> implements RemoteStore<T> {
  _TrackingRemoteStore({this.latency = Duration.zero});

  final Duration latency;
  final _inFlight = <String, int>{};
  var maxConcurrentPerEntity = 0;
  var calls = 0;

  Future<T> _run(T item) async {
    calls++;
    final live = (_inFlight[item.id] ?? 0) + 1;
    _inFlight[item.id] = live;
    if (live > maxConcurrentPerEntity) maxConcurrentPerEntity = live;
    try {
      await Future<void>.delayed(latency);
      return item;
    } finally {
      _inFlight[item.id] = _inFlight[item.id]! - 1;
    }
  }

  @override
  Future<T> create(T item) => _run(item);

  @override
  Future<T> update(T item) => _run(item);

  @override
  Future<void> delete(String id) async {}
}

/// A remote store whose calls never complete — the failure mode a per-call
/// timeout exists for.
class _HangingRemoteStore<T extends Identifiable> implements RemoteStore<T> {
  @override
  Future<T> create(T item) => Completer<T>().future;

  @override
  Future<T> update(T item) => Completer<T>().future;

  @override
  Future<void> delete(String id) => Completer<void>().future;
}
