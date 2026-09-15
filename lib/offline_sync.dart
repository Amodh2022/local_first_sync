/// A production-quality, state-management-agnostic offline-first
/// synchronization framework for Flutter/Dart.
///
/// See `DESIGN.md` for the architecture this package implements, and
/// `.claude/agents/package_create.md` for the governing product/engineering
/// spec.
library;

export 'src/conflict/conflict_resolver.dart';
export 'src/connectivity/connectivity_monitor.dart';
export 'src/core/identifiable.dart';
export 'src/core/retry_policy.dart';
export 'src/core/sync_errors.dart';
export 'src/core/sync_events.dart';
export 'src/core/sync_operation.dart' show SyncOperation, SyncOperationType;
export 'src/core/sync_status.dart';
export 'src/dependency/dependency_graph.dart';
export 'src/dependency/temp_id_registry.dart';
export 'src/inspector/sync_inspector.dart';
export 'src/offline_sync_facade.dart';
export 'src/queue/in_memory_sync_queue.dart';
export 'src/queue/operation_coalescer.dart';
export 'src/queue/persistent_sync_queue.dart';
export 'src/queue/sync_operation_store.dart';
export 'src/queue/sync_queue.dart';
export 'src/remote/in_memory_remote_store.dart';
export 'src/remote/remote_store.dart';
export 'src/repository/collection.dart';
export 'src/serialization/serializer.dart';
export 'src/storage/in_memory_local_store.dart';
export 'src/storage/local_store.dart';
export 'src/sync/collection_binding.dart';
export 'src/sync/sync_config.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_state.dart';
export 'src/sync/typed_collection_binding.dart';
