import 'package:test/test.dart';
import 'package:offline_sync/offline_sync.dart';

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

    var connectivity = ManualConnectivityMonitor(initial: ConnectivityState.offline);
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
    connectivity = ManualConnectivityMonitor(initial: ConnectivityState.offline);
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
}
