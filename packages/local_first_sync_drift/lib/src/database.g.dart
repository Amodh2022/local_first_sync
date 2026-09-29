// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalFirstEntitiesTable extends LocalFirstEntities
    with TableInfo<$LocalFirstEntitiesTable, LocalFirstEntityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFirstEntitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionMeta = const VerificationMeta(
    'collection',
  );
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
    'collection',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [collection, id, json, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_first_entities';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFirstEntityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection')) {
      context.handle(
        _collectionMeta,
        collection.isAcceptableOrUnknown(data['collection']!, _collectionMeta),
      );
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collection, id};
  @override
  LocalFirstEntityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFirstEntityRow(
      collection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalFirstEntitiesTable createAlias(String alias) {
    return $LocalFirstEntitiesTable(attachedDatabase, alias);
  }
}

class LocalFirstEntityRow extends DataClass
    implements Insertable<LocalFirstEntityRow> {
  final String collection;
  final String id;
  final String json;

  /// Milliseconds since epoch of the last local write.
  final int updatedAt;
  const LocalFirstEntityRow({
    required this.collection,
    required this.id,
    required this.json,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection'] = Variable<String>(collection);
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalFirstEntitiesCompanion toCompanion(bool nullToAbsent) {
    return LocalFirstEntitiesCompanion(
      collection: Value(collection),
      id: Value(id),
      json: Value(json),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalFirstEntityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFirstEntityRow(
      collection: serializer.fromJson<String>(json['collection']),
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collection': serializer.toJson<String>(collection),
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  LocalFirstEntityRow copyWith({
    String? collection,
    String? id,
    String? json,
    int? updatedAt,
  }) => LocalFirstEntityRow(
    collection: collection ?? this.collection,
    id: id ?? this.id,
    json: json ?? this.json,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalFirstEntityRow copyWithCompanion(LocalFirstEntitiesCompanion data) {
    return LocalFirstEntityRow(
      collection: data.collection.present
          ? data.collection.value
          : this.collection,
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFirstEntityRow(')
          ..write('collection: $collection, ')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(collection, id, json, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFirstEntityRow &&
          other.collection == this.collection &&
          other.id == this.id &&
          other.json == this.json &&
          other.updatedAt == this.updatedAt);
}

class LocalFirstEntitiesCompanion extends UpdateCompanion<LocalFirstEntityRow> {
  final Value<String> collection;
  final Value<String> id;
  final Value<String> json;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const LocalFirstEntitiesCompanion({
    this.collection = const Value.absent(),
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFirstEntitiesCompanion.insert({
    required String collection,
    required String id,
    required String json,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : collection = Value(collection),
       id = Value(id),
       json = Value(json),
       updatedAt = Value(updatedAt);
  static Insertable<LocalFirstEntityRow> custom({
    Expression<String>? collection,
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (collection != null) 'collection': collection,
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFirstEntitiesCompanion copyWith({
    Value<String>? collection,
    Value<String>? id,
    Value<String>? json,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalFirstEntitiesCompanion(
      collection: collection ?? this.collection,
      id: id ?? this.id,
      json: json ?? this.json,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFirstEntitiesCompanion(')
          ..write('collection: $collection, ')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFirstOperationsTable extends LocalFirstOperations
    with TableInfo<$LocalFirstOperationsTable, LocalFirstOperationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFirstOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [operationId, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_first_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFirstOperationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  LocalFirstOperationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFirstOperationRow(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $LocalFirstOperationsTable createAlias(String alias) {
    return $LocalFirstOperationsTable(attachedDatabase, alias);
  }
}

class LocalFirstOperationRow extends DataClass
    implements Insertable<LocalFirstOperationRow> {
  final String operationId;
  final String json;
  const LocalFirstOperationRow({required this.operationId, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['json'] = Variable<String>(json);
    return map;
  }

  LocalFirstOperationsCompanion toCompanion(bool nullToAbsent) {
    return LocalFirstOperationsCompanion(
      operationId: Value(operationId),
      json: Value(json),
    );
  }

  factory LocalFirstOperationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFirstOperationRow(
      operationId: serializer.fromJson<String>(json['operationId']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'json': serializer.toJson<String>(json),
    };
  }

  LocalFirstOperationRow copyWith({String? operationId, String? json}) =>
      LocalFirstOperationRow(
        operationId: operationId ?? this.operationId,
        json: json ?? this.json,
      );
  LocalFirstOperationRow copyWithCompanion(LocalFirstOperationsCompanion data) {
    return LocalFirstOperationRow(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFirstOperationRow(')
          ..write('operationId: $operationId, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(operationId, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFirstOperationRow &&
          other.operationId == this.operationId &&
          other.json == this.json);
}

class LocalFirstOperationsCompanion
    extends UpdateCompanion<LocalFirstOperationRow> {
  final Value<String> operationId;
  final Value<String> json;
  final Value<int> rowid;
  const LocalFirstOperationsCompanion({
    this.operationId = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFirstOperationsCompanion.insert({
    required String operationId,
    required String json,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       json = Value(json);
  static Insertable<LocalFirstOperationRow> custom({
    Expression<String>? operationId,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFirstOperationsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return LocalFirstOperationsCompanion(
      operationId: operationId ?? this.operationId,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFirstOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalFirstDatabase extends GeneratedDatabase {
  _$LocalFirstDatabase(QueryExecutor e) : super(e);
  $LocalFirstDatabaseManager get managers => $LocalFirstDatabaseManager(this);
  late final $LocalFirstEntitiesTable localFirstEntities =
      $LocalFirstEntitiesTable(this);
  late final $LocalFirstOperationsTable localFirstOperations =
      $LocalFirstOperationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localFirstEntities,
    localFirstOperations,
  ];
}

typedef $$LocalFirstEntitiesTableCreateCompanionBuilder =
    LocalFirstEntitiesCompanion Function({
      required String collection,
      required String id,
      required String json,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$LocalFirstEntitiesTableUpdateCompanionBuilder =
    LocalFirstEntitiesCompanion Function({
      Value<String> collection,
      Value<String> id,
      Value<String> json,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$LocalFirstEntitiesTableFilterComposer
    extends Composer<_$LocalFirstDatabase, $LocalFirstEntitiesTable> {
  $$LocalFirstEntitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFirstEntitiesTableOrderingComposer
    extends Composer<_$LocalFirstDatabase, $LocalFirstEntitiesTable> {
  $$LocalFirstEntitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFirstEntitiesTableAnnotationComposer
    extends Composer<_$LocalFirstDatabase, $LocalFirstEntitiesTable> {
  $$LocalFirstEntitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalFirstEntitiesTableTableManager
    extends
        RootTableManager<
          _$LocalFirstDatabase,
          $LocalFirstEntitiesTable,
          LocalFirstEntityRow,
          $$LocalFirstEntitiesTableFilterComposer,
          $$LocalFirstEntitiesTableOrderingComposer,
          $$LocalFirstEntitiesTableAnnotationComposer,
          $$LocalFirstEntitiesTableCreateCompanionBuilder,
          $$LocalFirstEntitiesTableUpdateCompanionBuilder,
          (
            LocalFirstEntityRow,
            BaseReferences<
              _$LocalFirstDatabase,
              $LocalFirstEntitiesTable,
              LocalFirstEntityRow
            >,
          ),
          LocalFirstEntityRow,
          PrefetchHooks Function()
        > {
  $$LocalFirstEntitiesTableTableManager(
    _$LocalFirstDatabase db,
    $LocalFirstEntitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFirstEntitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFirstEntitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFirstEntitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> collection = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFirstEntitiesCompanion(
                collection: collection,
                id: id,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String collection,
                required String id,
                required String json,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalFirstEntitiesCompanion.insert(
                collection: collection,
                id: id,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalFirstEntitiesTable, LocalFirstEntityRow>(
                    table,
                  ),
                  BaseReferences<
                    _$LocalFirstDatabase,
                    $LocalFirstEntitiesTable,
                    LocalFirstEntityRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFirstEntitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalFirstDatabase,
      $LocalFirstEntitiesTable,
      LocalFirstEntityRow,
      $$LocalFirstEntitiesTableFilterComposer,
      $$LocalFirstEntitiesTableOrderingComposer,
      $$LocalFirstEntitiesTableAnnotationComposer,
      $$LocalFirstEntitiesTableCreateCompanionBuilder,
      $$LocalFirstEntitiesTableUpdateCompanionBuilder,
      (
        LocalFirstEntityRow,
        BaseReferences<
          _$LocalFirstDatabase,
          $LocalFirstEntitiesTable,
          LocalFirstEntityRow
        >,
      ),
      LocalFirstEntityRow,
      PrefetchHooks Function()
    >;
typedef $$LocalFirstOperationsTableCreateCompanionBuilder =
    LocalFirstOperationsCompanion Function({
      required String operationId,
      required String json,
      Value<int> rowid,
    });
typedef $$LocalFirstOperationsTableUpdateCompanionBuilder =
    LocalFirstOperationsCompanion Function({
      Value<String> operationId,
      Value<String> json,
      Value<int> rowid,
    });

class $$LocalFirstOperationsTableFilterComposer
    extends Composer<_$LocalFirstDatabase, $LocalFirstOperationsTable> {
  $$LocalFirstOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFirstOperationsTableOrderingComposer
    extends Composer<_$LocalFirstDatabase, $LocalFirstOperationsTable> {
  $$LocalFirstOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFirstOperationsTableAnnotationComposer
    extends Composer<_$LocalFirstDatabase, $LocalFirstOperationsTable> {
  $$LocalFirstOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$LocalFirstOperationsTableTableManager
    extends
        RootTableManager<
          _$LocalFirstDatabase,
          $LocalFirstOperationsTable,
          LocalFirstOperationRow,
          $$LocalFirstOperationsTableFilterComposer,
          $$LocalFirstOperationsTableOrderingComposer,
          $$LocalFirstOperationsTableAnnotationComposer,
          $$LocalFirstOperationsTableCreateCompanionBuilder,
          $$LocalFirstOperationsTableUpdateCompanionBuilder,
          (
            LocalFirstOperationRow,
            BaseReferences<
              _$LocalFirstDatabase,
              $LocalFirstOperationsTable,
              LocalFirstOperationRow
            >,
          ),
          LocalFirstOperationRow,
          PrefetchHooks Function()
        > {
  $$LocalFirstOperationsTableTableManager(
    _$LocalFirstDatabase db,
    $LocalFirstOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFirstOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFirstOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalFirstOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFirstOperationsCompanion(
                operationId: operationId,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => LocalFirstOperationsCompanion.insert(
                operationId: operationId,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LocalFirstOperationsTable,
                    LocalFirstOperationRow
                  >(table),
                  BaseReferences<
                    _$LocalFirstDatabase,
                    $LocalFirstOperationsTable,
                    LocalFirstOperationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFirstOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalFirstDatabase,
      $LocalFirstOperationsTable,
      LocalFirstOperationRow,
      $$LocalFirstOperationsTableFilterComposer,
      $$LocalFirstOperationsTableOrderingComposer,
      $$LocalFirstOperationsTableAnnotationComposer,
      $$LocalFirstOperationsTableCreateCompanionBuilder,
      $$LocalFirstOperationsTableUpdateCompanionBuilder,
      (
        LocalFirstOperationRow,
        BaseReferences<
          _$LocalFirstDatabase,
          $LocalFirstOperationsTable,
          LocalFirstOperationRow
        >,
      ),
      LocalFirstOperationRow,
      PrefetchHooks Function()
    >;

class $LocalFirstDatabaseManager {
  final _$LocalFirstDatabase _db;
  $LocalFirstDatabaseManager(this._db);
  $$LocalFirstEntitiesTableTableManager get localFirstEntities =>
      $$LocalFirstEntitiesTableTableManager(_db, _db.localFirstEntities);
  $$LocalFirstOperationsTableTableManager get localFirstOperations =>
      $$LocalFirstOperationsTableTableManager(_db, _db.localFirstOperations);
}
