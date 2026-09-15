import 'package:test/test.dart';
import 'package:local_first_sync/local_first_sync.dart';

import '../support/test_models.dart';

Future<SyncOperation> _findOp(OfflineSync sync, String operationId) async {
  final snapshot = await sync.inspector().snapshot();
  return snapshot.operations.firstWhere((o) => o.operationId == operationId);
}

void main() {
  test('a simple create syncs successfully and is marked synced', () async {
    final localUsers = InMemoryLocalStore<TestUser>();
    final remoteUsers = InMemoryRemoteStore<TestUser>();
    final sync = OfflineSync();
    final users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
    );

    final opId = await users.save(TestUser(id: '1', name: 'Amodh'));
    await sync.syncNow();

    expect(remoteUsers.peek('1'), TestUser(id: '1', name: 'Amodh'));
    expect((await _findOp(sync, opId)).status, SyncStatus.synced);
  });

  test(
      'temp id reassignment rewrites a dependent operation payload and '
      'unblocks it', () async {
    final localOrders = InMemoryLocalStore<TestUser>();
    final remoteOrders = InMemoryRemoteStore<TestUser>(
      assignServerId: (item) => item.copyWith(id: 'server_${item.id}'),
    );
    final localItems = InMemoryLocalStore<TestOrderItem>();
    final remoteItems = InMemoryRemoteStore<TestOrderItem>();

    final sync = OfflineSync();
    final orders = sync.registerCollection<TestUser>(
      name: 'orders',
      localStore: localOrders,
      remoteStore: remoteOrders,
      serializer: const TestUserSerializer(),
    );
    final items = sync.registerCollection<TestOrderItem>(
      name: 'orderItems',
      localStore: localItems,
      remoteStore: remoteItems,
      serializer: const TestOrderItemSerializer(),
      referenceFields: const ['orderId'],
    );

    final orderOpId =
        await orders.save(TestUser(id: 'temp_order_1', name: 'Order'));
    final itemOpId = await items.save(
      TestOrderItem(id: 'item_1', orderId: 'temp_order_1', sku: 'sku'),
      dependsOn: [orderOpId],
    );

    expect((await _findOp(sync, itemOpId)).status, SyncStatus.blocked);

    await sync.syncNow();

    expect(remoteOrders.peek('server_temp_order_1'), isNotNull);
    expect(await orders.get('temp_order_1'), isNull);
    expect(await orders.get('server_temp_order_1'), isNotNull);

    final syncedItem = remoteItems.peek('item_1');
    expect(syncedItem, isNotNull);
    expect(syncedItem!.orderId, 'server_temp_order_1');
    expect((await _findOp(sync, itemOpId)).status, SyncStatus.synced);
  });

  test('a transient failure retries with backoff and eventually succeeds',
      () async {
    var attempts = 0;
    final localUsers = InMemoryLocalStore<TestUser>();
    final remoteUsers = InMemoryRemoteStore<TestUser>(
      failureInjector: (op, item) {
        attempts++;
        return attempts < 3 ? const NetworkFailure('offline') : null;
      },
    );
    final sync = OfflineSync(
      config: const SyncConfig(
        retryPolicy: RetryPolicy(
          initialDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 5),
        ),
      ),
    );
    final users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
    );

    final opId = await users.save(TestUser(id: '1', name: 'Amodh'));

    await sync.syncNow();
    expect((await _findOp(sync, opId)).status, SyncStatus.retry);

    SyncOperation op;
    var iterations = 0;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sync.syncNow();
      op = await _findOp(sync, opId);
      iterations++;
    } while (op.status != SyncStatus.synced && iterations < 20);

    expect(op.status, SyncStatus.synced);
    expect(attempts, 3);
  });

  test('a permanently failed operation blocks its dependents with a reason',
      () async {
    final localOrders = InMemoryLocalStore<TestUser>();
    final remoteOrders = InMemoryRemoteStore<TestUser>(
      failureInjector: (op, item) => const ValidationFailure('bad order'),
    );
    final localItems = InMemoryLocalStore<TestOrderItem>();
    final remoteItems = InMemoryRemoteStore<TestOrderItem>();

    final sync = OfflineSync();
    final orders = sync.registerCollection<TestUser>(
      name: 'orders',
      localStore: localOrders,
      remoteStore: remoteOrders,
      serializer: const TestUserSerializer(),
    );
    final items = sync.registerCollection<TestOrderItem>(
      name: 'orderItems',
      localStore: localItems,
      remoteStore: remoteItems,
      serializer: const TestOrderItemSerializer(),
      referenceFields: const ['orderId'],
    );

    final orderOpId =
        await orders.save(TestUser(id: 'temp_order_1', name: 'Order'));
    final itemOpId = await items.save(
      TestOrderItem(id: 'item_1', orderId: 'temp_order_1', sku: 'sku'),
      dependsOn: [orderOpId],
    );

    await sync.syncNow();

    final orderOp = await _findOp(sync, orderOpId);
    final itemOp = await _findOp(sync, itemOpId);

    expect(orderOp.status, SyncStatus.failed);
    expect(itemOp.status, SyncStatus.blocked);
    expect(itemOp.blockedReason, contains('failed permanently'));

    final explanation = sync.inspector().explain(itemOp);
    expect(explanation, contains('BLOCKED'));
  });

  test('a conflict is routed through the configured resolver', () async {
    final localUsers = InMemoryLocalStore<TestUser>();
    await localUsers.insert(TestUser(id: '1', name: 'Local'));

    final remoteUsers = InMemoryRemoteStore<TestUser>(
      failureInjector: (op, item) => op == 'update'
          ? ConflictFailure(
              'diverged',
              remoteValue: const TestUserSerializer()
                  .encode(TestUser(id: '1', name: 'Remote')),
            )
          : null,
    );

    final sync = OfflineSync();
    final users = sync.registerCollection<TestUser>(
      name: 'users',
      localStore: localUsers,
      remoteStore: remoteUsers,
      serializer: const TestUserSerializer(),
      conflictResolver: const ServerWinsResolver<TestUser>(),
    );

    final opId = await users.save(TestUser(id: '1', name: 'Local Updated'));
    await sync.syncNow();

    expect(await users.get('1'), TestUser(id: '1', name: 'Remote'));
    expect((await _findOp(sync, opId)).status, SyncStatus.synced);
  });
}
