import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/offline_sync.dart';

import '../support/test_models.dart';

void main() {
  late InMemoryLocalStore<TestUser> localStore;
  late InMemoryRemoteStore<TestUser> remoteStore;
  late ManualConnectivityMonitor connectivity;
  late OfflineSync sync;
  late Collection<TestUser> users;

  setUp(() {
    localStore = InMemoryLocalStore<TestUser>();
    remoteStore = InMemoryRemoteStore<TestUser>();
    connectivity = ManualConnectivityMonitor(initial: ConnectivityState.online);
    sync = OfflineSync(connectivity: connectivity);
    users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localStore,
      remoteStore: remoteStore,
      serializer: const TestUserSerializer(),
    );
    addTearDown(sync.dispose);
  });

  test('pulls records another device created into the local store', () async {
    remoteStore.seed(TestUser(id: 'remote_1', name: 'From another device'));

    expect(await sync.pullNow(), 1);
    expect((await users.get('remote_1'))!.name, 'From another device');
  });

  test('never overwrites a local write that has not synced yet', () async {
    connectivity.setOffline();
    await users.save(TestUser(id: '1', name: 'My unsynced edit'));
    remoteStore.seed(TestUser(id: '1', name: 'Stale server copy'));
    connectivity.setOnline();

    await sync.pullNow();

    expect((await users.get('1'))!.name, 'My unsynced edit',
        reason: 'a pull must not destroy work still sitting in the queue');
  });

  test('overwrites a local record once its own work has synced', () async {
    await users.save(TestUser(id: '1', name: 'Mine'));
    await sync.syncNow();
    remoteStore.seed(TestUser(id: '1', name: 'Edited elsewhere'));

    await sync.pullNow();

    expect((await users.get('1'))!.name, 'Edited elsewhere');
  });

  test('reports what it applied and skipped as an event', () async {
    connectivity.setOffline();
    await users.save(TestUser(id: '1', name: 'Unsynced'));
    connectivity.setOnline();
    remoteStore.seed(TestUser(id: '1', name: 'Server copy'));
    remoteStore.seed(TestUser(id: '2', name: 'New from server'));

    final events = <SyncEvent>[];
    final sub = sync.events.listen(events.add);
    addTearDown(sub.cancel);

    await sync.pullNow();
    await Future<void>.delayed(Duration.zero);

    final completed = events.whereType<PullCompleted>().single;
    expect(completed.collection, 'users');
    expect(completed.applied, 1);
    expect(completed.skipped, 1);
  });

  test('a second pull only asks for changes since the first', () async {
    remoteStore.seed(TestUser(id: '1', name: 'First'));
    await sync.pullNow();

    // Nothing new on the server — the incremental pull applies nothing.
    expect(await sync.pullNow(), 0);

    remoteStore.seed(TestUser(id: '2', name: 'Later'));
    expect(await sync.pullNow(), 1);
  });

  test('pulling does nothing while offline', () async {
    remoteStore.seed(TestUser(id: '1', name: 'Server'));
    connectivity.setOffline();

    expect(await sync.pullNow(), 0);
    expect(await users.get('1'), isNull);
  });

  test('a pull failure is surfaced as an event, not thrown', () async {
    final failing = InMemoryRemoteStore<TestUser>(
      failureInjector: (op, _) =>
          op == 'fetchChanges' ? const NetworkFailure('no route to host') : null,
    );
    final failingSync = OfflineSync(connectivity: connectivity);
    failingSync.registerCollection<TestUser>(
      name: 'users',
      localStore: InMemoryLocalStore<TestUser>(),
      remoteStore: failing,
      serializer: const TestUserSerializer(),
    );
    addTearDown(failingSync.dispose);

    final events = <SyncEvent>[];
    final sub = failingSync.events.listen(events.add);
    addTearDown(sub.cancel);

    expect(await failingSync.pullNow(), 0);
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<PullFailed>(), hasLength(1));
  });

  test('a push-only remote store is simply skipped', () async {
    final pushOnlySync = OfflineSync(connectivity: connectivity);
    pushOnlySync.registerCollection<TestUser>(
      name: 'users',
      localStore: InMemoryLocalStore<TestUser>(),
      remoteStore: _PushOnlyRemoteStore(),
      serializer: const TestUserSerializer(),
    );
    addTearDown(pushOnlySync.dispose);

    expect(await pushOnlySync.pullNow(), 0);
  });
}

class _PushOnlyRemoteStore implements RemoteStore<TestUser> {
  @override
  Future<TestUser> create(TestUser item) async => item;

  @override
  Future<TestUser> update(TestUser item) async => item;

  @override
  Future<void> delete(String id) async {}
}
