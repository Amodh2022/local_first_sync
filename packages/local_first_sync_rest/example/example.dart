import 'package:http/http.dart' as http;
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_rest/local_first_sync_rest.dart';

class Todo implements Identifiable {
  Todo({required this.id, required this.title});

  @override
  final String id;
  final String title;
}

class TodoSerializer implements Serializer<Todo> {
  const TodoSerializer();

  @override
  Map<String, Object?> encode(Todo value) =>
      {'id': value.id, 'title': value.title};

  @override
  Todo decode(Map<String, Object?> data) =>
      Todo(id: data['id']! as String, title: data['title']! as String);
}

Future<String> currentAccessToken() async => 'token';

Future<void> main() async {
  final sync = OfflineSync();

  final todos = sync.registerCollection<Todo>(
    name: 'todos',
    // Use a persistent LocalStore in a real app, e.g. DriftLocalStore from
    // local_first_sync_drift.
    localStore: InMemoryLocalStore<Todo>(),
    remoteStore: PullableRestRemoteStore<Todo>(
      client: http.Client(),
      collectionUri: Uri.parse('https://api.example.com/v1/todos'),
      serializer: const TodoSerializer(),
      // Resolved before every request, so a refreshed token is picked up.
      headers: () async =>
          {'Authorization': 'Bearer ${await currentAccessToken()}'},
    ),
    serializer: const TodoSerializer(),
    conflictResolver: const ServerWinsResolver<Todo>(),
  );

  // Lands locally at once; synced in the background with an Idempotency-Key.
  await todos.save(Todo(id: 'temp_1', title: 'Buy milk'));
  await sync.syncNow();
  await sync.pullNow();

  await sync.dispose();
}
