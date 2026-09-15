import '../core/sync_operation.dart';

enum ConflictOrigin { local, remote, merged }

class ConflictContext {
  const ConflictContext({
    required this.collection,
    required this.entityId,
    required this.operation,
  });

  final String collection;
  final String entityId;
  final SyncOperation operation;
}

class ConflictResolution<T> {
  const ConflictResolution(this.value, this.origin);

  final T value;
  final ConflictOrigin origin;
}

/// Extensible conflict resolution. Do not claim every
/// conflict can be automatically resolved — every resolution, including
/// automatic ones, is still surfaced as a [ConflictDetected] event so it
/// remains observable.
abstract interface class ConflictResolver<T> {
  ConflictResolution<T> resolve(T local, T remote, ConflictContext context);
}

class ServerWinsResolver<T> implements ConflictResolver<T> {
  const ServerWinsResolver();

  @override
  ConflictResolution<T> resolve(T local, T remote, ConflictContext context) =>
      ConflictResolution(remote, ConflictOrigin.remote);
}

class ClientWinsResolver<T> implements ConflictResolver<T> {
  const ClientWinsResolver();

  @override
  ConflictResolution<T> resolve(T local, T remote, ConflictContext context) =>
      ConflictResolution(local, ConflictOrigin.local);
}

/// Requires a reconcilable timestamp on [T] — that's a real constraint, not
/// an assumption we hide from the caller.
class LastWriteWinsResolver<T> implements ConflictResolver<T> {
  const LastWriteWinsResolver(this.timestampOf);

  final DateTime Function(T value) timestampOf;

  @override
  ConflictResolution<T> resolve(T local, T remote, ConflictContext context) {
    final remoteIsNewer = timestampOf(remote).isAfter(timestampOf(local));
    return remoteIsNewer
        ? ConflictResolution(remote, ConflictOrigin.remote)
        : ConflictResolution(local, ConflictOrigin.local);
  }
}

typedef CustomResolverFn<T> = T Function(
  T local,
  T remote,
  ConflictContext context,
);

/// Wraps an app-supplied merge function, e.g. for field-level resolution:
/// `(local, remote, ctx) => local.copyWith(name: remote.name)`.
class CustomResolver<T> implements ConflictResolver<T> {
  const CustomResolver(this.resolver);

  final CustomResolverFn<T> resolver;

  @override
  ConflictResolution<T> resolve(T local, T remote, ConflictContext context) =>
      ConflictResolution(
          resolver(local, remote, context), ConflictOrigin.merged);
}
