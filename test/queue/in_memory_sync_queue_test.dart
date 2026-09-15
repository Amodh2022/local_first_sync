import 'package:test/test.dart';
import 'package:local_first_sync/local_first_sync.dart';

SyncOperation _op(String id, {List<String> deps = const []}) {
  final now = DateTime.now();
  return SyncOperation(
    operationId: id,
    idempotencyKey: id,
    collection: 'users',
    entityId: id,
    type: SyncOperationType.create,
    payload: const {},
    createdAt: now,
    updatedAt: now,
    dependencyIds: deps,
  );
}

void main() {
  test('enqueue rejects a self-dependency', () async {
    final queue = InMemorySyncQueue();
    expect(
      () => queue.enqueue(_op('a', deps: ['a'])),
      throwsA(isA<CyclicDependencyException>()),
    );
  });

  test('enqueue rejects a cycle across multiple operations', () async {
    final queue = InMemorySyncQueue();
    await queue.enqueue(_op('a', deps: ['b']));
    expect(
      () => queue.enqueue(_op('b', deps: ['a'])),
      throwsA(isA<CyclicDependencyException>()),
    );
  });

  test('enqueue accepts a valid dependency chain', () async {
    final queue = InMemorySyncQueue();
    await queue.enqueue(_op('order'));
    await queue.enqueue(_op('orderItem', deps: ['order']));
    await queue.enqueue(_op('payment', deps: ['orderItem']));

    expect(await queue.all(), hasLength(3));
  });

  test('dependentsOf returns operations depending on the given id', () async {
    final queue = InMemorySyncQueue();
    await queue.enqueue(_op('order'));
    await queue.enqueue(_op('orderItem', deps: ['order']));
    await queue.enqueue(_op('unrelated'));

    final dependents = await queue.dependentsOf('order');
    expect(dependents.map((o) => o.operationId), ['orderItem']);
  });

  test('watchAll emits the current snapshot immediately, then on change',
      () async {
    final queue = InMemorySyncQueue();
    final emissions = <int>[];
    final sub = queue.watchAll().listen((ops) => emissions.add(ops.length));
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    expect(emissions, [0]);

    await queue.enqueue(_op('a'));
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last, 1);
  });
}
