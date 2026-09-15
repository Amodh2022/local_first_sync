import 'package:test/test.dart';
import 'package:offline_sync/offline_sync.dart';

SyncOperation _op(
  String id, {
  List<String> deps = const [],
  SyncStatus status = SyncStatus.ready,
  String? lastError,
}) {
  final now = DateTime.now();
  return SyncOperation(
    operationId: id,
    idempotencyKey: id,
    collection: 'orders',
    entityId: id,
    type: SyncOperationType.create,
    payload: const {},
    createdAt: now,
    updatedAt: now,
    dependencyIds: deps,
    status: status,
    lastError: lastError,
  );
}

void main() {
  group('wouldCreateCycle', () {
    test('false for an empty dependency list', () {
      expect(DependencyGraph.wouldCreateCycle([], _op('a')), isFalse);
    });

    test('true for a self-dependency', () {
      expect(
          DependencyGraph.wouldCreateCycle([], _op('a', deps: ['a'])), isTrue);
    });

    test('true for a->b->a', () {
      final existing = [
        _op('a', deps: ['b'])
      ];
      expect(DependencyGraph.wouldCreateCycle(existing, _op('b', deps: ['a'])),
          isTrue);
    });

    test('false for a valid chain a->b->c', () {
      final existing = [
        _op('a'),
        _op('b', deps: ['a'])
      ];
      expect(DependencyGraph.wouldCreateCycle(existing, _op('c', deps: ['b'])),
          isFalse);
    });
  });

  group('blockedReasons', () {
    test('an operation with an unsynced dependency is blocked', () {
      final all = [
        _op('order', status: SyncStatus.failed, lastError: 'HTTP 500'),
        _op('item', deps: ['order'], status: SyncStatus.blocked),
      ];
      final reasons = DependencyGraph.blockedReasons(all);
      expect(reasons, contains('item'));
      expect(reasons['item'], contains('order'));
      expect(reasons['item'], contains('HTTP 500'));
      expect(reasons, isNot(contains('order')));
    });

    test('an operation whose dependency synced is not blocked', () {
      final all = [
        _op('order', status: SyncStatus.synced),
        _op('item', deps: ['order'], status: SyncStatus.ready),
      ];
      expect(DependencyGraph.blockedReasons(all), isEmpty);
    });
  });
}
