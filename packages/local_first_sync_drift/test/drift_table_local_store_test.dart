import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:test/test.dart';

import 'support/todo_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late TodoDatabase db;
  late TodoStore todos;

  setUp(() {
    db = TodoDatabase(NativeDatabase.memory());
    todos = TodoStore(db);
  });
  tearDown(() => db.close());

  test('insert, get, update (upsert), delete', () async {
    expect(await todos.getById('1'), isNull);
    await todos.insert(Todo(id: '1', title: 'Milk'));
    expect(await todos.getById('1'), Todo(id: '1', title: 'Milk'));

    await todos.update(Todo(id: '1', title: 'Milk', done: true));
    await todos.update(Todo(id: '2', title: 'Bread'));
    expect(await todos.getAll(), hasLength(2));
    expect((await todos.getById('1'))!.done, isTrue);

    await todos.delete('1');
    expect(await todos.getById('1'), isNull);
  });

  test('getAll follows the overridden orderBy', () async {
    await todos.insert(Todo(id: '1', title: 'c'));
    await todos.insert(Todo(id: '2', title: 'a'));
    await todos.insert(Todo(id: '3', title: 'b'));
    expect((await todos.getAll()).map((t) => t.title), ['a', 'b', 'c']);
  });

  test('watchAll and watchById emit immediately, then on change', () async {
    final all = todos.watchAll();
    final one = todos.watchById('1');
    expect(await all.first, isEmpty);
    expect(await one.first, isNull);

    final allLater = expectLater(
      all,
      emitsThrough(predicate<List<Todo>>((l) => l.length == 1)),
    );
    final oneLater = expectLater(
      one,
      emitsThrough(Todo(id: '1', title: 'Milk')),
    );
    await todos.insert(Todo(id: '1', title: 'Milk'));
    await allLater;
    await oneLater;
  });

  test('reassignId leaves only the new id', () async {
    await todos.insert(Todo(id: 'temp_1', title: 'Milk'));
    await todos.reassignId('temp_1', Todo(id: 'server_1', title: 'Milk'));
    expect(await todos.getById('temp_1'), isNull);
    expect(
      await todos.getById('server_1'),
      Todo(id: 'server_1', title: 'Milk'),
    );
    expect(await todos.getAll(), hasLength(1));
  });

  test(
    'syncs end to end through OfflineSync with a server-assigned id',
    () async {
      final remote = InMemoryRemoteStore<Todo>(
        assignServerId: (t) => Todo(id: 'server_${t.id}', title: t.title),
      );
      final sync = OfflineSync(
        connectivity: ManualConnectivityMonitor(
          initial: ConnectivityState.online,
        ),
      );
      addTearDown(sync.dispose);
      final collection = sync.registerCollection<Todo>(
        name: 'todos',
        localStore: todos,
        remoteStore: remote,
        serializer: const TodoSerializer(),
      );

      await collection.save(Todo(id: 'temp_1', title: 'Milk'));
      await sync.syncNow();

      expect(remote.peek('server_temp_1'), isNotNull);
      expect(await todos.getById('temp_1'), isNull);
      expect((await todos.getById('server_temp_1'))!.title, 'Milk');
    },
  );
}
