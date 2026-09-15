/// Explicit typed serialization. Prefer generated `encode`
/// implementations for performance-sensitive models rather than reflection.
///
/// `encode(value)['id']` must round-trip to the same value as
/// `(value as Identifiable).id` — the engine relies on that to detect
/// server-assigned id changes on create.
abstract interface class Serializer<T> {
  Map<String, Object?> encode(T value);

  T decode(Map<String, Object?> data);
}
