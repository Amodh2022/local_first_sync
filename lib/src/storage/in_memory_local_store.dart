import 'dart:async';

import '../core/identifiable.dart';
import 'local_store.dart';

/// A [LocalStore] backed by a plain [Map]. Useful for prototyping, tests, and
/// as the reference implementation while a real database adapter
/// (`local_first_sync_drift`, etc.) is being built — it holds no data across
/// process restarts, so it must not be used for anything that needs real
/// crash recovery — use [PersistentSyncQueue] with a durable
/// [SyncOperationStore] and a real [LocalStore] adapter for that.
class InMemoryLocalStore<T extends Identifiable> implements LocalStore<T> {
  final _items = <String, T>{};
  final _changes = StreamController<List<T>>.broadcast();

  List<T> _snapshot() => _items.values.toList(growable: false);

  void _emit() => _changes.add(_snapshot());

  @override
  Future<T?> getById(String id) async => _items[id];

  @override
  Future<List<T>> getAll() async => _snapshot();

  @override
  Future<void> insert(T item) async {
    _items[item.id] = item;
    _emit();
  }

  @override
  Future<void> update(T item) async {
    _items[item.id] = item;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
    _emit();
  }

  @override
  Future<void> reassignId(String oldId, T newItem) async {
    _items.remove(oldId);
    _items[newItem.id] = newItem;
    _emit();
  }

  @override
  Stream<List<T>> watchAll() => Stream.multi((controller) {
        controller.add(_snapshot());
        final sub = _changes.stream
            .listen(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  @override
  Stream<T?> watchById(String id) => watchAll().map((items) {
        for (final item in items) {
          if (item.id == id) return item;
        }
        return null;
      });

  Future<void> dispose() => _changes.close();
}
