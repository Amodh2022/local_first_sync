import 'package:test/test.dart';
import 'package:local_first_sync/local_first_sync.dart';

import '../support/test_models.dart';

void main() {
  test(
      'offline mutation -> simulated app restart -> still offline -> '
      'network returns -> sync -> remote and local both reflect it', () async {
    // These three stand in for what a real persistence layer would keep
    // across a restart: the local database, the sync queue's own table, and
    // (from the server's point of view) the backend.
    final localUsers = InMemoryLocalStore<TestUser>();
    final remoteUsers = InMemoryRemoteStore<TestUser>();
    final sharedQueue = InMemorySyncQueue();

    var connectivity =
        ManualConnectivityMonitor(initial: ConnectivityState.offline);
    var sync = OfflineSync(queue: sharedQueue, connectivity: connectivity);
    var users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
    );

    final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
    expect(await users.get('1'), TestUser(id: '1', name: 'Amodh'));

    await sync.syncNow(); // offline: must not reach the "backend"
    expect(remoteUsers.peek('1'), isNull);

    // --- simulated app restart: new engine, same underlying "persisted" state ---
    await sync.dispose();
    connectivity =
        ManualConnectivityMonitor(initial: ConnectivityState.offline);
    sync = OfflineSync(queue: sharedQueue, connectivity: connectivity);
    users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
    );

    // The mutation survived the "restart" in both local storage and the queue.
    expect(await users.get('1'), TestUser(id: '1', name: 'Amodh'));
    expect((await sync.inspector().snapshot()).pending, 1);

    // Still offline post-restart: still must not sync.
    await sync.syncNow();
    expect(remoteUsers.peek('1'), isNull);

    // Network returns.
    connectivity.setOnline();
    await sync.syncNow();

    expect(remoteUsers.peek('1'), TestUser(id: '1', name: 'Amodh'));
    expect(await users.get('1'), TestUser(id: '1', name: 'Amodh'));
    final op = (await sync.inspector().snapshot())
        .operations
        .firstWhere((o) => o.operationId == opId);
    expect(op.status, SyncStatus.synced);
  });

  test(
      'a write the server applied but never acknowledged is re-sent after a '
      'restart and deduplicated by its idempotency key', () async {
    final store = InMemoryOperationStore();
    final localUsers = InMemoryLocalStore<TestUser>();
    final remoteUsers = InMemoryRemoteStore<TestUser>();

    var sync = OfflineSync(
      queue: await PersistentSyncQueue.open(store),
      connectivity:
          ManualConnectivityMonitor(initial: ConnectivityState.offline),
    );
    final users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
    );
    final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
    final queued = (await sync.inspector().snapshot())
        .operations
        .firstWhere((o) => o.operationId == opId);
    await sync.dispose();

    // The request reached the server, then the process died before the
    // response came back: the row is still `syncing` on disk.
    await remoteUsers.createWithKey(TestUser(id: '1', name: 'Amodh'),
        idempotencyKey: queued.idempotencyKey);
    final row = (await store.readAll()).single;
    await store.write({...row, 'status': SyncStatus.syncing.name});

    sync = OfflineSync(
      queue: await PersistentSyncQueue.open(store),
      connectivity:
          ManualConnectivityMonitor(initial: ConnectivityState.online),
    );
    sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
    );
    await sync.syncNow();

    final op = (await sync.inspector().snapshot())
        .operations
        .firstWhere((o) => o.operationId == opId);
    expect(op.status, SyncStatus.synced);
    expect(remoteUsers.receivedIdempotencyKeys,
        [queued.idempotencyKey, queued.idempotencyKey]);
    expect(remoteUsers.appliedWrites, 1);
    await sync.dispose();
  });
}
