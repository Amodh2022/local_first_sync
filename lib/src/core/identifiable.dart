/// Anything storable in a [LocalStore]/[Collection] must expose a stable,
/// string identity. The id is what temporary-id reassignment, dependency
/// tracking, and reactive `watchById` all key off of.
abstract interface class Identifiable {
  String get id;
}
