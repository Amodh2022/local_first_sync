import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_drift/local_first_sync_drift.dart';
import 'package:test/test.dart';

import 'support/test_models.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('DriftOperationStore', () {
    late LocalFirstDatabase db;
    late DriftOperationStore store;

    setUp(() {
      db = LocalFirstDatabase(NativeDatabase.memory());
      store = DriftOperationStore(db);
    });
    tearDown(() => db.close());

    Map<String, Object?> row(String id, String status) => {
      'operationId': id,
      'status': status,
      'payload': {
        'id': 'u_$id',
        'tags': <Object?>[1, 'two', null],
      },
    };

    test('write, overwrite, delete, clear', () async {
      expect(await store.readAll(), isEmpty);

      await store.write(row('a', 'ready'));
      await store.write(row('b', 'ready'));
      await store.write(row('a', 'synced'));
      final all = await store.readAll();
      expect(all, hasLength(2));
      expect(
        all.firstWhere((r) => r['operationId'] == 'a'),
        row('a', 'synced'),
      );

      await store.delete('a');
      expect((await store.readAll()).single['operationId'], 'b');

      await store.clear();
      expect(await store.readAll(), isEmpty);
    });

    test(
      'round-trips a real SyncOperation through PersistentSyncQueue',
      () async {
        final sync = OfflineSync(
          queue: await PersistentSyncQueue.open(store),
          connectivity: ManualConnectivityMonitor(
            initial: ConnectivityState.offline,
          ),
        );
        final users = sync.registerCollection<TestUser>(
          name: 'users',
          localStore: DriftLocalStore(
            db,
            collection: 'users',
            serializer: const TestUserSerializer(),
          ),
          remoteStore: InMemoryRemoteStore<TestUser>(),
          serializer: const TestUserSerializer(),
        );
        final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
        final original = (await sync.inspector().snapshot()).operations.single;
        await sync.dispose();

        final reopened = await PersistentSyncQueue.open(store);
        final restored = (await reopened.all()).single;
        expect(restored.operationId, opId);
        expect(restored.idempotencyKey, original.idempotencyKey);
        expect(restored.payload, original.payload);
        expect(restored.type, original.type);
      },
    );
  });

  test('offline save -> app restart on a file-backed database -> online -> '
      'sync reaches the backend and local storage survives', () async {
    final dir = await Directory.systemTemp.createTemp('local_first_sync_drift');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    final remote = InMemoryRemoteStore<TestUser>();

    // First process: save while offline, then shut everything down.
    var db = LocalFirstDatabase(NativeDatabase(file));
    var sync = OfflineSync(
      queue: await PersistentSyncQueue.open(DriftOperationStore(db)),
      connectivity: ManualConnectivityMonitor(
        initial: ConnectivityState.offline,
      ),
    );
    var users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: DriftLocalStore(
        db,
        collection: 'users',
        serializer: const TestUserSerializer(),
      ),
      remoteStore: remote,
      serializer: const TestUserSerializer(),
    );
    final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
    await sync.syncNow();
    expect(remote.peek('1'), isNull);
    await sync.dispose();
    await db.close();

    // Second process: reopen the same file, now online.
    db = LocalFirstDatabase(NativeDatabase(file));
    sync = OfflineSync(
      queue: await PersistentSyncQueue.open(DriftOperationStore(db)),
      connectivity: ManualConnectivityMonitor(
        initial: ConnectivityState.online,
      ),
    );
    users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: DriftLocalStore(
        db,
        collection: 'users',
        serializer: const TestUserSerializer(),
      ),
      remoteStore: remote,
      serializer: const TestUserSerializer(),
    );
    expect(await users.get('1'), TestUser(id: '1', name: 'Amodh'));
    await sync.syncNow();

    expect(remote.peek('1'), TestUser(id: '1', name: 'Amodh'));
    expect(await users.get('1'), TestUser(id: '1', name: 'Amodh'));
    final op = (await sync.inspector().snapshot()).operations.firstWhere(
      (o) => o.operationId == opId,
    );
    expect(op.status, SyncStatus.synced);
    await sync.dispose();
    await db.close();
  });
}
