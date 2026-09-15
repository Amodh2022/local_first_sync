// A Flutter demo you can actually watch the sync lifecycle happen in.
//
// The whole point of a local-first framework is that a write lands *now* and
// reaches the server *later*, so this app makes both halves visible:
//
//   1. Tap "New todo" while the Offline switch is off. The row appears
//      instantly with a PENDING chip — nothing has touched the network.
//   2. Flip the switch to Online. The chip goes SYNCING (the fake backend
//      has 1.5s of latency so you can see it), then SYNCED.
//   3. The bar at the top is a single `SyncState` stream: connectivity,
//      in-flight spinner, unsynced count, and "last synced" — no polling.
//   4. The panel at the bottom is the Sync Inspector: every operation in
//      the queue with `explain()`'s plain-English reason it is stuck.
//
// The toolbar also drives the failure paths worth seeing: a transient error
// (watch it retry with backoff), a permanent one (watch it go FAILED and
// stay there until you hit Retry), pause/resume, and a pull of a record
// "another device" created.
//
// Run with: flutter run
import 'package:flutter/material.dart';
import 'package:offline_sync/offline_sync.dart';

void main() => runApp(const OfflineSyncDemoApp());

class OfflineSyncDemoApp extends StatelessWidget {
  const OfflineSyncDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'offline_sync demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    ),
    home: const TodoScreen(),
  );
}

// ---------------------------------------------------------------------------
// The model. Nothing sync-specific: a plain class plus an explicit serializer.
// ---------------------------------------------------------------------------

class Todo implements Identifiable {
  Todo({required this.id, required this.title, this.done = false});

  @override
  final String id;
  final String title;
  final bool done;

  Todo copyWith({String? title, bool? done}) =>
      Todo(id: id, title: title ?? this.title, done: done ?? this.done);
}

class TodoSerializer implements Serializer<Todo> {
  const TodoSerializer();

  @override
  Map<String, Object?> encode(Todo value) => {
    'id': value.id,
    'title': value.title,
    'done': value.done,
  };

  @override
  Todo decode(Map<String, Object?> data) => Todo(
    id: data['id']! as String,
    title: data['title']! as String,
    done: (data['done'] as bool?) ?? false,
  );
}

/// What the fake backend should do with the next request, so every failure
/// path in the engine can be triggered from the toolbar.
enum FailureMode { none, transient, permanent }

// ---------------------------------------------------------------------------

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  late final ManualConnectivityMonitor _connectivity;
  late final InMemoryRemoteStore<Todo> _remote;
  late final OfflineSync _sync;
  late final Collection<Todo> _todos;

  var _failureMode = FailureMode.none;
  var _online = false;
  var _nextId = 1;
  var _showInspector = true;

  @override
  void initState() {
    super.initState();

    _connectivity = ManualConnectivityMonitor(
      initial: ConnectivityState.offline,
    );

    // Slow on purpose: with a zero-latency backend every operation would go
    // from queued to synced within one frame and you would never see the
    // SYNCING state this demo exists to show.
    _remote = InMemoryRemoteStore<Todo>(
      latency: const Duration(milliseconds: 1500),
      failureInjector: (operation, item) => switch (_failureMode) {
        FailureMode.none => null,
        FailureMode.transient => const NetworkFailure(
          'Connection reset by the server',
        ),
        FailureMode.permanent => const ValidationFailure(
          'Title rejected by the backend',
        ),
      },
    );

    _sync = OfflineSync(
      connectivity: _connectivity,
      config: const SyncConfig(
        // Short, deterministic backoff so a retry is watchable rather than
        // something you wait a minute for.
        retryPolicy: RetryPolicy(
          initialDelay: Duration(seconds: 2),
          maxDelay: Duration(seconds: 8),
          maxAttempts: 3,
          jitter: 0,
        ),
        // Keep completed operations around long enough to stay on screen.
        retainSyncedOperations: Duration(minutes: 30),
      ),
    );

    _todos = _sync.registerCollection<Todo>(
      name: 'todos',
      localStore: InMemoryLocalStore<Todo>(),
      remoteStore: _remote,
      serializer: const TodoSerializer(),
    );

    // Reacts to connectivity coming back *and* to every queue change, so
    // nothing in this file ever has to call syncNow() to make a save sync.
    _sync.start();
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  // --- actions -------------------------------------------------------------

  Future<void> _addTodo() async {
    final id = 'todo_${_nextId++}';
    await _todos.save(Todo(id: id, title: 'Task #$id'));
  }

  Future<void> _toggleDone(Todo todo) =>
      _todos.save(todo.copyWith(done: !todo.done));

  Future<void> _deleteTodo(Todo todo) => _todos.delete(todo.id);

  void _setOnline(bool online) {
    setState(() => _online = online);
    online ? _connectivity.setOnline() : _connectivity.setOffline();
  }

  void _togglePause() {
    setState(() => _sync.isPaused ? _sync.resume() : _sync.pause());
  }

  /// Simulates another device having added a todo, then pulls it down.
  /// Records with unsynced local work queued are skipped, never clobbered.
  Future<void> _pullFromServer() async {
    final id =
        'from_other_device_${DateTime.now().millisecondsSinceEpoch % 1000}';
    _remote.seed(Todo(id: id, title: 'Added on another device'));
    final applied = await _sync.pullNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applied > 0
              ? 'Pulled $applied record(s) from the server'
              : 'Nothing new on the server (or you are offline)',
        ),
      ),
    );
  }

  Future<void> _retryAll() async {
    final count = await _sync.retryAllFailed();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Requeued $count failed operation(s)')),
    );
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('offline_sync demo'),
        actions: [
          Row(
            children: [
              Icon(_online ? Icons.cloud_done : Icons.cloud_off, size: 20),
              Text(_online ? ' Online' : ' Offline'),
              Switch(value: _online, onChanged: _setOnline),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTodo,
        icon: const Icon(Icons.add),
        label: const Text('New todo'),
      ),
      body: Column(
        children: [
          _SyncStatusBar(sync: _sync),
          _Toolbar(
            sync: _sync,
            failureMode: _failureMode,
            onFailureModeChanged: (mode) => setState(() => _failureMode = mode),
            onPauseToggled: _togglePause,
            onPull: _pullFromServer,
            onRetryAll: _retryAll,
            showInspector: _showInspector,
            onInspectorToggled: () =>
                setState(() => _showInspector = !_showInspector),
          ),
          const Divider(height: 1),
          Expanded(
            child: _TodoList(
              sync: _sync,
              todos: _todos,
              onToggleDone: _toggleDone,
              onDelete: _deleteTodo,
            ),
          ),
          if (_showInspector) ...[
            const Divider(height: 1),
            SizedBox(height: 220, child: _InspectorPanel(sync: _sync)),
          ],
        ],
      ),
    );
  }
}

/// Everything here comes from a single `sync.watchState()` subscription —
/// the one stream a status bar needs.
class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({required this.sync});

  final OfflineSync sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<SyncState>(
      stream: sync.watchState(),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) return const SizedBox(height: 56);

        final (color, label) = switch (state) {
          _ when state.isPaused => (Colors.orange, 'Paused'),
          _ when !state.isOnline => (Colors.grey, 'Offline'),
          _ when state.isSyncing => (Colors.blue, 'Syncing…'),
          _ when state.failed > 0 => (Colors.red, 'Needs attention'),
          _ when state.isUpToDate => (Colors.green, 'All changes synced'),
          _ => (Colors.blueGrey, 'Waiting to sync'),
        };

        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (state.isSyncing)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.circle, size: 12, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    state.hasUnsyncedWork
                        ? '${state.unsynced} unsynced'
                        : 'nothing queued',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'pending ${state.pending} · syncing ${state.syncing} · '
                'retrying ${state.retrying} · failed ${state.failed} · '
                'blocked ${state.blocked} · synced ${state.synced}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                state.lastSyncedAt == null
                    ? 'Never fully synced in this session'
                    : 'Last fully synced at '
                          '${_formatTime(state.lastSyncedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (state.lastError != null)
                Text(
                  'Last error: ${state.lastError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sync,
    required this.failureMode,
    required this.onFailureModeChanged,
    required this.onPauseToggled,
    required this.onPull,
    required this.onRetryAll,
    required this.showInspector,
    required this.onInspectorToggled,
  });

  final OfflineSync sync;
  final FailureMode failureMode;
  final ValueChanged<FailureMode> onFailureModeChanged;
  final VoidCallback onPauseToggled;
  final Future<void> Function() onPull;
  final Future<void> Function() onRetryAll;
  final bool showInspector;
  final VoidCallback onInspectorToggled;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          SegmentedButton<FailureMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: FailureMode.none, label: Text('Server OK')),
              ButtonSegment(
                value: FailureMode.transient,
                label: Text('Transient fail'),
              ),
              ButtonSegment(
                value: FailureMode.permanent,
                label: Text('Permanent fail'),
              ),
            ],
            selected: {failureMode},
            onSelectionChanged: (s) => onFailureModeChanged(s.first),
          ),
          FilledButton.tonalIcon(
            onPressed: onPauseToggled,
            icon: Icon(sync.isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(sync.isPaused ? 'Resume' : 'Pause'),
          ),
          FilledButton.tonalIcon(
            onPressed: onRetryAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry failed'),
          ),
          FilledButton.tonalIcon(
            onPressed: onPull,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Pull from server'),
          ),
          TextButton.icon(
            onPressed: onInspectorToggled,
            icon: Icon(showInspector ? Icons.visibility_off : Icons.visibility),
            label: const Text('Inspector'),
          ),
        ],
      ),
    );
  }
}

/// The list itself reads from `Collection.watch()` — a plain
/// `Stream<List<Todo>>` off local storage, so a save shows up before any
/// network call. The per-row chip comes from the inspector's view of the
/// queue.
class _TodoList extends StatelessWidget {
  const _TodoList({
    required this.sync,
    required this.todos,
    required this.onToggleDone,
    required this.onDelete,
  });

  final OfflineSync sync;
  final Collection<Todo> todos;
  final Future<void> Function(Todo) onToggleDone;
  final Future<void> Function(Todo) onDelete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Todo>>(
      stream: todos.watch(),
      initialData: const [],
      builder: (context, todoSnapshot) {
        final items = todoSnapshot.data ?? const <Todo>[];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Add a todo while Offline is on.\n'
                'It appears instantly as PENDING, then syncs when you go '
                'online.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return StreamBuilder<SyncInspectorSnapshot>(
          stream: sync.inspector().watch(),
          builder: (context, queueSnapshot) {
            final operations = queueSnapshot.data?.operations ?? const [];
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final todo = items[i];
                final op = _latestOperationFor(operations, todo.id);
                return ListTile(
                  key: ValueKey(todo.id),
                  leading: Checkbox(
                    value: todo.done,
                    onChanged: (_) => onToggleDone(todo),
                  ),
                  title: Text(
                    todo.title,
                    style: TextStyle(
                      decoration: todo.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text(
                    op == null
                        ? todo.id
                        : '${todo.id} · ${sync.inspector().explain(op)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusChip(status: op?.status),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onDelete(todo),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The most recent queued operation for one entity — what its chip reflects.
SyncOperation? _latestOperationFor(
  List<SyncOperation> operations,
  String entityId,
) {
  SyncOperation? latest;
  for (final op in operations) {
    if (op.collection != 'todos' || op.entityId != entityId) continue;
    if (latest == null || op.createdAt.isAfter(latest.createdAt)) latest = op;
  }
  return latest;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      // No queued operation for this entity: either it was pulled from the
      // server, or its operations have aged out of the queue.
      null => (Colors.grey, 'NOT QUEUED'),
      SyncStatus.synced => (Colors.green, 'SYNCED'),
      SyncStatus.syncing => (Colors.blue, 'SYNCING'),
      SyncStatus.retry => (Colors.amber, 'RETRYING'),
      SyncStatus.failed => (Colors.red, 'FAILED'),
      SyncStatus.blocked => (Colors.purple, 'BLOCKED'),
      SyncStatus.cancelled => (Colors.grey, 'CANCELLED'),
      SyncStatus.conflict => (Colors.deepOrange, 'CONFLICT'),
      _ => (Colors.blueGrey, 'PENDING'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// The Sync Inspector: every operation in the queue and, for each, the
/// plain-English reason it is where it is. This is the surface the package
/// exists to make possible — a status enum alone never answers "why is this
/// stuck?".
class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.sync});

  final OfflineSync sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<SyncInspectorSnapshot>(
      stream: sync.inspector().watch(),
      builder: (context, snapshot) {
        final operations = [...?snapshot.data?.operations]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Sync Inspector — ${operations.length} operation(s)',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: operations.isEmpty
                  ? const Center(child: Text('Queue is empty'))
                  : ListView.builder(
                      itemCount: operations.length,
                      itemBuilder: (context, i) {
                        final op = operations[i];
                        return ListTile(
                          dense: true,
                          leading: _StatusChip(status: op.status),
                          title: Text(
                            '${op.type.name.toUpperCase()} '
                            '${op.collection}/${op.entityId}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(sync.inspector().explain(op)),
                          trailing: op.status == SyncStatus.failed
                              ? TextButton(
                                  onPressed: () =>
                                      sync.retryOperation(op.operationId),
                                  child: const Text('Retry'),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

String _formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}:'
    '${time.second.toString().padLeft(2, '0')}';
