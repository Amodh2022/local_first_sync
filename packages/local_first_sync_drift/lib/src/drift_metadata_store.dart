import 'package:local_first_sync/local_first_sync.dart';

import 'database.dart';

/// A [SyncMetadataStore] over the `local_first_metadata` table of a
/// [LocalFirstDatabase]. With it, pull sync resumes from its saved cursor
/// after an app restart instead of re-downloading every collection.
///
/// ```dart
/// final sync = OfflineSync(
///   queue: await PersistentSyncQueue.open(DriftOperationStore(db)),
///   metadataStore: DriftMetadataStore(db),
/// );
/// ```
class DriftMetadataStore implements SyncMetadataStore {
  DriftMetadataStore(this.db);

  final LocalFirstDatabase db;

  $LocalFirstMetadataTable get _table => db.localFirstMetadata;

  @override
  Future<String?> read(String key) async {
    final row = await (db.select(
      _table,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String key, String value) => db
      .into(_table)
      .insertOnConflictUpdate(
        LocalFirstMetadataCompanion.insert(key: key, value: value),
      );
}
