import 'package:drift/drift.dart';

part 'database.g.dart';

/// Entities of every registered collection, stored as the JSON their
/// `Serializer<T>` produces. One table serves all collections, so adding a
/// collection needs no schema change and no codegen in your app.
@DataClassName('LocalFirstEntityRow')
class LocalFirstEntities extends Table {
  TextColumn get collection => text()();
  TextColumn get id => text()();
  TextColumn get json => text()();

  /// Milliseconds since epoch of the last local write.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {collection, id};
}

/// The sync queue: one row per `SyncOperation`, as `SyncOperation.toJson`.
@DataClassName('LocalFirstOperationRow')
class LocalFirstOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

/// The Drift database behind [DriftLocalStore] and [DriftOperationStore].
///
/// Pass whichever executor fits your platform — `driftDatabase(name: ...)`
/// from `drift_flutter`, `NativeDatabase` from `drift/native.dart`, or a
/// `WasmDatabase` on the web. Keep one instance for the life of the app and
/// share it between every store.
@DriftDatabase(tables: [LocalFirstEntities, LocalFirstOperations])
class LocalFirstDatabase extends _$LocalFirstDatabase {
  LocalFirstDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
