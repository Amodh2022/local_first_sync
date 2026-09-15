import 'dart:async';

import '../core/sync_operation.dart';
import '../dependency/dependency_graph.dart';
import 'sync_queue.dart';

class InMemorySyncQueue implements SyncQueue {
  final _ops = <String, SyncOperation>{};
  final _changes = StreamController<List<SyncOperation>>.broadcast();

  List<SyncOperation> _snapshot() => _ops.values.toList(growable: false);

  void _emit() => _changes.add(_snapshot());

  @override
  Future<void> enqueue(SyncOperation operation) async {
    if (DependencyGraph.wouldCreateCycle(_ops.values, operation)) {
      throw CyclicDependencyException(
        'Enqueuing ${operation.operationId} would create a circular '
        'dependency.',
      );
    }
    _ops[operation.operationId] = operation;
    _emit();
  }

  @override
  Future<SyncOperation?> getOperation(String operationId) async =>
      _ops[operationId];

  @override
  Future<List<SyncOperation>> all() async => _snapshot();

  @override
  Future<List<SyncOperation>> dependentsOf(String operationId) async =>
      _snapshot().where((op) => op.dependencyIds.contains(operationId)).toList();

  @override
  Future<void> updateOperation(SyncOperation operation) async {
    _ops[operation.operationId] = operation;
    _emit();
  }

  @override
  Future<void> removeOperation(String operationId) async {
    _ops.remove(operationId);
    _emit();
  }

  @override
  Stream<List<SyncOperation>> watchAll() => Stream.multi((controller) {
        controller.add(_snapshot());
        final sub =
            _changes.stream.listen(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });
}
