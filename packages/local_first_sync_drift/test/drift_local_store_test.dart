import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:local_first_sync_drift/local_first_sync_drift.dart';
import 'package:test/test.dart';

import 'support/test_models.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LocalFirstDatabase db;
  late DriftLocalStore<TestUser> users;

  setUp(() {
    db = LocalFirstDatabase(NativeDatabase.memory());
    users = DriftLocalStore(
      db,
      collection: 'users',
      serializer: const TestUserSerializer(),
    );
  });
  tearDown(() => db.close());

  test('insert, get, update, delete', () async {
    expect(await users.getById('1'), isNull);

    await users.insert(TestUser(id: '1', name: 'Amodh'));
    expect(await users.getById('1'), TestUser(id: '1', name: 'Amodh'));

    await users.update(TestUser(id: '1', name: 'Renamed'));
    expect(await users.getById('1'), TestUser(id: '1', name: 'Renamed'));
    expect(await users.getAll(), hasLength(1));

    await users.delete('1');
    expect(await users.getById('1'), isNull);
    expect(await users.getAll(), isEmpty);
  });

  test('insert and update both upsert, like InMemoryLocalStore', () async {
    await users.update(TestUser(id: '1', name: 'A'));
    await users.insert(TestUser(id: '1', name: 'B'));
    expect(await users.getAll(), [TestUser(id: '1', name: 'B')]);
  });

  test('getAll keeps insertion order, and an update keeps its place', () async {
    await users.insert(TestUser(id: 'b', name: 'B'));
    await users.insert(TestUser(id: 'a', name: 'A'));
    await users.insert(TestUser(id: 'c', name: 'C'));
    await users.update(TestUser(id: 'b', name: 'B2'));
    expect((await users.getAll()).map((u) => u.id), ['b', 'a', 'c']);
  });

  test('collections sharing a database are isolated', () async {
    final admins = DriftLocalStore<TestUser>(
      db,
      collection: 'admins',
      serializer: const TestUserSerializer(),
    );
    await users.insert(TestUser(id: '1', name: 'User'));
    await admins.insert(TestUser(id: '1', name: 'Admin'));

    expect(await users.getById('1'), TestUser(id: '1', name: 'User'));
    expect(await admins.getById('1'), TestUser(id: '1', name: 'Admin'));
    await admins.delete('1');
    expect(await users.getAll(), hasLength(1));
  });

  test('reassignId leaves only the new id', () async {
    await users.insert(TestUser(id: 'temp_1', name: 'Amodh'));
    await users.reassignId('temp_1', TestUser(id: 'server_1', name: 'Amodh'));

    expect(await users.getById('temp_1'), isNull);
    expect(await users.getAll(), [TestUser(id: 'server_1', name: 'Amodh')]);
  });

  test('watchAll emits immediately, then on every change', () async {
    final emissions = <List<TestUser>>[];
    final sub = users.watchAll().listen(emissions.add);

    await pumpUntil(() => emissions.length == 1);
    expect(emissions.single, isEmpty);

    await users.insert(TestUser(id: '1', name: 'Amodh'));
    await pumpUntil(() => emissions.length == 2);
    expect(emissions.last, [TestUser(id: '1', name: 'Amodh')]);

    await users.delete('1');
    await pumpUntil(() => emissions.length == 3);
    expect(emissions.last, isEmpty);
    await sub.cancel();
  });

  test('watchById follows one record through a reassignment', () async {
    await users.insert(TestUser(id: 'temp_1', name: 'Amodh'));
    final temp = <TestUser?>[];
    final real = <TestUser?>[];
    final subs = [
      users.watchById('temp_1').listen(temp.add),
      users.watchById('server_1').listen(real.add),
    ];
    await pumpUntil(() => temp.isNotEmpty && real.isNotEmpty);
    expect(temp.last, TestUser(id: 'temp_1', name: 'Amodh'));
    expect(real.last, isNull);

    await users.reassignId('temp_1', TestUser(id: 'server_1', name: 'Amodh'));
    await pumpUntil(() => temp.last == null && real.last != null);
    expect(real.last, TestUser(id: 'server_1', name: 'Amodh'));
    for (final sub in subs) {
      await sub.cancel();
    }
  });
}

Future<void> pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition never became true');
}
