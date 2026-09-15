import '../core/identifiable.dart';
import '../core/sync_errors.dart';
import 'remote_store.dart';

/// A [RemoteStore] backed by a plain [Map], for tests and prototyping. Not
/// a real backend adapter — it never persists anything or talks to a
/// network. Supports injecting latency and failures so retry/backoff,
/// conflict, and temp-id-reassignment behavior can be tested deterministically.
class InMemoryRemoteStore<T extends Identifiable>
    implements PullableRemoteStore<T> {
  InMemoryRemoteStore({
    this.latency = Duration.zero,
    this._assignServerId,
    this.failureInjector,
  });

  final Duration latency;
  final T Function(T item)? _assignServerId;

  /// Called before every operation; return a [SyncFailure] to simulate that
  /// operation failing, or `null` to let it succeed.
  final SyncFailure? Function(String operation, T? item)? failureInjector;

  final _items = <String, T>{};
  final _modifiedAt = <String, DateTime>{};

  Future<void> _maybeFail(String op, T? item) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final failure = failureInjector?.call(op, item);
    if (failure != null) throw failure;
  }

  @override
  Future<T> create(T item) async {
    await _maybeFail('create', item);
    final stored = _assignServerId != null ? _assignServerId(item) : item;
    _items[stored.id] = stored;
    _modifiedAt[stored.id] = DateTime.now();
    return stored;
  }

  @override
  Future<T> update(T item) async {
    await _maybeFail('update', item);
    _items[item.id] = item;
    _modifiedAt[item.id] = DateTime.now();
    return item;
  }

  @override
  Future<void> delete(String id) async {
    await _maybeFail('delete', null);
    _items.remove(id);
    _modifiedAt.remove(id);
  }

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
