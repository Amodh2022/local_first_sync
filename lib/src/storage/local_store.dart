import '../core/identifiable.dart';

/// Database-independent local persistence for entities of type [T].
/// Concrete adapters (Drift, Isar, ...) implement this;
/// [Collection] and [SyncEngine] never assume a specific database.
abstract interface class LocalStore<T extends Identifiable> {
  Future<T?> getById(String id);

  Future<List<T>> getAll();

  Future<void> insert(T item);

  Future<void> update(T item);

  Future<void> delete(String id);

  /// Replaces the record stored under [oldId] with [newItem], which may have
  /// a different id. Used when a server assigns a permanent id to a record
  /// that was created under a temporary id (DESIGN.md §6).
  ///
  /// Implementations that can't do this atomically may implement it as
  /// delete-then-insert; either way it must never leave both [oldId] and
  /// `newItem.id` present at once.
  Future<void> reassignId(String oldId, T newItem);

  /// Emits the current snapshot immediately on listen, then again whenever
  /// the collection changes.
  Stream<List<T>> watchAll();

  Stream<T?> watchById(String id);
}
