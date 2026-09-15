import 'package:local_first_sync/local_first_sync.dart';

class TestUser implements Identifiable {
  TestUser({required this.id, required this.name, this.updatedAt});

  @override
  final String id;
  final String name;
  final DateTime? updatedAt;

  TestUser copyWith({String? id, String? name, DateTime? updatedAt}) =>
      TestUser(
        id: id ?? this.id,
        name: name ?? this.name,
        updatedAt: updatedAt ?? this.updatedAt,
      );

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
        'updatedAt': value.updatedAt?.toIso8601String(),
      };

  @override
  TestUser decode(Map<String, Object?> data) => TestUser(
        id: data['id']! as String,
        name: data['name']! as String,
        updatedAt: data['updatedAt'] != null
            ? DateTime.parse(data['updatedAt']! as String)
            : null,
      );
}

class TestOrderItem implements Identifiable {
  TestOrderItem({required this.id, required this.orderId, required this.sku});

  @override
  final String id;
  final String orderId;
  final String sku;

  @override
  bool operator ==(Object other) =>
      other is TestOrderItem &&
      other.id == id &&
      other.orderId == orderId &&
      other.sku == sku;

  @override
  int get hashCode => Object.hash(id, orderId, sku);

  @override
  String toString() => 'TestOrderItem($id, order: $orderId, sku: $sku)';
}

class TestOrderItemSerializer implements Serializer<TestOrderItem> {
  const TestOrderItemSerializer();

  @override
  Map<String, Object?> encode(TestOrderItem value) =>
      {'id': value.id, 'orderId': value.orderId, 'sku': value.sku};

  @override
  TestOrderItem decode(Map<String, Object?> data) => TestOrderItem(
        id: data['id']! as String,
        orderId: data['orderId']! as String,
        sku: data['sku']! as String,
      );
}
