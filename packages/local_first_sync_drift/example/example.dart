// Run with: dart run example/example.dart
import 'package:drift/native.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_drift/local_first_sync_drift.dart';

class Todo implements Identifiable {
  Todo({required this.id, required this.title});

  @override
  final String id;
  final String title;
}

class TodoSerializer implements Serializer<Todo> {
  const TodoSerializer();

  @override
  Map<String, Object?> encode(Todo value) => {
    'id': value.id,
    'title': value.title,
  };

  @override
  Todo decode(Map<String, Object?> data) =>
      Todo(id: data['id']! as String, title: data['title']! as String);
}

Future<void> main() async {
  // In a Flutter app: LocalFirstDatabase(driftDatabase(name: 'app')) from
  // package:drift_flutter. In-memory here so the example leaves no files.
  final db = LocalFirstDatabase(NativeDatabase.memory());

  final sync = OfflineSync(
    queue: await PersistentSyncQueue.open(DriftOperationStore(db)),
  );
  final todos = sync.registerCollection<Todo>(
    name: 'todos',
    localStore: DriftLocalStore(
      db,
      collection: 'todos',
      serializer: const TodoSerializer(),
    ),
    // Replace with your real backend, e.g. RestRemoteStore from
    // package:local_first_sync_rest.
    remoteStore: InMemoryRemoteStore<Todo>(),
    serializer: const TodoSerializer(),
  );

  await todos.save(Todo(id: '1', title: 'Buy milk'));
  print('Stored locally: ${(await todos.getAll()).map((t) => t.title)}');

  await sync.syncNow();
  final snapshot = await sync.inspector().snapshot();
  print('Queue: ${snapshot.operations.map((o) => o.status.name)}');

  await sync.dispose();
  await db.close();
}
