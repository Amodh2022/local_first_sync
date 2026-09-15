import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/offline_sync.dart';

import '../support/test_models.dart';

ConflictContext _ctx(SyncOperation op) =>
    ConflictContext(collection: 'users', entityId: op.entityId, operation: op);

SyncOperation _op() {
  final now = DateTime.now();
  return SyncOperation(
    operationId: 'op1',
    idempotencyKey: 'op1',
    collection: 'users',
    entityId: '1',
    type: SyncOperationType.update,
    payload: const {},
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final local = TestUser(id: '1', name: 'Local Name');
  final remote = TestUser(id: '1', name: 'Remote Name');

  test('ServerWinsResolver picks remote', () {
    final result = const ServerWinsResolver<TestUser>().resolve(local, remote, _ctx(_op()));
    expect(result.value, remote);
    expect(result.origin, ConflictOrigin.remote);
  });

  test('ClientWinsResolver picks local', () {
    final result = const ClientWinsResolver<TestUser>().resolve(local, remote, _ctx(_op()));
    expect(result.value, local);
    expect(result.origin, ConflictOrigin.local);
  });

  test('LastWriteWinsResolver picks whichever has the later timestamp', () {
    final older = TestUser(id: '1', name: 'Old', updatedAt: DateTime(2024));
    final newer = TestUser(id: '1', name: 'New', updatedAt: DateTime(2025));

    final resolver = LastWriteWinsResolver<TestUser>((u) => u.updatedAt!);

    expect(resolver.resolve(older, newer, _ctx(_op())).value, newer);
    expect(resolver.resolve(newer, older, _ctx(_op())).value, newer);
  });

  test('CustomResolver merges field-by-field', () {
    final resolver = CustomResolver<TestUser>((local, remote, ctx) {
      // name -> server, but keep local's id (contrived merge for the test).
      return local.copyWith(name: remote.name);
    });
    final result = resolver.resolve(local, remote, _ctx(_op()));
    expect(result.value.name, 'Remote Name');
    expect(result.origin, ConflictOrigin.merged);
  });
}
