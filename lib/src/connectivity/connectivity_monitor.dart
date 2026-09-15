import 'dart:async';

/// AGENTS.md §13: never equate device network connectivity with server
/// reachability. This MVP models only the binary distinction a core can make
/// without a platform plugin; an adapter can implement a richer
/// [ConnectivityMonitor] (e.g. layering `connectivity_plus` + a reachability
/// ping) without the core needing to change.
enum ConnectivityState { offline, online }

abstract interface class ConnectivityMonitor {
  ConnectivityState get current;

  Stream<ConnectivityState> get onStateChanged;
}

/// A [ConnectivityMonitor] driven entirely by explicit calls — the default
/// for apps/tests that don't wire up a platform-specific adapter, and the
/// building block integration tests use to simulate offline/online
/// transitions deterministically.
class ManualConnectivityMonitor implements ConnectivityMonitor {
  ManualConnectivityMonitor(
      {ConnectivityState initial = ConnectivityState.online})
      : _state = initial;

  ConnectivityState _state;
  final _controller = StreamController<ConnectivityState>.broadcast();

  @override
  ConnectivityState get current => _state;

  @override
  Stream<ConnectivityState> get onStateChanged => _controller.stream;

  void setOnline() => _set(ConnectivityState.online);

  void setOffline() => _set(ConnectivityState.offline);

  void _set(ConnectivityState state) {
    if (state == _state) return;
    _state = state;
    _controller.add(state);
  }

  Future<void> dispose() => _controller.close();
}

/// A [ConnectivityMonitor] that decides it is online by actually reaching
/// something, rather than by asking the OS whether a network interface is up.
///
/// This is the §13 distinction made real, and it is the one every competing
/// package gets wrong by wiring `connectivity_plus` straight into the sync
/// trigger: a captive-portal wifi, an expired VPN, or a backend that is
/// simply down all report "connected" and send the queue into a retry storm.
///
/// Dependency-free by design — you supply the probe, so it can be a cheap
/// `HEAD /health` on your own backend (the only thing that actually
/// matters), and you can layer it on top of `connectivity_plus` by calling
/// [check] from that plugin's stream instead of, or as well as, polling.
///
/// ```dart
/// final monitor = ReachabilityConnectivityMonitor(
///   probe: () async {
///     try {
///       final res = await http.head(Uri.parse('https://api.example.com/health'))
///           .timeout(const Duration(seconds: 5));
///       return res.statusCode < 500;
///     } catch (_) {
///       return false;
///     }
///   },
///   interval: const Duration(seconds: 30),
/// )..start();
/// ```
class ReachabilityConnectivityMonitor implements ConnectivityMonitor {
  ReachabilityConnectivityMonitor({
    required this.probe,
    this.interval = const Duration(seconds: 30),
    ConnectivityState initial = ConnectivityState.offline,
  }) : _state = initial;

  /// Returns whether the backend is genuinely reachable right now. Must not
  /// throw — return `false` instead.
  final Future<bool> Function() probe;

  /// How often [check] runs while [start]ed.
  final Duration interval;

  ConnectivityState _state;
  final _controller = StreamController<ConnectivityState>.broadcast();
  Timer? _timer;
  bool _checking = false;

  @override
  ConnectivityState get current => _state;

  @override
  Stream<ConnectivityState> get onStateChanged => _controller.stream;

  /// Begins polling. Runs one [check] immediately so the first state isn't
  /// stale for a whole [interval].
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
    unawaited(check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Probes once and updates the state. Call this directly on app resume, on
  /// a `connectivity_plus` change, or after a network failure, instead of
  /// waiting for the next tick. Overlapping calls are ignored.
  Future<ConnectivityState> check() async {
    if (_checking) return _state;
    _checking = true;
    try {
      final reachable = await probe();
      _set(reachable ? ConnectivityState.online : ConnectivityState.offline);
    } finally {
      _checking = false;
    }
    return _state;
  }

  void _set(ConnectivityState state) {
    if (state == _state) return;
    _state = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
