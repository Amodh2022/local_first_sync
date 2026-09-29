import 'package:test/test.dart';
import 'package:local_first_sync/local_first_sync.dart';

import '../support/test_models.dart';

Future<SyncOperation> _findOp(OfflineSync sync, String operationId) async {
  final snapshot = await sync.inspector().snapshot();
  return snapshot.operations.firstWhere((o) => o.operationId == operationId);
}

const _fastRetries = RetryPolicy(
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 5),
  jitter: 0,
);

OfflineSync _online({SyncConfig config = const SyncConfig()}) => OfflineSync(
      config: config,
      connectivity:
          ManualConnectivityMonitor(initial: ConnectivityState.online),
    );

void main() {
  group('Retry-After', () {
    test('a longer server-requested delay overrides the backoff', () async {
      final sync = _online(config: const SyncConfig(retryPolicy: _fastRetries));
      addTearDown(sync.dispose);
      var calls = 0;
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) => calls++ == 0
              ? const NetworkFailure('HTTP 429', retryAfter: Duration(hours: 1))
              : null,
        ),
        serializer: const TestUserSerializer(),
      );

      final before = DateTime.now();
      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();

      final op = await _findOp(sync, opId);
      expect(op.status, SyncStatus.retry);
      expect(
        op.nextRetryAt!.difference(before),
        greaterThanOrEqualTo(const Duration(minutes: 59)),
      );
    });

    test('a shorter server-requested delay does not shorten the backoff',
        () async {
      final sync = _online(
        config: const SyncConfig(
          retryPolicy: RetryPolicy(
            initialDelay: Duration(hours: 1),
            maxDelay: Duration(hours: 2),
            jitter: 0,
          ),
        ),
      );
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) => ServerFailure(503, 'HTTP 503',
              retryAfter: const Duration(seconds: 1)),
        ),
        serializer: const TestUserSerializer(),
      );

      final before = DateTime.now();
      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();

      final op = await _findOp(sync, opId);
      expect(op.nextRetryAt!.difference(before),
          greaterThanOrEqualTo(const Duration(minutes: 59)));
    });
  });

  group('onAuthFailure', () {
    test('retry: refreshes once and re-sends', () async {
      var tokenValid = false;
      var refreshes = 0;
      final sync = _online(
        config: SyncConfig(
          onAuthFailure: (_) async {
            refreshes++;
            tokenValid = true;
            return AuthRecovery.retry;
          },
        ),
      );
      addTearDown(sync.dispose);
      final remote = InMemoryRemoteStore<TestUser>(
        failureInjector: (_, __) =>
            tokenValid ? null : const AuthFailure('HTTP 401'),
      );
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: remote,
        serializer: const TestUserSerializer(),
      );

      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();

      final op = await _findOp(sync, opId);
      expect(op.status, SyncStatus.synced);
      expect(op.retryCount, 0, reason: 'an auth retry uses no retry budget');
      expect(refreshes, 1);
      expect(remote.peek('1'), isNotNull);
    });

    test('operations in one batch share a single refresh', () async {
      var tokenValid = false;
      var refreshes = 0;
      final sync = _online(
        config: SyncConfig(
          onAuthFailure: (_) async {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            tokenValid = true;
            return AuthRecovery.retry;
          },
        ),
      );
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) =>
              tokenValid ? null : const AuthFailure('HTTP 401'),
        ),
        serializer: const TestUserSerializer(),
      );

      final ids = [
        for (var i = 0; i < 3; i++)
          await users.save(TestUser(id: '$i', name: 'User $i')),
      ];
      await sync.syncNow();

      expect(refreshes, 1);
      for (final id in ids) {
        expect((await _findOp(sync, id)).status, SyncStatus.synced);
      }
    });

    test('a second auth failure after a refresh fails the operation', () async {
      var refreshes = 0;
      final sync = _online(
        config: SyncConfig(
          onAuthFailure: (_) async {
            refreshes++;
            return AuthRecovery.retry;
          },
        ),
      );
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) => const AuthFailure('HTTP 401'),
        ),
        serializer: const TestUserSerializer(),
      );

      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();

      expect((await _findOp(sync, opId)).status, SyncStatus.failed);
      expect(refreshes, 1);
    });

    test('pause: stops syncing and keeps the operation queued', () async {
      var signedIn = false;
      final sync = _online(
        config: SyncConfig(onAuthFailure: (_) async => AuthRecovery.pause),
      );
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) =>
              signedIn ? null : const AuthFailure('HTTP 401'),
        ),
        serializer: const TestUserSerializer(),
      );

      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();

      expect(sync.isPaused, isTrue);
      final paused = await _findOp(sync, opId);
      expect(paused.status, SyncStatus.ready);
      expect(paused.retryCount, 0);

      signedIn = true;
      sync.resume();
      await sync.syncNow();
      expect((await _findOp(sync, opId)).status, SyncStatus.synced);
    });

    test('a handler that throws falls back to failing the operation', () async {
      final sync = _online(
        config: SyncConfig(onAuthFailure: (_) async => throw StateError('x')),
      );
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) => const AuthFailure('HTTP 401'),
        ),
        serializer: const TestUserSerializer(),
      );

      final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.syncNow();
      expect((await _findOp(sync, opId)).status, SyncStatus.failed);
    });
  });

  group('rewriting local references to temporary ids', () {
    Future<InMemoryLocalStore<TestOrderItem>> run(
        {required bool rewrite}) async {
      final sync = _online(
        config: SyncConfig(
          rewriteLocalReferences: rewrite,
          retryPolicy: const RetryPolicy(initialDelay: Duration(hours: 1)),
        ),
      );
      addTearDown(sync.dispose);
      final orders = sync.registerCollection<TestUser>(
        name: 'orders',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          assignServerId: (item) => item.copyWith(id: 'server_${item.id}'),
        ),
        serializer: const TestUserSerializer(),
      );
      final localItems = InMemoryLocalStore<TestOrderItem>();
      final items = sync.registerCollection<TestOrderItem>(
        name: 'orderItems',
        localStore: localItems,
        // The item never reaches the server, so only the local rewrite can
        // fix its row.
        remoteStore: InMemoryRemoteStore<TestOrderItem>(
          failureInjector: (_, __) => const NetworkFailure('offline'),
        ),
        serializer: const TestOrderItemSerializer(),
        referenceFields: const ['orderId'],
      );

      final orderOp = await orders.save(TestUser(id: 'temp_1', name: 'Order'));
      await items.save(
        TestOrderItem(id: 'item_1', orderId: 'temp_1', sku: 'sku'),
        dependsOn: [orderOp],
      );
      await sync.syncNow();
      return localItems;
    }

    test('stored rows pointing at the temp id are rewritten', () async {
      final localItems = await run(rewrite: true);
      expect((await localItems.getById('item_1'))!.orderId, 'server_temp_1');
    });

    test('can be turned off', () async {
      final localItems = await run(rewrite: false);
      expect((await localItems.getById('item_1'))!.orderId, 'temp_1');
    });
  });

  group('pull cursor', () {
    test('survives a restart through the SyncMetadataStore', () async {
      final metadata = InMemorySyncMetadataStore();
      final remote = InMemoryRemoteStore<TestUser>();
      final local = InMemoryLocalStore<TestUser>();

      OfflineSync open() {
        final sync = OfflineSync(
          metadataStore: metadata,
          connectivity:
              ManualConnectivityMonitor(initial: ConnectivityState.online),
        );
        sync.registerCollection<TestUser>(
          name: 'users',
          localStore: local,
          remoteStore: remote,
          serializer: const TestUserSerializer(),
        );
        return sync;
      }

      remote.seed(TestUser(id: 'old', name: 'Old'),
          modifiedAt: DateTime.now().subtract(const Duration(days: 1)));
      var sync = open();
      expect(await sync.pullNow(), 1);
      await sync.dispose();

      sync = open();
      addTearDown(sync.dispose);
      expect(await sync.lastPulledAt('users'), isNotNull);
      remote.seed(TestUser(id: 'new', name: 'New'));
      expect(await sync.pullNow(), 1,
          reason: 'only the record changed since the saved cursor is pulled');
    });
  });

  group('event history', () {
    test('historyFor shows one operation\'s timeline, redacted', () async {
      var calls = 0;
      final sync = _online(config: const SyncConfig(retryPolicy: _fastRetries));
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(
          failureInjector: (_, __) =>
              calls++ == 0 ? const NetworkFailure('socket closed') : null,
        ),
        serializer: const TestUserSerializer(),
      );

      final opId = await users.save(TestUser(id: '1', name: 'Secret'));
      await sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sync.syncNow();

      final history = sync.inspector(redactedFields: {'name'}).historyFor(opId);
      expect(history.map((e) => e.runtimeType), [
        OperationStarted,
        OperationFailed,
        OperationStarted,
        OperationSucceeded,
      ]);
      final failed = history[1] as OperationFailed;
      expect(failed.error.message, 'socket closed');
      expect(failed.operation.payload['name'], '<redacted>');
      expect(failed.timestamp,
          sync.recentEvents.whereType<OperationFailed>().single.timestamp,
          reason: 'redaction keeps the original timestamp');
    });

    test('is bounded by eventHistoryLimit', () async {
      final sync = _online(config: const SyncConfig(eventHistoryLimit: 3));
      addTearDown(sync.dispose);
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: InMemoryLocalStore<TestUser>(),
        remoteStore: InMemoryRemoteStore<TestUser>(),
        serializer: const TestUserSerializer(),
      );
      for (var i = 0; i < 5; i++) {
        await users.save(TestUser(id: '$i', name: 'User $i'));
      }
      await sync.syncNow();

      expect(sync.recentEvents, hasLength(3));
      expect(sync.recentEvents.last, isA<SyncCompleted>());
    });
  });
}
