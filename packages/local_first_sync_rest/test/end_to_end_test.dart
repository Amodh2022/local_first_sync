import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_rest/local_first_sync_rest.dart';
import 'package:test/test.dart';

import 'support/test_models.dart';

/// A tiny REST backend: assigns `srv_N` ids on create, honors
/// `Idempotency-Key`, and can be told to fail the next N requests.
class _FakeServer {
  final rows = <String, Map<String, Object?>>{};
  final _responses = <String, http.Response>{};
  final keys = <String?>[];
  var applied = 0;
  var failNext = 0;
  var _nextId = 1;

  /// Forces a status (with the stored row as body) for matching requests.
  int? Function(http.Request)? statusOverride;

  late final client = MockClient((req) async {
    final key = req.headers['Idempotency-Key'];
    keys.add(key);
    if (failNext > 0) {
      failNext--;
      return http.Response('', 503);
    }
    final override = statusOverride?.call(req);
    if (override != null) {
      return http.Response(
          jsonEncode(rows[req.url.pathSegments.last]), override);
    }
    if (key != null && _responses.containsKey(key)) return _responses[key]!;
    final response = _handle(req);
    if (key != null) _responses[key] = response;
    return response;
  });

  http.Response _handle(http.Request req) {
    applied++;
    final segments = req.url.pathSegments;
    switch (req.method) {
      case 'POST':
        final body = Map<String, Object?>.from(jsonDecode(req.body) as Map);
        final row = {...body, 'id': 'srv_${_nextId++}'};
        rows[row['id']! as String] = row;
        return http.Response(jsonEncode(row), 201);
      case 'PUT':
        final row = Map<String, Object?>.from(jsonDecode(req.body) as Map);
        rows[segments.last] = row;
        return http.Response(jsonEncode(row), 200);
      case 'DELETE':
        return http.Response(
            '', rows.remove(segments.last) == null ? 404 : 204);
    }
    return http.Response('', 405);
  }
}

void main() {
  late _FakeServer server;
  late OfflineSync sync;
  late InMemoryLocalStore<TestUser> local;

  Collection<TestUser> register({ConflictResolver<TestUser>? resolver}) =>
      sync.registerCollection<TestUser>(
        name: 'users',
        localStore: local,
        remoteStore: RestRemoteStore<TestUser>(
          client: server.client,
          collectionUri: Uri.parse('https://api.example.com/users'),
          serializer: const TestUserSerializer(),
        ),
        serializer: const TestUserSerializer(),
        conflictResolver: resolver,
      );

  setUp(() {
    server = _FakeServer();
    local = InMemoryLocalStore<TestUser>();
    sync = OfflineSync(
      config: const SyncConfig(
        retryPolicy: RetryPolicy(
          initialDelay: Duration(milliseconds: 1),
          maxDelay: Duration(milliseconds: 5),
        ),
      ),
    );
  });

  tearDown(() => sync.dispose());

  Future<SyncOperation> op(String id) async =>
      (await sync.inspector().snapshot())
          .operations
          .firstWhere((o) => o.operationId == id);

  Future<void> drain(String opId) async {
    for (var i = 0; i < 20; i++) {
      await sync.syncNow();
      if ((await op(opId)).status == SyncStatus.synced) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a temp-id create syncs and the local row takes the server id',
      () async {
    final users = register();
    final opId = await users.save(TestUser(id: 'temp_1', name: 'Amodh'));
    await sync.syncNow();

    expect((await op(opId)).status, SyncStatus.synced);
    expect(server.rows.keys, ['srv_1']);
    expect(await users.get('temp_1'), isNull);
    expect(await users.get('srv_1'), TestUser(id: 'srv_1', name: 'Amodh'));
  });

  test('retries after 503s carry the same idempotency key', () async {
    final users = register();
    server.failNext = 2;
    final opId = await users.save(TestUser(id: 'temp_1', name: 'Amodh'));
    final key = (await op(opId)).idempotencyKey;

    await drain(opId);

    expect((await op(opId)).status, SyncStatus.synced);
    expect(server.keys, [key, key, key]);
    expect(server.applied, 1);
  });

  test('a 409 is resolved server-wins into the local store', () async {
    final users = register(resolver: const ServerWinsResolver<TestUser>());
    server.rows['1'] = {'id': '1', 'name': 'Server'};
    server.statusOverride = (req) => req.method == 'PUT' ? 409 : null;

    await local.insert(TestUser(id: '1', name: 'Server'));
    final opId = await users.save(TestUser(id: '1', name: 'Local'));
    await sync.syncNow();

    expect((await op(opId)).status, SyncStatus.synced);
    expect(await users.get('1'), TestUser(id: '1', name: 'Server'));
  });

  test('a 422 fails permanently without retrying', () async {
    final users = register();
    server.statusOverride = (_) => 422;
    final opId = await users.save(TestUser(id: '1', name: 'X'));
    await sync.syncNow();

    expect((await op(opId)).status, SyncStatus.failed);
    expect(server.keys, hasLength(1));
  });
}
