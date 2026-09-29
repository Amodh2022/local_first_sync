import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_rest/local_first_sync_rest.dart';
import 'package:test/test.dart';

import 'support/test_models.dart';

final _base = Uri.parse('https://api.example.com/v1/users');

RestRemoteStore<TestUser> _store(
  MockClientHandler handler, {
  FutureOr<Map<String, String>> Function()? headers,
  String updateMethod = 'PUT',
}) =>
    RestRemoteStore<TestUser>(
      client: MockClient(handler),
      collectionUri: _base,
      serializer: const TestUserSerializer(),
      headers: headers,
      updateMethod: updateMethod,
    );

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  group('requests', () {
    test('create POSTs the encoded item and decodes the response', () async {
      late http.Request seen;
      final store = _store((req) async {
        seen = req;
        return _json({'id': 'srv_1', 'name': 'Amodh'}, 201);
      });

      final result = await store.create(TestUser(id: 'tmp', name: 'Amodh'));

      expect(seen.method, 'POST');
      expect(seen.url, _base);
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), containsPair('id', 'tmp'));
      expect(seen.headers.containsKey('Idempotency-Key'), isFalse);
      expect(result, TestUser(id: 'srv_1', name: 'Amodh'));
    });

    test('update PUTs to the entity URI, encoding the id segment', () async {
      late http.Request seen;
      final store = _store((req) async {
        seen = req;
        return http.Response('', 204);
      });

      final item = TestUser(id: 'a/b', name: 'X');
      expect(await store.update(item), item);
      expect(seen.method, 'PUT');
      expect(seen.url.toString(), '$_base/a%2Fb');
    });

    test('updateMethod PATCH is honored', () async {
      late http.Request seen;
      final store = _store((req) async {
        seen = req;
        return _json({'id': '1', 'name': 'X'});
      }, updateMethod: 'PATCH');

      await store.update(TestUser(id: '1', name: 'X'));
      expect(seen.method, 'PATCH');
    });

    test('a trailing slash on the collection URI does not double up', () {
      final store = RestRemoteStore<TestUser>(
        client: MockClient((_) async => http.Response('', 204)),
        collectionUri: Uri.parse('https://api.example.com/users/'),
        serializer: const TestUserSerializer(),
      );
      expect(
          store.entityUri('7').toString(), 'https://api.example.com/users/7');
    });

    test('delete sends DELETE and treats 404 as already gone', () async {
      final methods = <String>[];
      final store = _store((req) async {
        methods.add(req.method);
        return http.Response('', 404);
      });
      await store.delete('1');
      expect(methods, ['DELETE']);
    });

    test('*WithKey methods send the idempotency header', () async {
      final keys = <String?>[];
      final store = _store((req) async {
        keys.add(req.headers['Idempotency-Key']);
        return req.method == 'DELETE'
            ? http.Response('', 204)
            : _json({'id': '1', 'name': 'X'});
      });
      final item = TestUser(id: '1', name: 'X');
      await store.createWithKey(item, idempotencyKey: 'k1');
      await store.updateWithKey(item, idempotencyKey: 'k2');
      await store.deleteWithKey('1', idempotencyKey: 'k3');
      expect(keys, ['k1', 'k2', 'k3']);
    });

    test('the headers callback runs before every request', () async {
      var calls = 0;
      final auth = <String?>[];
      final store = _store(
        (req) async {
          auth.add(req.headers['Authorization']);
          return _json({'id': '1', 'name': 'X'});
        },
        headers: () async => {'Authorization': 'Bearer t${++calls}'},
      );
      final item = TestUser(id: '1', name: 'X');
      await store.create(item);
      await store.update(item);
      expect(auth, ['Bearer t1', 'Bearer t2']);
    });
  });

  group('failure mapping', () {
    Future<SyncFailure> failureFor(int status, {Object? body}) async {
      final store = _store((_) async =>
          http.Response(body == null ? '' : jsonEncode(body), status));
      try {
        await store.create(TestUser(id: '1', name: 'X'));
      } on SyncFailure catch (e) {
        return e;
      }
      fail('expected a SyncFailure for HTTP $status');
    }

    for (final (status, type, retryable) in [
      (400, ValidationFailure, false),
      (401, AuthFailure, false),
      (403, AuthFailure, false),
      (408, NetworkFailure, true),
      (422, ValidationFailure, false),
      (429, NetworkFailure, true),
      (500, ServerFailure, true),
      (503, ServerFailure, true),
      (404, ServerFailure, false),
      (418, ServerFailure, false),
    ]) {
      test('HTTP $status -> $type (retryable: $retryable)', () async {
        final failure = await failureFor(status);
        expect(failure.runtimeType, type);
        expect(failure.retryable, retryable);
      });
    }

    test('409 and 412 carry the decoded server copy as remoteValue', () async {
      for (final status in [409, 412]) {
        final failure =
            await failureFor(status, body: {'id': '1', 'name': 'Server'});
        expect(failure, isA<ConflictFailure>());
        expect((failure as ConflictFailure).remoteValue,
            {'id': '1', 'name': 'Server'});
      }
    });

    test('a conflict with a non-object body has a null remoteValue', () async {
      final failure = await failureFor(409, body: ['nope']);
      expect((failure as ConflictFailure).remoteValue, isNull);
    });

    test('Retry-After on 429 and 503 becomes retryAfter', () async {
      for (final status in [429, 503]) {
        final store = _store((_) async =>
            http.Response('', status, headers: {'retry-after': '120'}));
        await expectLater(
          store.create(TestUser(id: '1', name: 'A')),
          throwsA(isA<SyncFailure>()
              .having((f) => f.retryable, 'retryable', isTrue)
              .having((f) => f.retryAfter, 'retryAfter',
                  const Duration(seconds: 120))),
        );
      }
    });

    test('parseRetryAfter handles seconds, dates and junk', () {
      final now = DateTime.utc(2026, 10, 21, 7, 28, 0);
      expect(
          RestRemoteStore.parseRetryAfter('30'), const Duration(seconds: 30));
      expect(
          RestRemoteStore.parseRetryAfter('Wed, 21 Oct 2026 07:30:00 GMT',
              now: now),
          const Duration(minutes: 2));
      expect(
          RestRemoteStore.parseRetryAfter('Wed, 21 Oct 2026 07:00:00 GMT',
              now: now),
          Duration.zero);
      expect(RestRemoteStore.parseRetryAfter('soon'), isNull);
      expect(RestRemoteStore.parseRetryAfter('-5'), isNull);
      expect(RestRemoteStore.parseRetryAfter(null), isNull);
    });

    test('ClientException -> NetworkFailure', () async {
      final store =
          _store((_) async => throw http.ClientException('connection reset'));
      await expectLater(store.create(TestUser(id: '1', name: 'X')),
          throwsA(isA<NetworkFailure>()));
    });

    test('TimeoutException -> TimeoutFailure', () async {
      final store = _store((_) async => throw TimeoutException('slow'));
      await expectLater(store.create(TestUser(id: '1', name: 'X')),
          throwsA(isA<TimeoutFailure>()));
    });

    test('an undecodable 2xx body -> UnknownFailure (permanent)', () async {
      final store = _store((_) async => http.Response('<html>', 200));
      await expectLater(store.create(TestUser(id: '1', name: 'X')),
          throwsA(isA<UnknownFailure>()));
    });

    test('mapFailure can be overridden', () async {
      final store = _NoRetry503Store((_) async => http.Response('', 503));
      await expectLater(store.create(TestUser(id: '1', name: 'X')),
          throwsA(isA<ValidationFailure>()));
    });
  });

  group('pull', () {
    test('first pull has no since param; later pulls send it in UTC', () async {
      final urls = <Uri>[];
      final store = PullableRestRemoteStore<TestUser>(
        client: MockClient((req) async {
          urls.add(req.url);
          return _json([
            {'id': '1', 'name': 'A'},
          ]);
        }),
        collectionUri: _base.replace(queryParameters: {'team': '9'}),
        serializer: const TestUserSerializer(),
      );

      expect(await store.fetchChanges(), [TestUser(id: '1', name: 'A')]);
      final since = DateTime.utc(2026, 9, 1, 12);
      await store.fetchChanges(since: since.toLocal());

      expect(urls[0].queryParameters, {'team': '9'});
      expect(urls[1].queryParameters,
          {'team': '9', 'since': '2026-09-01T12:00:00.000Z'});
    });

    test('decodeList unwraps an envelope and sinceParam is configurable',
        () async {
      late Uri seen;
      final store = PullableRestRemoteStore<TestUser>(
        client: MockClient((req) async {
          seen = req.url;
          return _json({
            'data': [
              {'id': '2', 'name': 'B'},
            ],
          });
        }),
        collectionUri: _base,
        serializer: const TestUserSerializer(),
        sinceParam: 'updated_after',
        decodeList: (body) => (body! as Map)['data'] as List<Object?>,
      );

      final items = await store.fetchChanges(since: DateTime.utc(2026, 1, 1));
      expect(items, [TestUser(id: '2', name: 'B')]);
      expect(seen.queryParameters.keys, ['updated_after']);
    });

    test('a pull failure is mapped like a write failure', () async {
      final store = PullableRestRemoteStore<TestUser>(
        client: MockClient((_) async => http.Response('', 401)),
        collectionUri: _base,
        serializer: const TestUserSerializer(),
      );
      await expectLater(store.fetchChanges(), throwsA(isA<AuthFailure>()));
    });
  });
}

class _NoRetry503Store extends RestRemoteStore<TestUser> {
  _NoRetry503Store(MockClientHandler handler)
      : super(
          client: MockClient(handler),
          collectionUri: _base,
          serializer: const TestUserSerializer(),
        );

  @override
  SyncFailure mapFailure(http.Response response) => response.statusCode == 503
      ? const ValidationFailure('maintenance')
      : super.mapFailure(response);
}
