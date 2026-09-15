/// Tracks `temporaryId -> serverId` mappings created when a `create`
/// operation for an offline-generated entity finally syncs (AGENTS.md §15).
///
/// [rewritePayload] is how those mappings actually get applied: it walks a
/// caller-declared list of reference fields and swaps any value that matches
/// a known temporary id for its resolved server id. It never does naive
/// whole-payload string replacement, since a temp id could coincidentally
/// match unrelated text.
class TempIdRegistry {
  final _map = <String, String>{};

  void register(String tempId, String realId) {
    if (tempId == realId) return;
    _map[tempId] = realId;
  }

  /// Follows the mapping chain (in case of `a -> b -> c`, which shouldn't
  /// normally happen but is handled defensively) and returns the final id.
  /// Returns [id] unchanged if it isn't a known temporary id.
  String resolve(String id) {
    var current = id;
    final seen = <String>{};
    while (_map.containsKey(current) && seen.add(current)) {
      current = _map[current]!;
    }
    return current;
  }

  /// Returns a copy of [payload] with every declared [referenceFields] value
  /// (a single id, or a list of ids) resolved through [resolve].
  Map<String, Object?> rewritePayload(
    Map<String, Object?> payload,
    List<String> referenceFields,
  ) {
    if (referenceFields.isEmpty || _map.isEmpty) return payload;
    var changed = false;
    final result = Map<String, Object?>.of(payload);
    for (final field in referenceFields) {
      final value = result[field];
      if (value is String) {
        final resolved = resolve(value);
        if (resolved != value) {
          result[field] = resolved;
          changed = true;
        }
      } else if (value is List) {
        final resolvedList =
            value.map((v) => v is String ? resolve(v) : v).toList();
        if (!_listEquals(resolvedList, value)) {
          result[field] = resolvedList;
          changed = true;
        }
      }
    }
    return changed ? result : payload;
  }

  bool _listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
