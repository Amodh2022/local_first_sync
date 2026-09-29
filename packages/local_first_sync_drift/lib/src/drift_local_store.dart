import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:local_first_sync/local_first_sync.dart';

import 'database.dart';

/// A persistent [LocalStore] for one collection, backed by the shared
/// `local_first_entities` table of a [LocalFirstDatabase].
///
/// Records are stored as `jsonEncode(serializer.encode(item))`, so the same
/// [Serializer] you register with `OfflineSync` is all this store needs. The
/// trade-off: fields are not columns, so you can't filter by them in SQL —
/// load with [getAll]/[watchAll] and filter in Dart, or keep your own typed
/// table for query-heavy data.
///
/// [insert] and [update] both upsert, matching [InMemoryLocalStore]. Reads
/// come back in insertion order.
class DriftLocalStore<T extends Identifiable> implements LocalStore<T> {
  DriftLocalStore(
    this.db, {
    required this.collection,
    required this.serializer,
  });

  final LocalFirstDatabase db;

  /// The collection name rows are stored under. Usually the same name you
  /// pass to `OfflineSync.registerCollection`.
  final String collection;

  final Serializer<T> serializer;

  $LocalFirstEntitiesTable get _table => db.localFirstEntities;

  T _decode(LocalFirstEntityRow row) =>
      serializer.decode(jsonDecode(row.json) as Map<String, Object?>);

  LocalFirstEntitiesCompanion _companion(T item) =>
      LocalFirstEntitiesCompanion.insert(
        collection: collection,
        id: item.id,
        json: jsonEncode(serializer.encode(item)),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  SimpleSelectStatement<$LocalFirstEntitiesTable, LocalFirstEntityRow> _all() =>
      db.select(_table)
        ..where((t) => t.collection.equals(collection))
        ..orderBy([(t) => OrderingTerm.asc(t.rowId)]);

  SimpleSelectStatement<$LocalFirstEntitiesTable, LocalFirstEntityRow> _byId(
    String id,
  ) =>
      db.select(_table)
        ..where((t) => t.collection.equals(collection) & t.id.equals(id));

  Future<void> _upsert(T item) =>
      db.into(_table).insertOnConflictUpdate(_companion(item));

  Future<int> _delete(String id) => (db.delete(
    _table,
  )..where((t) => t.collection.equals(collection) & t.id.equals(id))).go();

  @override
  Future<T?> getById(String id) async {
    final row = await _byId(id).getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  @override
  Future<List<T>> getAll() async => (await _all().get()).map(_decode).toList();

  @override
  Future<void> insert(T item) => _upsert(item);

  @override
  Future<void> update(T item) => _upsert(item);

  @override
  Future<void> delete(String id) => _delete(id);

  @override
  Future<void> reassignId(String oldId, T newItem) => db.transaction(() async {
    await _delete(oldId);
    await _delete(newItem.id);
    await db.into(_table).insert(_companion(newItem));
  });

  @override
  Stream<List<T>> watchAll() =>
      _all().watch().map((rows) => rows.map(_decode).toList());

  @override
  Stream<T?> watchById(String id) => _byId(
    id,
  ).watchSingleOrNull().map((row) => row == null ? null : _decode(row));
}
