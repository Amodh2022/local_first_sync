import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_drift/local_first_sync_drift.dart';
import 'package:test/test.dart';

import 'support/test_models.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('read returns what write stored, and write overwrites', () async {
    final db = LocalFirstDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftMetadataStore(db);

    expect(await store.read('k'), isNull);
    await store.write('k', 'v1');
    await store.write('k', 'v2');
    await store.write('other', 'x');
    expect(await store.read('k'), 'v2');
    expect(await store.read('other'), 'x');
  });

  test(
    'the pull cursor survives a restart on a file-backed database',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'local_first_sync_drift',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      final remote = InMemoryRemoteStore<TestUser>();

      Future<(LocalFirstDatabase, OfflineSync)> open() async {
        final db = LocalFirstDatabase(NativeDatabase(file));
        final sync = OfflineSync(
          queue: await PersistentSyncQueue.open(DriftOperationStore(db)),
          metadataStore: DriftMetadataStore(db),
          connectivity: ManualConnectivityMonitor(
            initial: ConnectivityState.online,
          ),
        );
        sync.registerCollection<TestUser>(
          name: 'users',
          localStore: DriftLocalStore(
            db,
            collection: 'users',
            serializer: const TestUserSerializer(),
          ),
          remoteStore: remote,
          serializer: const TestUserSerializer(),
        );
        return (db, sync);
      }

      remote.seed(
        TestUser(id: 'old', name: 'Old'),
        modifiedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      var (db, sync) = await open();
      expect(await sync.pullNow(), 1);
      await sync.dispose();
      await db.close();

      (db, sync) = await open();
      addTearDown(db.close);
      addTearDown(sync.dispose);
      expect(await sync.lastPulledAt('users'), isNotNull);
      remote.seed(TestUser(id: 'new', name: 'New'));
      expect(
        await sync.pullNow(),
        1,
        reason: 'only the record changed since the saved cursor is pulled',
      );
    },
  );
}
