# local_first_sync_example

Two ways to see `local_first_sync` in action.

## 1. Visual demo — [`lib/main.dart`](lib/main.dart)

A Flutter app that makes the sync lifecycle watchable. Add a todo while the Offline switch
is on and it appears instantly with a `PENDING` chip — nothing has touched the network. Flip
to Online and the chip goes `SYNCING` (the fake backend has 1.5 s of latency on purpose),
then `SYNCED`.

The toolbar drives the paths worth seeing: a transient failure (watch it retry on its own
when the backoff elapses), a permanent one (watch it go `FAILED` and stay there until you hit
Retry), pause/resume, and pulling a record "another device" created. The bar at the top is a
single `SyncState` stream; the panel at the bottom is the Sync Inspector, showing every queued
operation with `explain()`'s plain-English reason it is where it is.

```sh
flutter run
```

## 2. Console walkthrough — [`bin/local_first_sync_example.dart`](bin/local_first_sync_example.dart)

One plain-Dart script covering more ground, with print statements: local-first
save/get/watch, dependency-aware sync with temporary ids, retry with backoff, conflict
resolution, operation coalescing, a queue that survives a restart, pause/resume and manual
retry, pull sync, and rollback of a rejected write. No device or emulator needed.

```sh
dart run bin/local_first_sync_example.dart
```

Run `flutter pub get` once first — this example is a Flutter app, so its own dependencies
need the Flutter SDK even though `local_first_sync` itself is pure Dart.
