import 'conflict/conflict_resolver.dart';
import 'connectivity/connectivity_monitor.dart';
import 'core/identifiable.dart';
import 'core/sync_events.dart';
import 'inspector/sync_inspector.dart';
import 'queue/in_memory_sync_queue.dart';
import 'queue/sync_queue.dart';
import 'remote/remote_store.dart';
import 'repository/collection.dart';
import 'serialization/serializer.dart';
import 'storage/local_store.dart';
import 'sync/sync_config.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_state.dart';
import 'sync/typed_collection_binding.dart';

/// The top-level entry point most apps construct once and keep around
/// (typically injected into whichever state-management setup the app
/// already uses — this class has no opinion about that).
///
/// ```dart
/// final sync = OfflineSync();
/// final users = sync.registerCollection<User>(
///   name: 'users',
///   localStore: DriftUserStore(db),
///   remoteStore: RestUserStore(client),
///   serializer: UserSerializer(),
/// );
/// sync.start();
/// ```
class OfflineSync {
  OfflineSync({
    SyncConfig config = const SyncConfig(),
    SyncQueue? queue,
    ConnectivityMonitor? connectivity,
  })  : _queue = queue ?? InMemorySyncQueue(),
        _connectivity = connectivity ?? ManualConnectivityMonitor() {
    _config = config;
    _engine =
        SyncEngine(queue: _queue, connectivity: _connectivity, config: config);
  }

  final SyncQueue _queue;
  final ConnectivityMonitor _connectivity;
  late final SyncEngine _engine;
  late final SyncConfig _config;
  final _collections = <String, Collection<Identifiable>>{};

  ConnectivityMonitor get connectivity => _connectivity;

  Stream<SyncEvent> get events => _engine.events;

  /// The queue this instance drains. Exposed so an app can build its own
  /// diagnostics on top; prefer [inspector] and [watchState] for anything
  /// read-only.
  SyncQueue get queue => _queue;

  /// A one-object summary for a status bar or badge: online/offline,
  /// whether a drain is in flight, unsynced counts, and when everything was
  /// last fully synced.
  Future<SyncState> state() => _engine.currentState();

  /// [state] as a stream, emitting immediately and on every change.
  ///
  /// ```dart
  /// StreamBuilder<SyncState>(
  ///   stream: sync.watchState(),
  ///   builder: (_, snap) => Text('${snap.data?.unsynced ?? 0} unsynced'),
  /// );
  /// ```
  Stream<SyncState> watchState() => _engine.watchState();

  /// Whether syncing is currently suspended — see [pause].
  bool get isPaused => _engine.isPaused;

  SyncInspector inspector({Set<String> redactedFields = const {}}) =>
      SyncInspector(
          queue: _queue,
          connectivity: _connectivity,
          redactedFields: redactedFields);

  /// Wires a [Collection] up to local + remote storage and registers it with
  /// the sync engine, returning the [Collection] apps read/write through.
  Collection<T> registerCollection<T extends Identifiable>({
    required String name,
    required LocalStore<T> localStore,
    required RemoteStore<T> remoteStore,
    required Serializer<T> serializer,
    List<String> referenceFields = const [],
    ConflictResolver<T>? conflictResolver,
  }) {
    final collection = Collection<T>(
      name: name,
      localStore: localStore,
      queue: _queue,
      serializer: serializer,
      coalesceOperations: _config.coalesceOperations,
    );
    _collections[name] = collection as Collection<Identifiable>;
    _engine.registerCollection(TypedCollectionBinding<T>(
      name: name,
      localStore: localStore,
      remoteStore: remoteStore,
      serializer: serializer,
      referenceFields: referenceFields,
      conflictResolver: conflictResolver,
    ));
    return collection;
  }

  /// Looks up a previously [registerCollection]-ed collection by name.
  Collection<T> collection<T extends Identifiable>(String name) {
    final found = _collections[name];
    if (found == null) {
      throw StateError(
        'No collection registered with name "$name". Call registerCollection first.',
      );
    }
    return found as Collection<T>;
  }

  /// Starts reacting to connectivity changes *and* queue changes (so a
  /// `Collection.save`/`delete` made while already online syncs on its own),
  /// and runs an initial sync pass. See [SyncEngine.start].
  void start() => _engine.start();

  /// Triggers an immediate sync pass. Rarely needed once [start] has been
  /// called — mainly useful for an explicit "sync now" UI affordance, or to
  /// drive syncing yourself without calling [start] at all.
  Future<void> syncNow() => _engine.syncNow();

  /// Fetches remote changes into local storage for collections whose
  /// [RemoteStore] implements [PullableRemoteStore]. Local writes that
  /// haven't synced yet are never overwritten. See [SyncEngine.pullNow].
  Future<int> pullNow({String? collection}) =>
      _engine.pullNow(collection: collection);

  /// Suspends syncing without discarding anything — writes keep queuing.
  /// The canonical use is an [AuthFailure]: pause, refresh the token,
  /// [resume].
  void pause() => _engine.pause();

  void resume() => _engine.resume();

  /// Requeues a failed (or cancelled) operation immediately, clearing its
  /// error and backoff — the "Retry" button in a sync UI.
  Future<void> retryOperation(String operationId) =>
      _engine.retryOperation(operationId);

  /// [retryOperation] for every permanently failed operation; returns how
  /// many were requeued.
  Future<int> retryAllFailed() => _engine.retryAllFailed();

  /// Abandons an operation. Its dependents are blocked with an explicit
  /// reason rather than silently dropped.
  Future<void> cancelOperation(String operationId) =>
      _engine.cancelOperation(operationId);

  /// Removes completed operations from the queue. Runs automatically after
  /// each drain per [SyncConfig.retainSyncedOperations]; call it directly to
  /// purge sooner. Returns how many were removed.
  Future<int> purgeCompleted({Duration? olderThan}) =>
      _engine.purgeCompleted(olderThan: olderThan);

  Future<void> dispose() => _engine.dispose();
}
