import 'package:local_first_sync/local_first_sync.dart';

class TestUser implements Identifiable {
  TestUser({required this.id, required this.name});

  @override
  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is TestUser && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'TestUser($id, $name)';
}

class TestUserSerializer implements Serializer<TestUser> {
  const TestUserSerializer();

  @override
  Map<String, Object?> encode(TestUser value) => {
    'id': value.id,
    'name': value.name,
  };

  @override
  TestUser decode(Map<String, Object?> data) =>
      TestUser(id: data['id']! as String, name: data['name']! as String);
}
