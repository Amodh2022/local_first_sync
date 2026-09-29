import '../core/identifiable.dart';
import '../core/sync_errors.dart';
import 'remote_store.dart';

/// A [RemoteStore] backed by a plain [Map], for tests and prototyping. Not
/// a real backend adapter — it never persists anything or talks to a
/// network. Supports injecting latency and failures so retry/backoff,
/// conflict, and temp-id-reassignment behavior can be tested deterministically.
///
/// Like a well-behaved backend, it honors idempotency keys: a repeated key
/// returns the first request's result without applying the write again.
class InMemoryRemoteStore<T extends Identifiable>
    implements PullableRemoteStore<T>, IdempotentRemoteStore<T> {
  InMemoryRemoteStore({
    this.latency = Duration.zero,
    T Function(T item)? assignServerId,
    this.failureInjector,
  }) : _assignServerId = assignServerId;

  final Duration latency;
  final T Function(T item)? _assignServerId;

  /// Called before every operation; return a [SyncFailure] to simulate that
  /// operation failing, or `null` to let it succeed.
  final SyncFailure? Function(String operation, T? item)? failureInjector;

  final _items = <String, T>{};
  final _modifiedAt = <String, DateTime>{};
  final _resultsByKey = <String, Object?>{};

  /// Every idempotency key received, in arrival order — including repeats.
  final List<String> receivedIdempotencyKeys = [];

  /// How many writes were actually applied (repeated keys excluded).
  int appliedWrites = 0;

  Future<void> _maybeFail(String op, T? item) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final failure = failureInjector?.call(op, item);
    if (failure != null) throw failure;
  }

  @override
  Future<T> create(T item) async {
    await _maybeFail('create', item);
    appliedWrites++;
    final stored = _assignServerId != null ? _assignServerId(item) : item;
    _items[stored.id] = stored;
    _modifiedAt[stored.id] = DateTime.now();
    return stored;
  }

  @override
  Future<T> update(T item) async {
    await _maybeFail('update', item);
    appliedWrites++;
    _items[item.id] = item;
    _modifiedAt[item.id] = DateTime.now();
    return item;
  }

  @override
  Future<void> delete(String id) async {
    await _maybeFail('delete', null);
    appliedWrites++;
    _items.remove(id);
    _modifiedAt.remove(id);
  }

  Future<R> _once<R>(String key, Future<R> Function() write) async {
    receivedIdempotencyKeys.add(key);
    if (_resultsByKey.containsKey(key)) return _resultsByKey[key] as R;
    final result = await write();
    _resultsByKey[key] = result;
    return result;
  }

  @override
  Future<T> createWithKey(T item, {required String idempotencyKey}) =>
      _once(idempotencyKey, () => create(item));

  @override
  Future<T> updateWithKey(T item, {required String idempotencyKey}) =>
      _once(idempotencyKey, () => update(item));

  @override
  Future<void> deleteWithKey(String id, {required String idempotencyKey}) =>
      _once(idempotencyKey, () => delete(id));

  @override
  Future<List<T>> fetchChanges({DateTime? since}) async {
    await _maybeFail('fetchChanges', null);
    if (since == null) return _items.values.toList();
    return _items.values.where((item) {
      final modified = _modifiedAt[item.id];
      return modified != null && !modified.isBefore(since);
    }).toList();
  }

  /// Test/demo helper: place a record on the "server" as if another device
  /// had created it, so a pull has something to find.
  void seed(T item, {DateTime? modifiedAt}) {
    _items[item.id] = item;
    _modifiedAt[item.id] = modifiedAt ?? DateTime.now();
  }

  /// Test helper: inspect what the "backend" currently holds without going
  /// through the sync engine.
  T? peek(String id) => _items[id];

  /// Test helper: everything the "backend" currently holds.
  List<T> get all => _items.values.toList();
}
