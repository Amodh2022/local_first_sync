import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/offline_sync.dart';

import '../support/test_models.dart';

void main() {
  late InMemoryLocalStore<TestUser> localStore;
  late InMemorySyncQueue queue;
  late Collection<TestUser> users;

  /// A collection with coalescing off, for asserting the raw one-write-one-
  /// operation behavior.
  late Collection<TestUser> rawUsers;

  setUp(() {
    localStore = InMemoryLocalStore<TestUser>();
    queue = InMemorySyncQueue();
    users = Collection<TestUser>(
      name: 'users',
      localStore: localStore,
      queue: queue,
      serializer: const TestUserSerializer(),
    );
    rawUsers = Collection<TestUser>(
      name: 'users',
      localStore: localStore,
      queue: queue,
      serializer: const TestUserSerializer(),
      coalesceOperations: false,
    );
  });

  test('save is visible locally immediately, without any network', () async {
    final user = TestUser(id: '1', name: 'Amodh');
    await users.save(user);

    expect(await users.get('1'), user);
    expect(await users.getAll(), [user]);
  });

  test('save enqueues a create operation the first time, update after',
      () async {
    final user = TestUser(id: '1', name: 'Amodh');
    final createOpId = await rawUsers.save(user);
    final createOp = await queue.getOperation(createOpId);
    expect(createOp!.type, SyncOperationType.create);
    expect(createOp.status, SyncStatus.ready);

    final updateOpId = await rawUsers.save(user.copyWith(name: 'Amodh N'));
    final updateOp = await queue.getOperation(updateOpId);
    expect(updateOp!.type, SyncOperationType.update);
    expect(await queue.all(), hasLength(2));
  });

  test('delete removes locally and enqueues a delete operation', () async {
    final user = TestUser(id: '1', name: 'Amodh');
    await rawUsers.save(user);

    final opId = await rawUsers.delete('1');
    expect(await users.get('1'), isNull);
    final op = await queue.getOperation(opId);
    expect(op!.type, SyncOperationType.delete);
  });

  test('save captures the pre-write state as a rollback payload', () async {
    await rawUsers.save(TestUser(id: '1', name: 'Amodh'));
    final createOp = (await queue.all()).single;
    expect(createOp.rollbackPayload, isNull,
        reason: 'nothing existed before a create; rollback means delete');

    final updateOpId = await rawUsers.save(TestUser(id: '1', name: 'Renamed'));
    final updateOp = await queue.getOperation(updateOpId);
    expect(updateOp!.rollbackPayload!['name'], 'Amodh');
  });

  test('save honors priority', () async {
    final opId = await rawUsers.save(TestUser(id: '1', name: 'Urgent'),
        priority: 10);
    expect((await queue.getOperation(opId))!.priority, 10);
  });

  group('coalescing', () {
    test('two queued updates collapse into a single operation', () async {
      await users.save(TestUser(id: '1', name: 'A'));
      await users.save(TestUser(id: '1', name: 'B'));
      final finalOpId = await users.save(TestUser(id: '1', name: 'C'));

      final all = await queue.all();
      expect(all, hasLength(1));
      expect(all.single.operationId, finalOpId);
      expect(all.single.payload['name'], 'C',
          reason: 'the newest payload wins');
      expect(all.single.type, SyncOperationType.create,
          reason: 'the backend has never seen this record, so it stays a '
              'create rather than becoming an update it would reject');
    });

    test('an update on a synced record does not touch the synced operation',
        () async {
      final createOpId = await users.save(TestUser(id: '1', name: 'A'));
      final createOp = await queue.getOperation(createOpId);
      await queue.updateOperation(createOp!.copyWith(status: SyncStatus.synced));

      final updateOpId = await users.save(TestUser(id: '1', name: 'B'));
      expect(await queue.all(), hasLength(2));
      expect((await queue.getOperation(updateOpId))!.type,
          SyncOperationType.update);
    });

    test('create then delete while offline sends nothing at all', () async {
      await users.save(TestUser(id: '1', name: 'Typo'));
      await users.delete('1');

      expect(await queue.all(), isEmpty,
          reason: 'the backend never knew this record existed');
    });

    test('delete after a synced create still enqueues the delete', () async {
      final createOpId = await users.save(TestUser(id: '1', name: 'A'));
      final createOp = await queue.getOperation(createOpId);
      await queue.updateOperation(createOp!.copyWith(status: SyncStatus.synced));

      final deleteOpId = await users.delete('1');
      expect((await queue.getOperation(deleteOpId))!.type,
          SyncOperationType.delete);
    });

    test('an operation another operation depends on is never coalesced away',
        () async {
      final firstId = await users.save(TestUser(id: '1', name: 'A'));
      await users.save(TestUser(id: '2', name: 'Child'), dependsOn: [firstId]);

      await users.save(TestUser(id: '1', name: 'B'));

      expect(await queue.getOperation(firstId), isNotNull,
          reason: 'removing it would orphan its dependent');
      expect(await queue.all(), hasLength(3));
    });

    test('a coalesced operation inherits the dependencies it absorbed',
        () async {
      final blockerId = await users.save(TestUser(id: '9', name: 'Blocker'));
      await users.save(TestUser(id: '1', name: 'A'), dependsOn: [blockerId]);
      final secondId = await users.save(TestUser(id: '1', name: 'B'));

      final merged = await queue.getOperation(secondId);
      expect(merged!.dependencyIds, contains(blockerId));
      expect(merged.status, SyncStatus.blocked,
          reason: 'it must not sync ahead of the dependency it absorbed');
    });
  });

  test('watch emits the current snapshot immediately, then on every change', () async {
    final emissions = <List<TestUser>>[];
    final sub = users.watch().listen(emissions.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    expect(emissions, [<TestUser>[]]);

    final user = TestUser(id: '1', name: 'Amodh');
    await users.save(user);
    await Future<void>.delayed(Duration.zero);

    expect(emissions.last, [user]);
  });

  test('save with dependsOn starts the operation as blocked', () async {
    final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
    final dependentOpId = await users.save(
      TestUser(id: '2', name: 'Dependent'),
      dependsOn: [opId],
    );

    final dependentOp = await queue.getOperation(dependentOpId);
    expect(dependentOp!.status, SyncStatus.blocked);
  });
}
