/// Small key–value persistence for the engine's own bookkeeping, separate
/// from your entities and the operation queue.
///
/// Today it holds each collection's pull cursor (when the last successful
/// pull started), so an app restart resumes with `fetchChanges(since: ...)`
/// instead of re-downloading the whole collection. Keys are namespaced by
/// the engine; treat them as opaque.
///
/// Implement it over whatever the app already has, such as a
/// SharedPreferences instance, a table row, or a file. As with
/// `SyncOperationStore`, [write] must be durable before its `Future`
/// completes.
abstract interface class SyncMetadataStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Non-durable [SyncMetadataStore]: bookkeeping lasts only as long as the
/// process. The default when `OfflineSync` is given no store.
class InMemorySyncMetadataStore implements SyncMetadataStore {
  InMemorySyncMetadataStore([Map<String, String>? initial])
      : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
