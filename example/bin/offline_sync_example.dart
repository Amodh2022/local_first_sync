// A single, minimal, runnable walkthrough of offline_sync's core behaviors:
//   0. basic save / get / watch — no sync concepts at all
//   1. dependency-aware sync + temporary ids
//   2. retry with exponential backoff
//   3. conflict resolution
//   4. operation coalescing — a burst of offline edits costs one request
//   5. a crash-safe queue that survives a restart
//   6. pause / resume and manual retry of a failed operation
//   7. pull sync — changes another device made, without clobbering yours
//   8. rollback of an optimistic write the backend rejected
//
// Plain Dart only — no Flutter widgets, no real database, no network, no
// external process to start first. Everything runs against offline_sync's
// in-memory LocalStore/RemoteStore stand-ins so the whole thing is readable
// top to bottom in one sitting.
//
// Run with (from the example/ directory, not this one):
//   flutter pub run offline_sync_example
import 'dart:async';

import 'package:offline_sync/offline_sync.dart';

class Order implements Identifiable {
  Order({required this.id, required this.customerName});

  @override
  final String id;
  final String customerName;

  Order copyWith({String? id}) => Order(id: id ?? this.id, customerName: customerName);

  @override
  String toString() => 'Order($id, customer: $customerName)';
}

class OrderSerializer implements Serializer<Order> {
  const OrderSerializer();

  @override
  Map<String, Object?> encode(Order value) =>
      {'id': value.id, 'customerName': value.customerName};

  @override
  Order decode(Map<String, Object?> data) =>
      Order(id: data['id']! as String, customerName: data['customerName']! as String);
}

class OrderItem implements Identifiable {
  OrderItem({required this.id, required this.orderId, required this.sku});

  @override
  final String id;
  final String orderId;
  final String sku;

  @override
  String toString() => 'OrderItem($id, order: $orderId, sku: $sku)';
}

class OrderItemSerializer implements Serializer<OrderItem> {
  const OrderItemSerializer();

  @override
  Map<String, Object?> encode(OrderItem value) =>
      {'id': value.id, 'orderId': value.orderId, 'sku': value.sku};

  @override
  OrderItem decode(Map<String, Object?> data) => OrderItem(
        id: data['id']! as String,
        orderId: data['orderId']! as String,
        sku: data['sku']! as String,
      );
}

Future<void> main() async {
  print('=== offline_sync example ===\n');
  await _basicSaveGetWatchDemo();
  await _dependencyAndTempIdDemo();
  await _retryDemo();
  await _conflictDemo();
  await _coalescingDemo();
  await _persistenceDemo();
  await _pauseAndManualRetryDemo();
  await _pullDemo();
  await _rollbackDemo();
}

/// 0. The simplest possible flow: no dependencies, no failures, no
/// conflicts. Just prove save/get/watch/sync work end-to-end.
Future<void> _basicSaveGetWatchDemo() async {
  print('--- 0. Basic save / get / watch ---');

  final sync = OfflineSync();
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: InMemoryLocalStore<Order>(),
    remoteStore: InMemoryRemoteStore<Order>(),
    serializer: const OrderSerializer(),
  );

  final sub = orders.watch().listen((all) => print('  [watch] ${all.length} order(s): $all'));

  await orders.save(Order(id: 'order_1', customerName: 'Amodh'));
  print('  get("order_1") right after save: ${await orders.get('order_1')}');

  await sync.syncNow();
  print('  Synced. Snapshot: ${(await sync.inspector().snapshot()).synced} synced op(s)\n');

  await sub.cancel();
  await sync.dispose();
}

/// 1. Writes are visible locally before any network call. An OrderItem that
/// depends on an offline-created Order stays BLOCKED until the Order syncs
/// and gets a permanent id — at which point the item's queued payload is
/// rewritten to point at that real id, entirely automatically.
Future<void> _dependencyAndTempIdDemo() async {
  print('--- 1. Dependency-aware sync + temporary ids ---');

  final localOrders = InMemoryLocalStore<Order>();
  final remoteOrders = InMemoryRemoteStore<Order>(
    // Simulate a backend that assigns its own permanent id on create.
    assignServerId: (order) => order.copyWith(id: 'srv_${order.id}'),
    latency: const Duration(milliseconds: 30),
  );
  final localItems = InMemoryLocalStore<OrderItem>();
  final remoteItems = InMemoryRemoteStore<OrderItem>(latency: const Duration(milliseconds: 30));

  final connectivity = ManualConnectivityMonitor(initial: ConnectivityState.offline);
  final sync = OfflineSync(connectivity: connectivity);

  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: localOrders,
    remoteStore: remoteOrders,
    serializer: const OrderSerializer(),
  );
  final orderItems = sync.registerCollection<OrderItem>(
    name: 'orderItems',
    localStore: localItems,
    remoteStore: remoteItems,
    serializer: const OrderItemSerializer(),
    // Declares which payload field(s) may hold another entity's (possibly
    // temporary) id, so the engine knows what to rewrite once that id
    // resolves to a permanent one.
    referenceFields: const ['orderId'],
  );

  final sub = sync.events.listen((e) => print('  [event] ${e.runtimeType}'));

  // The app is offline. Both writes are visible locally immediately.
  final orderOpId = await orders.save(Order(id: 'temp_order_1', customerName: 'Amodh'));
  final itemOpId = await orderItems.save(
    OrderItem(id: 'item_1', orderId: 'temp_order_1', sku: 'WIDGET-1'),
    dependsOn: [orderOpId],
  );

  print('  Local order right after save: ${await orders.get('temp_order_1')}');
  var snapshot = await sync.inspector().snapshot();
  final itemOp = snapshot.operations.firstWhere((o) => o.operationId == itemOpId);
  print('  Inspector (offline): pending=${snapshot.pending} blocked=${snapshot.blocked}');
  print('  Why is the item not synced? ${sync.inspector().explain(itemOp)}');

  print('  ...network returns...');
  connectivity.setOnline();
  await sync.syncNow();

  print('  Local order after sync (id was reassigned by the server): '
      '${await orders.get('srv_temp_order_1')}');
  print('  Order item queued payload was rewritten to the real order id: '
      '${remoteItems.peek('item_1')}');
  snapshot = await sync.inspector().snapshot();
  print('  Inspector (after sync): synced=${snapshot.synced} blocked=${snapshot.blocked}\n');

  await sub.cancel();
  await sync.dispose();
}

/// 2. A transient failure retries with exponential backoff instead of
/// failing permanently or hammering the backend.
Future<void> _retryDemo() async {
  print('--- 2. Retry with exponential backoff ---');

  var attempts = 0;
  final remoteOrders = InMemoryRemoteStore<Order>(
    failureInjector: (op, item) {
      attempts++;
      if (attempts < 3) {
        print('  [backend] attempt $attempts failed (simulated network blip)');
        return const NetworkFailure('simulated network blip');
      }
      print('  [backend] attempt $attempts succeeded');
      return null;
    },
  );

  final sync = OfflineSync(
    config: const SyncConfig(
      retryPolicy: RetryPolicy(
        initialDelay: Duration(milliseconds: 40),
        maxDelay: Duration(milliseconds: 200),
      ),
    ),
  );
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: InMemoryLocalStore<Order>(),
    remoteStore: remoteOrders,
    serializer: const OrderSerializer(),
  );

  final opId = await orders.save(Order(id: 'order_1', customerName: 'Retry Demo'));

  var op = (await sync.inspector().snapshot()).operations.firstWhere((o) => o.operationId == opId);
  var guard = 0;
  while (op.status != SyncStatus.synced && guard < 20) {
    await sync.syncNow();
    op = (await sync.inspector().snapshot()).operations.firstWhere((o) => o.operationId == opId);
    print('  ${sync.inspector().explain(op)}');
    if (op.status == SyncStatus.retry) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    guard++;
  }
  print('  Final status: ${op.status}\n');
  await sync.dispose();
}

/// 3. When the backend reports a conflict, the configured ConflictResolver
/// decides the outcome — here, server-wins — and the resolution is applied
/// to local storage rather than silently dropped.
Future<void> _conflictDemo() async {
  print('--- 3. Conflict resolution ---');

  final localOrders = InMemoryLocalStore<Order>();
  await localOrders.insert(Order(id: 'order_1', customerName: 'Original'));

  final remoteOrders = InMemoryRemoteStore<Order>(
    failureInjector: (op, item) => op == 'update'
        ? ConflictFailure(
            'a newer version exists on the server',
            remoteValue: const OrderSerializer()
                .encode(Order(id: 'order_1', customerName: 'Changed on another device')),
          )
        : null,
  );

  final sync = OfflineSync();
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: localOrders,
    remoteStore: remoteOrders,
    serializer: const OrderSerializer(),
    conflictResolver: const ServerWinsResolver<Order>(),
  );

  await orders.save(Order(id: 'order_1', customerName: 'Changed locally, offline'));
  await sync.syncNow();

  print('  After conflict (server-wins policy): ${await orders.get('order_1')}\n');
  await sync.dispose();
}

/// 4. Eight offline edits to one record should cost one request when the
/// network comes back, not eight.
Future<void> _coalescingDemo() async {
  print('--- 4. Operation coalescing ---');

  final connectivity =
      ManualConnectivityMonitor(initial: ConnectivityState.offline);
  final remote = InMemoryRemoteStore<Order>();
  final sync = OfflineSync(connectivity: connectivity);
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: InMemoryLocalStore<Order>(),
    remoteStore: remote,
    serializer: const OrderSerializer(),
  );

  for (var i = 1; i <= 8; i++) {
    await orders.save(Order(id: 'order_1', customerName: 'Draft $i'));
  }
  print('  8 offline edits queued as '
      '${(await sync.queue.all()).length} operation(s)');

  // A record created and deleted before either reached the server is work
  // the backend should never hear about at all.
  await orders.save(Order(id: 'order_typo', customerName: 'Mistake'));
  await orders.delete('order_typo');
  print('  create-then-delete while offline left '
      '${(await sync.queue.all()).where((o) => o.entityId == 'order_typo').length}'
      ' operation(s) for that record');

  connectivity.setOnline();
  await sync.syncNow();
  print('  Server received: ${remote.peek('order_1')}');
  print('  Server heard about the typo record: '
      '${remote.peek('order_typo') != null}\n');

  await sync.dispose();
}

/// 5. The failure the package exists to prevent: a user force-quits the app
/// while offline. With a PersistentSyncQueue their writes are still there.
Future<void> _persistenceDemo() async {
  print('--- 5. A queue that survives a restart ---');

  // Stands in for SharedPreferences / a file / a Drift table.
  String? storageSlot;
  JsonBlobOperationStore openStore() => JsonBlobOperationStore(
        readBlob: () async => storageSlot,
        writeBlob: (json) async => storageSlot = json,
      );

  final localStore = InMemoryLocalStore<Order>();
  final remote = InMemoryRemoteStore<Order>();
  final connectivity =
      ManualConnectivityMonitor(initial: ConnectivityState.offline);

  // --- first run: save offline, then "crash" ---
  var sync = OfflineSync(
    queue: await PersistentSyncQueue.open(openStore()),
    connectivity: connectivity,
  );
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: localStore,
    remoteStore: remote,
    serializer: const OrderSerializer(),
  );
  await orders.save(Order(id: 'order_1', customerName: 'Written on a plane'));
  await sync.dispose();
  print('  App killed while offline. Server has it: '
      '${remote.peek('order_1') != null}');

  // --- second run: same storage, now online ---
  connectivity.setOnline();
  sync = OfflineSync(
    queue: await PersistentSyncQueue.open(openStore()),
    connectivity: connectivity,
  );
  sync.registerCollection<Order>(
    name: 'orders',
    localStore: localStore,
    remoteStore: remote,
    serializer: const OrderSerializer(),
  );
  print('  Restarted with ${(await sync.queue.all()).length} recovered '
      'operation(s)');
  await sync.syncNow();
  print('  After restart the server has: ${remote.peek('order_1')}\n');

  await sync.dispose();
}

/// 6. An auth failure is not something to burn a retry budget on: pause,
/// fix the credentials, resume. And a permanently failed operation stays
/// visible and retryable rather than disappearing.
Future<void> _pauseAndManualRetryDemo() async {
  print('--- 6. Pause / resume and manual retry ---');

  var tokenIsValid = false;
  final remote = InMemoryRemoteStore<Order>(
    failureInjector: (op, item) =>
        tokenIsValid ? null : const AuthFailure('401: token expired'),
  );
  final sync = OfflineSync();
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: InMemoryLocalStore<Order>(),
    remoteStore: remote,
    serializer: const OrderSerializer(),
  );

  final opId = await orders.save(Order(id: 'order_1', customerName: 'Amodh'));
  await sync.syncNow();

  var op = (await sync.queue.getOperation(opId))!;
  print('  ${sync.inspector().explain(op)}');

  sync.pause();
  print('  Paused while the token is refreshed. Writes still land locally.');
  await orders.save(Order(id: 'order_2', customerName: 'Queued while paused'));
  print('  Server saw the paused write: ${remote.peek('order_2') != null}');

  tokenIsValid = true;
  sync.resume();
  print('  Resumed. Requeued ${await sync.retryAllFailed()} failed '
      'operation(s).');

  op = (await sync.queue.getOperation(opId))!;
  print('  ${sync.inspector().explain(op)}');
  print('  Server now has both orders: '
      '${remote.peek('order_1') != null && remote.peek('order_2') != null}\n');

  await sync.dispose();
}

/// 7. Pull sync: bring down what another device changed — but never on top
/// of a local write that has not reached the server yet.
Future<void> _pullDemo() async {
  print('--- 7. Pull sync ---');

  final connectivity =
      ManualConnectivityMonitor(initial: ConnectivityState.offline);
  final remote = InMemoryRemoteStore<Order>();
  final sync = OfflineSync(connectivity: connectivity);
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: InMemoryLocalStore<Order>(),
    remoteStore: remote,
    serializer: const OrderSerializer(),
  );

  // An edit of ours that hasn't synced yet...
  await orders.save(Order(id: 'order_1', customerName: 'My offline edit'));
  // ...and what the server holds, including a record we've never seen.
  remote.seed(Order(id: 'order_1', customerName: 'Stale server copy'));
  remote.seed(Order(id: 'order_2', customerName: 'Created on another device'));

  connectivity.setOnline();
  final applied = await sync.pullNow();

  print('  Pulled $applied record(s)');
  print('  Our unsynced edit survived: ${await orders.get('order_1')}');
  print('  The other device\'s record arrived: ${await orders.get('order_2')}\n');

  await sync.dispose();
}

/// 8. When the backend permanently rejects a write, the optimistic local
/// value is put back instead of leaving the user staring at data the server
/// never accepted.
Future<void> _rollbackDemo() async {
  print('--- 8. Rollback of a rejected write ---');

  var rejectUpdates = false;
  final remote = InMemoryRemoteStore<Order>(
    failureInjector: (op, item) => rejectUpdates && op == 'update'
        ? const ValidationFailure('customerName contains banned characters')
        : null,
  );
  final sync = OfflineSync(
    config: const SyncConfig(rollbackOnPermanentFailure: true),
  );
  final orders = sync.registerCollection<Order>(
    name: 'orders',
    localStore: InMemoryLocalStore<Order>(),
    remoteStore: remote,
    serializer: const OrderSerializer(),
  );

  await orders.save(Order(id: 'order_1', customerName: 'Accepted name'));
  await sync.syncNow();

  rejectUpdates = true;
  await orders.save(Order(id: 'order_1', customerName: r'<script>oops</script>'));
  print('  Optimistically shown locally: ${await orders.get('order_1')}');

  await sync.syncNow();
  print('  After the backend rejected it: ${await orders.get('order_1')}\n');

  await sync.dispose();
}
