import 'dart:math';

import 'sync_errors.dart';

/// Configurable exponential backoff (AGENTS.md §12). `initialDelay *
/// multiplier^attempt`, capped at `maxDelay`, then spread by [jitter].
class RetryPolicy {
  const RetryPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.multiplier = 2.0,
    this.maxDelay = const Duration(minutes: 5),
    this.maxAttempts,
    this.jitter = 0.2,
  }) : assert(jitter >= 0 && jitter <= 1, 'jitter must be between 0 and 1');

  final Duration initialDelay;
  final double multiplier;
  final Duration maxDelay;

  /// Maximum number of retry attempts for a retryable failure. `null` means
  /// keep retrying indefinitely (still bounded by [maxDelay] between tries).
  final int? maxAttempts;

  /// Randomizes each computed delay by ±[jitter] (a fraction of the delay,
  /// `0.2` = ±20%). Without this, every operation queued during the same
  /// outage retries at the same instant and stampedes the backend the
  /// moment it comes back. Set to `0` for fully deterministic delays.
  final double jitter;

  static final _random = Random();

  Duration delayForAttempt(int attempt) {
    final rawMs = initialDelay.inMilliseconds * pow(multiplier, attempt);
    final cappedMs = min(rawMs.isFinite ? rawMs : double.maxFinite,
        maxDelay.inMilliseconds.toDouble());
    if (jitter == 0) return Duration(milliseconds: cappedMs.round());
    final spread = cappedMs * jitter;
    final jittered = cappedMs + (_random.nextDouble() * 2 - 1) * spread;
    return Duration(milliseconds: max(0, jittered).round());
  }

  /// Whether the engine should schedule another attempt for [failure], given
  /// how many attempts have already happened ([retryCount]).
  bool shouldRetry(SyncFailure failure, int retryCount) {
    if (!failure.retryable) return false;
    final max = maxAttempts;
    if (max != null && retryCount >= max) return false;
    return true;
  }
}
