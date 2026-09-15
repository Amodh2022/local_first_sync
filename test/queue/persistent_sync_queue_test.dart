import 'package:test/test.dart';
import 'package:local_first_sync/local_first_sync.dart';

import '../support/test_models.dart';

SyncOperation _op(
  String id, {
  SyncStatus status = SyncStatus.ready,
  List<String> dependsOn = const [],
  int priority = 0,
}) {
  final now = DateTime.now();
  return SyncOperation(
    operationId: id,
    idempotencyKey: id,
    collection: 'users',
    entityId: 'u_$id',
    type: SyncOperationType.create,
    payload: {'id': 'u_$id', 'name': 'User $id'},
    createdAt: now,
    updatedAt: now,
    status: status,
    dependencyIds: dependsOn,
    priority: priority,
  );
}

void main() {
  group('SyncOperation JSON round-trip', () {
    test('preserves every field', () {
      final original = _op('a', dependsOn: ['b'], priority: 7).copyWith(
        lastError: 'boom',
        nextRetryAt: DateTime.now().add(const Duration(seconds: 30)),
        blockedReason: 'waiting',
        retryCount: 3,
        status: SyncStatus.retry,
        rollbackPayload: {'id': 'u_a', 'name': 'Previous'},
      );

      final restored = SyncOperation.fromJson(original.toJson());

      expect(restored.operationId, original.operationId);
      expect(restored.idempotencyKey, original.idempotencyKey);
      expect(restored.collection, original.collection);
      expect(restored.entityId, original.entityId);
      expect(restored.type, original.type);
      expect(restored.payload, original.payload);
      expect(restored.createdAt, original.createdAt);
      expect(restored.retryCount, 3);
      expect(restored.status, SyncStatus.retry);
      expect(restored.dependencyIds, ['b']);
      expect(restored.lastError, 'boom');
      expect(restored.nextRetryAt, original.nextRetryAt);
      expect(restored.blockedReason, 'waiting');
      expect(restored.priority, 7);
      expect(restored.rollbackPayload, {'id': 'u_a', 'name': 'Previous'});
    });

    test(
        'an operation that was in flight when the process died comes back '
        'ready, not stuck syncing', () {
      final inFlight = _op('a', status: SyncStatus.syncing);
      final restored = SyncOperation.fromJson(inFlight.toJson());

      expect(restored.status, SyncStatus.ready);
      expect(restored.idempotencyKey, inFlight.idempotencyKey,
          reason: 're-sending under the same key is what makes it safe');
    });
  });

  group('PersistentSyncQueue', () {
    test('survives a restart with the queue intact', () async {
      final store = InMemoryOperationStore();
      final queue = await PersistentSyncQueue.open(store);
      await queue.enqueue(_op('a'));
      await queue.enqueue(_op('b', status: SyncStatus.failed));

      final reopened = await PersistentSyncQueue.open(store);
      final restored = await reopened.all();

      expect(restored.map((op) => op.operationId), unorderedEquals(['a', 'b']));
      expect(
        restored.firstWhere((op) => op.operationId == 'b').status,
        SyncStatus.failed,
      );
    });

    test('removeOperation deletes the persisted row too', () async {
      final store = InMemoryOperationStore();
      final queue = await PersistentSyncQueue.open(store);
      await queue.enqueue(_op('a'));
      await queue.removeOperation('a');

      expect(await (await PersistentSyncQueue.open(store)).all(), isEmpty);
    });

    test('rejects a cyclic dependency exactly like the in-memory queue',
        () async {
      final queue = await PersistentSyncQueue.open(InMemoryOperationStore());
      await queue.enqueue(_op('a', dependsOn: ['b']));

      expect(
        () => queue.enqueue(_op('b', dependsOn: ['a'])),
        throwsA(isA<CyclicDependencyException>()),
      );
    });

    test('clear wipes both the mirror and the store', () async {
      final store = InMemoryOperationStore();
      final queue = await PersistentSyncQueue.open(store);
      await queue.enqueue(_op('a'));
      await queue.clear();

      expect(await queue.all(), isEmpty);
      expect(await store.readAll(), isEmpty);
    });

    test('drives a real sync end to end after a restart', () async {
      final store = InMemoryOperationStore();
      final localStore = InMemoryLocalStore<TestUser>();
      final remoteStore = InMemoryRemoteStore<TestUser>();
      final connectivity =
          ManualConnectivityMonitor(initial: ConnectivityState.offline);

      // First "process": save while offline, then die.
      var sync = OfflineSync(
        queue: await PersistentSyncQueue.open(store),
        connectivity: connectivity,
      );
      final users = sync.registerCollection<TestUser>(
        name: 'users',
        localStore: localStore,
        remoteStore: remoteStore,
        serializer: const TestUserSerializer(),
      );
      await users.save(TestUser(id: '1', name: 'Amodh'));
      await sync.dispose();
      expect(remoteStore.peek('1'), isNull);

      // Second "process": same store, now online.
      connectivity.setOnline();
      sync = OfflineSync(
        queue: await PersistentSyncQueue.open(store),
        connectivity: connectivity,
      );
      sync.registerCollection<TestUser>(
        name: 'users',
        localStore: localStore,
        remoteStore: remoteStore,
        serializer: const TestUserSerializer(),
      );
      await sync.syncNow();

      expect(remoteStore.peek('1')?.name, 'Amodh');
      await sync.dispose();
    });
  });

  group('JsonBlobOperationStore', () {
    test('persists through a caller-supplied string slot', () async {
      String? slot;
      JsonBlobOperationStore makeStore() => JsonBlobOperationStore(
            readBlob: () async => slot,
            writeBlob: (json) async => slot = json,
          );

      final queue = await PersistentSyncQueue.open(makeStore());
      await queue.enqueue(_op('a'));
      expect(slot, isNotNull);

      final reopened = await PersistentSyncQueue.open(makeStore());
      expect((await reopened.all()).single.operationId, 'a');
    });
  });
}
