import 'package:drift/drift.dart';
import 'package:local_first_sync/local_first_sync.dart';

/// A [LocalStore] over *your own* typed Drift table, for models you want to
/// query in SQL (real columns, indexes, joins) rather than store as JSON in
/// [LocalFirstDatabase]'s generic table.
///
/// Subclass it once per table and supply the mapping; every [LocalStore]
/// method is implemented for you:
///
/// ```dart
/// class TodoStore extends DriftTableLocalStore<Todo, Todos, TodoRow> {
///   TodoStore(this.db);
///
///   @override
///   final AppDatabase db;
///
///   @override
///   TableInfo<Todos, TodoRow> get table => db.todos;
///
///   @override
///   Column<String> idColumn(Todos t) => t.id;
///
///   @override
///   Insertable<TodoRow> toRow(Todo todo) =>
///       TodosCompanion.insert(id: todo.id, title: todo.title);
///
///   @override
///   Todo fromRow(TodoRow row) => Todo(id: row.id, title: row.title);
/// }
/// ```
///
/// The table's primary key must be the id column: [insert]/[update] upsert
/// on it. Rows come back in SQLite's natural order unless you override
/// [orderBy], because not every table has a rowid to sort by.
abstract class DriftTableLocalStore<
  T extends Identifiable,
  Tbl extends Table,
  Row
>
    implements LocalStore<T> {
  /// The database that owns [table].
  GeneratedDatabase get db;

  TableInfo<Tbl, Row> get table;

  /// The text column holding [Identifiable.id].
  Column<String> idColumn(Tbl t);

  Insertable<Row> toRow(T item);

  T fromRow(Row row);

  /// Ordering for [getAll]/[watchAll]. Override to sort, for example
  /// `[OrderingTerm.asc(t.createdAt)]`. Empty by default.
  List<OrderingTerm> orderBy(Tbl t) => const [];

  SimpleSelectStatement<Tbl, Row> _all() {
    final statement = db.select(table);
    final terms = orderBy(table.asDslTable);
    if (terms.isNotEmpty) {
      statement.orderBy([for (final term in terms) (_) => term]);
    }
    return statement;
  }

  SimpleSelectStatement<Tbl, Row> _byId(String id) =>
      db.select(table)..where((t) => idColumn(t).equals(id));

  Future<int> _delete(String id) =>
      (db.delete(table)..where((t) => idColumn(t).equals(id))).go();

  @override
  Future<T?> getById(String id) async {
    final row = await _byId(id).getSingleOrNull();
    return row == null ? null : fromRow(row);
  }

  @override
  Future<List<T>> getAll() async => (await _all().get()).map(fromRow).toList();

  @override
  Future<void> insert(T item) =>
      db.into(table).insertOnConflictUpdate(toRow(item));

  @override
  Future<void> update(T item) =>
      db.into(table).insertOnConflictUpdate(toRow(item));

  @override
  Future<void> delete(String id) => _delete(id);

  @override
  Future<void> reassignId(String oldId, T newItem) => db.transaction(() async {
    await _delete(oldId);
    await _delete(newItem.id);
    await db.into(table).insert(toRow(newItem));
  });

  @override
  Stream<List<T>> watchAll() =>
      _all().watch().map((rows) => rows.map(fromRow).toList());

  @override
  Stream<T?> watchById(String id) => _byId(
    id,
  ).watchSingleOrNull().map((row) => row == null ? null : fromRow(row));
}
