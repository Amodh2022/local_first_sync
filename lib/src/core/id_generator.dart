import 'dart:math';

int _counter = 0;
final _random = Random();

/// Generates a locally unique id for a [SyncOperation]. Not a UUID — just
/// unique enough within a single app install, which is all a queue key needs.
String generateOperationId() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final seq = _counter++;
  final rand = _random.nextInt(0xFFFFFF).toRadixString(16);
  return 'op_${ts}_${seq}_$rand';
}
