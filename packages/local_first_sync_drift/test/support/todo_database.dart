import 'package:drift/drift.dart';
import 'package:local_first_sync/local_first_sync.dart';
import 'package:local_first_sync_drift/local_first_sync_drift.dart';

part 'todo_database.g.dart';

/// A typed app table, as a user of [DriftTableLocalStore] would define it.
@DataClassName('TodoRow')
class Todos extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Todos])
class TodoDatabase extends _$TodoDatabase {
  TodoDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

class Todo implements Identifiable {
  Todo({required this.id, required this.title, this.done = false});

  @override
  final String id;
  final String title;
  final bool done;

  @override
  bool operator ==(Object other) =>
      other is Todo &&
      other.id == id &&
      other.title == title &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, title, done);

  @override
  String toString() => 'Todo($id, $title, done: $done)';
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
    done: data['done'] as bool? ?? false,
  );
}

class TodoStore extends DriftTableLocalStore<Todo, Todos, TodoRow> {
  TodoStore(this.db);

  @override
  final TodoDatabase db;

  @override
  TableInfo<Todos, TodoRow> get table => db.todos;

  @override
  Column<String> idColumn(Todos t) => t.id;

  @override
  Insertable<TodoRow> toRow(Todo todo) => TodosCompanion.insert(
    id: todo.id,
    title: todo.title,
    done: Value(todo.done),
  );

  @override
  Todo fromRow(TodoRow row) =>
      Todo(id: row.id, title: row.title, done: row.done);

  @override
  List<OrderingTerm> orderBy(Todos t) => [OrderingTerm.asc(t.title)];
}
