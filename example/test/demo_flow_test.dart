// Proves the demo's headline claim: a save is visible locally and marked
// PENDING before any network call, and becomes SYNCED once online.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_first_sync_example/main.dart';

void main() {
  testWidgets('a todo saved offline shows PENDING, then SYNCED once online', (
    tester,
  ) async {
    await tester.pumpWidget(const OfflineSyncDemoApp());
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);

    // 1. Save while offline — visible immediately, nothing sent.
    await tester.tap(find.text('New todo'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Task #todo_1'),
      findsOneWidget,
      reason:
          'the local write must be on screen without waiting on a '
          'network round trip',
    );
    expect(find.text('PENDING'), findsWidgets);
    expect(find.text('SYNCED'), findsNothing);

    // 2. Go online: the fake backend has 1.5s of latency, so SYNCING is a
    //    state you can actually observe.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('SYNCING'), findsWidgets);

    // 3. Let the request land.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('SYNCED'), findsWidgets);
    expect(find.text('All changes synced'), findsOneWidget);
  });
}
