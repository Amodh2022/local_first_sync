/// Typed failures a [RemoteStore]/adapter can throw so the [SyncEngine] can
/// make a correct retry decision without guessing from an exception's
/// runtime type or message text.
///
/// Adapters should throw one of these (or a subclass) rather than letting a
/// raw HTTP/platform exception escape — that's the only way the engine can
/// honor "never retry permanent failures forever" (AGENTS.md §12).
sealed class SyncFailure implements Exception {
  const SyncFailure(this.message, {required this.retryable});

  final String message;

  /// Whether the [SyncEngine] should schedule a retry for this failure.
  final bool retryable;

  @override
  String toString() => message;
}

/// The device/socket could not reach the backend at all.
class NetworkFailure extends SyncFailure {
  const NetworkFailure(super.message) : super(retryable: true);
}

/// The request took too long.
class TimeoutFailure extends SyncFailure {
  const TimeoutFailure(super.message) : super(retryable: true);
}

/// The backend responded with an HTTP-style status code. 5xx is treated as
/// transient; anything else is treated as permanent unless overridden.
class ServerFailure extends SyncFailure {
  ServerFailure(this.statusCode, String message)
      : super(message, retryable: statusCode >= 500);

  final int statusCode;
}

/// The payload was rejected as invalid. Never retryable — retrying an
/// invalid payload forever would just waste the queue's time.
class ValidationFailure extends SyncFailure {
  const ValidationFailure(super.message) : super(retryable: false);
}

/// The credentials/session are no longer valid. Special-cased in AGENTS.md
/// §12 as "special handling" rather than a plain retry; MVP treats it as
/// non-retryable and surfaces it via events for the app to react to (e.g. by
/// refreshing a token and re-enqueuing).
class AuthFailure extends SyncFailure {
  const AuthFailure(super.message) : super(retryable: false);
}

/// The remote record has diverged from the local one. Carries the current
/// remote value (as an encoded payload) so a [ConflictResolver] can act on
/// it. Never auto-retried — conflicts are routed through resolution instead.
class ConflictFailure extends SyncFailure {
  const ConflictFailure(super.message, {this.remoteValue})
      : super(retryable: false);

  /// The current server-side value, if the backend/adapter provided one.
  final Object? remoteValue;
}

/// An error the engine doesn't recognize. Treated conservatively as
/// non-retryable so an unexpected exception can't spin forever.
class UnknownFailure extends SyncFailure {
  const UnknownFailure(super.message) : super(retryable: false);
}
