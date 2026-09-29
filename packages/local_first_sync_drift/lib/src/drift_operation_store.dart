import 'dart:convert';

import 'package:local_first_sync/local_first_sync.dart';

import 'database.dart';

/// A [SyncOperationStore] over the `local_first_operations` table of a
/// [LocalFirstDatabase]: one row per operation, so each queue change is a
/// single-row write rather than a whole-queue rewrite.
///
/// ```dart
/// final queue = await PersistentSyncQueue.open(DriftOperationStore(db));
/// ```
class DriftOperationStore implements SyncOperationStore {
  DriftOperationStore(this.db);

  final LocalFirstDatabase db;

  $LocalFirstOperationsTable get _table => db.localFirstOperations;

  @override
  Future<List<Map<String, Object?>>> readAll() async {
    final rows = await db.select(_table).get();
    return [
      for (final row in rows) jsonDecode(row.json) as Map<String, Object?>,
    ];
  }

  @override
  Future<void> write(Map<String, Object?> operation) => db
      .into(_table)
      .insertOnConflictUpdate(
        LocalFirstOperationsCompanion.insert(
          operationId: operation['operationId']! as String,
          json: jsonEncode(operation),
        ),
      );

  @override
  Future<void> delete(String operationId) =>
      (db.delete(_table)..where((t) => t.operationId.equals(operationId))).go();

  @override
  Future<void> clear() => db.delete(_table).go();
}
