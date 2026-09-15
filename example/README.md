# offline_sync_example

Two ways to see `offline_sync` in action:

## 1. Visual demo — [`lib/main.dart`](lib/main.dart)

A minimal single-screen Flutter app: add a todo (saves locally, visible in the list
immediately), toggle online/offline, watch each todo's live sync status. Shows the package
wired into a real widget tree.

```sh
flutter run
```

## 2. Console walkthrough — [`bin/offline_sync_example.dart`](bin/offline_sync_example.dart)

A single plain-Dart script covering more ground with print statements: local-first
save/get/watch, dependency-aware sync with temporary ids, retry with backoff, and conflict
resolution. No device/emulator needed.

```sh
flutter pub run offline_sync_example
```

(Not `dart run` — this repo's `offline_sync` package still depends on the Flutter SDK, so
plain `dart` resolves nothing. `flutter pub run` uses the Flutter-bundled Dart SDK.)
