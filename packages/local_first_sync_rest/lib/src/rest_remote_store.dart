import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:local_first_sync/local_first_sync.dart';

/// A [RemoteStore] for a JSON REST collection endpoint.
///
/// Given `collectionUri` `https://api.example.com/todos`:
///
/// | Operation | Request                                  |
/// |-----------|------------------------------------------|
/// | create    | `POST   /todos`                          |
/// | update    | `PUT    /todos/{id}` (or [updateMethod]) |
/// | delete    | `DELETE /todos/{id}`                     |
///
/// Bodies are `serializer.encode(item)` as JSON; create/update responses are
/// decoded with `serializer.decode`, so a server-assigned id on create flows
/// into the engine's temporary-id rewriting. An empty 2xx body means "the
/// server accepted what was sent", and the sent item is returned as-is.
///
/// Every failure is thrown as a [SyncFailure] — see [mapFailure] for the
/// status-code mapping. Transport errors become [NetworkFailure] (or
/// [TimeoutFailure]); a 2xx body that isn't valid JSON for the serializer
/// becomes [UnknownFailure] — permanent, since retrying won't change what the
/// server sends back.
///
/// The engine calls the `*WithKey` methods, which add
/// `idempotencyHeader: <operation's idempotencyKey>` so the backend can
/// deduplicate a write re-sent after a retry or crash. The plain
/// [create]/[update]/[delete] send no such header.
class RestRemoteStore<T extends Identifiable>
    implements IdempotentRemoteStore<T> {
  RestRemoteStore({
    required this.client,
    required this.collectionUri,
    required this.serializer,
    this.headers,
    this.idempotencyHeader = 'Idempotency-Key',
    this.updateMethod = 'PUT',
  });

  final http.Client client;

  /// The collection endpoint, e.g. `https://api.example.com/v1/todos`.
  final Uri collectionUri;

  final Serializer<T> serializer;

  /// Extra headers, resolved before every request — return a fresh bearer
  /// token here and a refreshed token is picked up on the next attempt.
  final FutureOr<Map<String, String>> Function()? headers;

  /// Header that carries the operation's idempotency key.
  final String idempotencyHeader;

  /// HTTP method for updates: `PUT` (default) or `PATCH`.
  final String updateMethod;

  @override
  Future<T> create(T item) => _write('POST', collectionUri, item, null);

  @override
  Future<T> createWithKey(T item, {required String idempotencyKey}) =>
      _write('POST', collectionUri, item, idempotencyKey);

  @override
  Future<T> update(T item) =>
      _write(updateMethod, entityUri(item.id), item, null);

  @override
  Future<T> updateWithKey(T item, {required String idempotencyKey}) =>
      _write(updateMethod, entityUri(item.id), item, idempotencyKey);

  @override
  Future<void> delete(String id) => _delete(id, null);

  @override
  Future<void> deleteWithKey(String id, {required String idempotencyKey}) =>
      _delete(id, idempotencyKey);

  /// The URI for a single entity: [collectionUri] plus one path segment.
  Uri entityUri(String id) => collectionUri.replace(
        pathSegments: [
          ...collectionUri.pathSegments.where((s) => s.isNotEmpty),
          id,
        ],
      );

  /// Translates a non-2xx [response] into the [SyncFailure] the engine acts
  /// on. Override it for a backend with its own conventions, e.g. one that
  /// signals rate limiting with a 503 you would rather not retry. Only
  /// non-2xx responses reach it.
  ///
  /// | Status     | Failure              | Retried? |
  /// |------------|----------------------|----------|
  /// | 401, 403   | [AuthFailure]        | no       |
  /// | 409, 412   | [ConflictFailure]    | resolved |
  /// | 400, 422   | [ValidationFailure]  | no       |
  /// | 408, 429   | [NetworkFailure]     | yes      |
  /// | 5xx        | [ServerFailure]      | yes      |
  /// | other      | [ServerFailure]      | no       |
  ///
  /// A conflict's `remoteValue` is the response body decoded as a JSON
  /// object — the encoded server copy a [ConflictResolver] needs — or `null`
  /// when the body isn't one.
  SyncFailure mapFailure(http.Response response) {
    final code = response.statusCode;
    final message = 'HTTP $code from ${response.request?.method ?? ''} '
            '${response.request?.url ?? collectionUri}'
        .trim();
    switch (code) {
      case 401:
      case 403:
        return AuthFailure(message);
      case 409:
      case 412:
        return ConflictFailure(message,
            remoteValue: _tryDecodeObject(response));
      case 400:
      case 422:
        return ValidationFailure(message);
      case 408:
      case 429:
        return NetworkFailure(message);
      default:
        return ServerFailure(code, message);
    }
  }

  Future<T> _write(String method, Uri uri, T item, String? key) async {
    final response = await send(
      method,
      uri,
      body: jsonEncode(serializer.encode(item)),
      idempotencyKey: key,
    );
    if (response.body.trim().isEmpty) return item;
    try {
      final decoded = jsonDecode(response.body);
      return serializer.decode(Map<String, Object?>.from(decoded as Map));
    } catch (e) {
      throw UnknownFailure(
          'Could not decode $method $uri response as ${T.toString()}: $e');
    }
  }

  Future<void> _delete(String id, String? key) async {
    await send('DELETE', entityUri(id),
        idempotencyKey: key, acceptNotFound: true);
  }

  /// Sends one request and returns the response if it is a success; throws
  /// the [mapFailure] result otherwise. Transport errors are mapped to
  /// [NetworkFailure]/[TimeoutFailure]. Exposed so subclasses can add
  /// endpoints with the same error handling.
  Future<http.Response> send(
    String method,
    Uri uri, {
    String? body,
    String? idempotencyKey,
    bool acceptNotFound = false,
  }) async {
    final http.Response response;
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
          ...?(await headers?.call()),
          if (idempotencyKey != null) idempotencyHeader: idempotencyKey,
        });
      if (body != null) request.body = body;
      response = await http.Response.fromStream(await client.send(request));
    } on SyncFailure {
      rethrow;
    } on TimeoutException catch (e) {
      throw TimeoutFailure('$method $uri timed out: ${e.message ?? e}');
    } on http.ClientException catch (e) {
      throw NetworkFailure('$method $uri failed: ${e.message}');
    }
    final code = response.statusCode;
    if (code >= 200 && code < 300) return response;
    if (acceptNotFound && code == 404) return response;
    throw mapFailure(response);
  }

  static Map<String, Object?>? _tryDecodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }
}

/// A [RestRemoteStore] that also supports pull sync: `GET collectionUri`,
/// with `?since=<ISO-8601 UTC>` after the first successful pull.
///
/// A separate class so that pulling is opt-in — the engine only pulls from
/// collections whose remote store implements [PullableRemoteStore].
class PullableRestRemoteStore<T extends Identifiable> extends RestRemoteStore<T>
    implements PullableRemoteStore<T> {
  PullableRestRemoteStore({
    required super.client,
    required super.collectionUri,
    required super.serializer,
    super.headers,
    super.idempotencyHeader,
    super.updateMethod,
    this.sinceParam = 'since',
    this.decodeList,
  });

  /// Query parameter that carries the previous pull's timestamp.
  final String sinceParam;

  /// Extracts the list of records from the decoded response body, for
  /// envelope formats like `{"data": [...]}`. Defaults to expecting a bare
  /// JSON array.
  final List<Object?> Function(Object? decodedBody)? decodeList;

  @override
  Future<List<T>> fetchChanges({DateTime? since}) async {
    final uri = since == null
        ? collectionUri
        : collectionUri.replace(queryParameters: {
            ...collectionUri.queryParametersAll,
            sinceParam: since.toUtc().toIso8601String(),
          });
    final response = await send('GET', uri);
    try {
      final decoded = jsonDecode(response.body);
      final list = decodeList != null ? decodeList!(decoded) : decoded as List;
      return [
        for (final row in list)
          serializer.decode(Map<String, Object?>.from(row! as Map)),
      ];
    } catch (e) {
      throw UnknownFailure('Could not decode GET $uri response: $e');
    }
  }
}
