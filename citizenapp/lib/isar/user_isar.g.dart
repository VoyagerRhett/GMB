// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_isar.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserPublicProfileCacheEntityCollection on Isar {
  IsarCollection<UserPublicProfileCacheEntity>
  get userPublicProfileCacheEntitys => this.collection();
}

const UserPublicProfileCacheEntitySchema = CollectionSchema(
  name: r'UserPublicProfileCacheEntity',
  id: 8159616370897781851,
  properties: {
    r'cidNumber': PropertySchema(
      id: 0,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'profileJson': PropertySchema(
      id: 1,
      name: r'profileJson',
      type: IsarType.string,
    ),
  },

  estimateSize: _userPublicProfileCacheEntityEstimateSize,
  serialize: _userPublicProfileCacheEntitySerialize,
  deserialize: _userPublicProfileCacheEntityDeserialize,
  deserializeProp: _userPublicProfileCacheEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber': IndexSchema(
      id: -8947736671869741624,
      name: r'cidNumber',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _userPublicProfileCacheEntityGetId,
  getLinks: _userPublicProfileCacheEntityGetLinks,
  attach: _userPublicProfileCacheEntityAttach,
  version: '3.3.2',
);

int _userPublicProfileCacheEntityEstimateSize(
  UserPublicProfileCacheEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.profileJson.length * 3;
  return bytesCount;
}

void _userPublicProfileCacheEntitySerialize(
  UserPublicProfileCacheEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cidNumber);
  writer.writeString(offsets[1], object.profileJson);
}

UserPublicProfileCacheEntity _userPublicProfileCacheEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = UserPublicProfileCacheEntity();
  object.cidNumber = reader.readString(offsets[0]);
  object.id = id;
  object.profileJson = reader.readString(offsets[1]);
  return object;
}

P _userPublicProfileCacheEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userPublicProfileCacheEntityGetId(UserPublicProfileCacheEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userPublicProfileCacheEntityGetLinks(
  UserPublicProfileCacheEntity object,
) {
  return [];
}

void _userPublicProfileCacheEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  UserPublicProfileCacheEntity object,
) {
  object.id = id;
}

extension UserPublicProfileCacheEntityByIndex
    on IsarCollection<UserPublicProfileCacheEntity> {
  Future<UserPublicProfileCacheEntity?> getByCidNumber(String cidNumber) {
    return getByIndex(r'cidNumber', [cidNumber]);
  }

  UserPublicProfileCacheEntity? getByCidNumberSync(String cidNumber) {
    return getByIndexSync(r'cidNumber', [cidNumber]);
  }

  Future<bool> deleteByCidNumber(String cidNumber) {
    return deleteByIndex(r'cidNumber', [cidNumber]);
  }

  bool deleteByCidNumberSync(String cidNumber) {
    return deleteByIndexSync(r'cidNumber', [cidNumber]);
  }

  Future<List<UserPublicProfileCacheEntity?>> getAllByCidNumber(
    List<String> cidNumberValues,
  ) {
    final values = cidNumberValues.map((e) => [e]).toList();
    return getAllByIndex(r'cidNumber', values);
  }

  List<UserPublicProfileCacheEntity?> getAllByCidNumberSync(
    List<String> cidNumberValues,
  ) {
    final values = cidNumberValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'cidNumber', values);
  }

  Future<int> deleteAllByCidNumber(List<String> cidNumberValues) {
    final values = cidNumberValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'cidNumber', values);
  }

  int deleteAllByCidNumberSync(List<String> cidNumberValues) {
    final values = cidNumberValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'cidNumber', values);
  }

  Future<Id> putByCidNumber(UserPublicProfileCacheEntity object) {
    return putByIndex(r'cidNumber', object);
  }

  Id putByCidNumberSync(
    UserPublicProfileCacheEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'cidNumber', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCidNumber(
    List<UserPublicProfileCacheEntity> objects,
  ) {
    return putAllByIndex(r'cidNumber', objects);
  }

  List<Id> putAllByCidNumberSync(
    List<UserPublicProfileCacheEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'cidNumber', objects, saveLinks: saveLinks);
  }
}

extension UserPublicProfileCacheEntityQueryWhereSort
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QWhere
        > {
  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension UserPublicProfileCacheEntityQueryWhere
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QWhereClause
        > {
  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  cidNumberEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'cidNumber', value: [cidNumber]),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterWhereClause
  >
  cidNumberNotEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension UserPublicProfileCacheEntityQueryFilter
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QFilterCondition
        > {
  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'cidNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'cidNumber',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profileJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileJson',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'profileJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'profileJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'profileJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'profileJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileJson', value: ''),
      );
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterFilterCondition
  >
  profileJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'profileJson', value: ''),
      );
    });
  }
}

extension UserPublicProfileCacheEntityQueryObject
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QFilterCondition
        > {}

extension UserPublicProfileCacheEntityQueryLinks
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QFilterCondition
        > {}

extension UserPublicProfileCacheEntityQuerySortBy
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QSortBy
        > {
  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  sortByProfileJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileJson', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  sortByProfileJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileJson', Sort.desc);
    });
  }
}

extension UserPublicProfileCacheEntityQuerySortThenBy
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QSortThenBy
        > {
  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  thenByProfileJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileJson', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QAfterSortBy
  >
  thenByProfileJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileJson', Sort.desc);
    });
  }
}

extension UserPublicProfileCacheEntityQueryWhereDistinct
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QDistinct
        > {
  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QDistinct
  >
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    UserPublicProfileCacheEntity,
    UserPublicProfileCacheEntity,
    QDistinct
  >
  distinctByProfileJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileJson', caseSensitive: caseSensitive);
    });
  }
}

extension UserPublicProfileCacheEntityQueryProperty
    on
        QueryBuilder<
          UserPublicProfileCacheEntity,
          UserPublicProfileCacheEntity,
          QQueryProperty
        > {
  QueryBuilder<UserPublicProfileCacheEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<UserPublicProfileCacheEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<UserPublicProfileCacheEntity, String, QQueryOperations>
  profileJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileJson');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserIdentityBadgeSnapshotEntityCollection on Isar {
  IsarCollection<UserIdentityBadgeSnapshotEntity>
  get userIdentityBadgeSnapshotEntitys => this.collection();
}

const UserIdentityBadgeSnapshotEntitySchema = CollectionSchema(
  name: r'UserIdentityBadgeSnapshotEntity',
  id: 5558258433434776581,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'cidNumber': PropertySchema(
      id: 1,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'identityLevel': PropertySchema(
      id: 2,
      name: r'identityLevel',
      type: IsarType.string,
    ),
    r'identitySnapshotJson': PropertySchema(
      id: 3,
      name: r'identitySnapshotJson',
      type: IsarType.string,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 4,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _userIdentityBadgeSnapshotEntityEstimateSize,
  serialize: _userIdentityBadgeSnapshotEntitySerialize,
  deserialize: _userIdentityBadgeSnapshotEntityDeserialize,
  deserializeProp: _userIdentityBadgeSnapshotEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber': IndexSchema(
      id: -8947736671869741624,
      name: r'cidNumber',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'accountId': IndexSchema(
      id: -1591555361937770434,
      name: r'accountId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'accountId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _userIdentityBadgeSnapshotEntityGetId,
  getLinks: _userIdentityBadgeSnapshotEntityGetLinks,
  attach: _userIdentityBadgeSnapshotEntityAttach,
  version: '3.3.2',
);

int _userIdentityBadgeSnapshotEntityEstimateSize(
  UserIdentityBadgeSnapshotEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.accountId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.identityLevel.length * 3;
  {
    final value = object.identitySnapshotJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _userIdentityBadgeSnapshotEntitySerialize(
  UserIdentityBadgeSnapshotEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.cidNumber);
  writer.writeString(offsets[2], object.identityLevel);
  writer.writeString(offsets[3], object.identitySnapshotJson);
  writer.writeLong(offsets[4], object.updatedAtMillis);
}

UserIdentityBadgeSnapshotEntity _userIdentityBadgeSnapshotEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = UserIdentityBadgeSnapshotEntity();
  object.accountId = reader.readStringOrNull(offsets[0]);
  object.cidNumber = reader.readString(offsets[1]);
  object.id = id;
  object.identityLevel = reader.readString(offsets[2]);
  object.identitySnapshotJson = reader.readStringOrNull(offsets[3]);
  object.updatedAtMillis = reader.readLong(offsets[4]);
  return object;
}

P _userIdentityBadgeSnapshotEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userIdentityBadgeSnapshotEntityGetId(
  UserIdentityBadgeSnapshotEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userIdentityBadgeSnapshotEntityGetLinks(
  UserIdentityBadgeSnapshotEntity object,
) {
  return [];
}

void _userIdentityBadgeSnapshotEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  UserIdentityBadgeSnapshotEntity object,
) {
  object.id = id;
}

extension UserIdentityBadgeSnapshotEntityQueryWhereSort
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QWhere
        > {
  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension UserIdentityBadgeSnapshotEntityQueryWhere
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QWhereClause
        > {
  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  cidNumberEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'cidNumber', value: [cidNumber]),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  cidNumberNotEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  accountIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'accountId', value: [null]),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  accountIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'accountId',
          lower: [null],
          includeLower: false,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  accountIdEqualTo(String? accountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'accountId', value: [accountId]),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterWhereClause
  >
  accountIdNotEqualTo(String? accountId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'accountId',
                lower: [],
                upper: [accountId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'accountId',
                lower: [accountId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'accountId',
                lower: [accountId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'accountId',
                lower: [],
                upper: [accountId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension UserIdentityBadgeSnapshotEntityQueryFilter
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QFilterCondition
        > {
  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'accountId'),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'accountId'),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'accountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'accountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'accountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'accountId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'accountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'accountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'accountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'accountId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'accountId', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  accountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'accountId', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'cidNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'cidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'cidNumber',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'identityLevel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'identityLevel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'identityLevel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'identityLevel',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'identityLevel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'identityLevel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'identityLevel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'identityLevel',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'identityLevel', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identityLevelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'identityLevel', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'identitySnapshotJson'),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'identitySnapshotJson'),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'identitySnapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'identitySnapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'identitySnapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'identitySnapshotJson',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'identitySnapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'identitySnapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'identitySnapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'identitySnapshotJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'identitySnapshotJson', value: ''),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  identitySnapshotJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'identitySnapshotJson',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  updatedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  updatedAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  updatedAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterFilterCondition
  >
  updatedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension UserIdentityBadgeSnapshotEntityQueryObject
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QFilterCondition
        > {}

extension UserIdentityBadgeSnapshotEntityQueryLinks
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QFilterCondition
        > {}

extension UserIdentityBadgeSnapshotEntityQuerySortBy
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QSortBy
        > {
  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByIdentityLevel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identityLevel', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByIdentityLevelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identityLevel', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByIdentitySnapshotJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identitySnapshotJson', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByIdentitySnapshotJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identitySnapshotJson', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension UserIdentityBadgeSnapshotEntityQuerySortThenBy
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QSortThenBy
        > {
  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByIdentityLevel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identityLevel', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByIdentityLevelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identityLevel', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByIdentitySnapshotJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identitySnapshotJson', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByIdentitySnapshotJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'identitySnapshotJson', Sort.desc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension UserIdentityBadgeSnapshotEntityQueryWhereDistinct
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QDistinct
        > {
  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QDistinct
  >
  distinctByAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QDistinct
  >
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QDistinct
  >
  distinctByIdentityLevel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'identityLevel',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QDistinct
  >
  distinctByIdentitySnapshotJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'identitySnapshotJson',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<
    UserIdentityBadgeSnapshotEntity,
    UserIdentityBadgeSnapshotEntity,
    QDistinct
  >
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension UserIdentityBadgeSnapshotEntityQueryProperty
    on
        QueryBuilder<
          UserIdentityBadgeSnapshotEntity,
          UserIdentityBadgeSnapshotEntity,
          QQueryProperty
        > {
  QueryBuilder<UserIdentityBadgeSnapshotEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<UserIdentityBadgeSnapshotEntity, String?, QQueryOperations>
  accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<UserIdentityBadgeSnapshotEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<UserIdentityBadgeSnapshotEntity, String, QQueryOperations>
  identityLevelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'identityLevel');
    });
  }

  QueryBuilder<UserIdentityBadgeSnapshotEntity, String?, QQueryOperations>
  identitySnapshotJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'identitySnapshotJson');
    });
  }

  QueryBuilder<UserIdentityBadgeSnapshotEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserContactStateEntityCollection on Isar {
  IsarCollection<UserContactStateEntity> get userContactStateEntitys =>
      this.collection();
}

const UserContactStateEntitySchema = CollectionSchema(
  name: r'UserContactStateEntity',
  id: 4018788771566803176,
  properties: {
    r'ownerCidNumber': PropertySchema(
      id: 0,
      name: r'ownerCidNumber',
      type: IsarType.string,
    ),
    r'sealedPayload': PropertySchema(
      id: 1,
      name: r'sealedPayload',
      type: IsarType.string,
    ),
    r'stateKey': PropertySchema(
      id: 2,
      name: r'stateKey',
      type: IsarType.string,
    ),
    r'stateKind': PropertySchema(
      id: 3,
      name: r'stateKind',
      type: IsarType.string,
    ),
  },

  estimateSize: _userContactStateEntityEstimateSize,
  serialize: _userContactStateEntitySerialize,
  deserialize: _userContactStateEntityDeserialize,
  deserializeProp: _userContactStateEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'stateKey': IndexSchema(
      id: 535423888346486579,
      name: r'stateKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'stateKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'ownerCidNumber': IndexSchema(
      id: -7703291541778452577,
      name: r'ownerCidNumber',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'ownerCidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'stateKind': IndexSchema(
      id: 5233811905841789300,
      name: r'stateKind',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'stateKind',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _userContactStateEntityGetId,
  getLinks: _userContactStateEntityGetLinks,
  attach: _userContactStateEntityAttach,
  version: '3.3.2',
);

int _userContactStateEntityEstimateSize(
  UserContactStateEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.ownerCidNumber.length * 3;
  bytesCount += 3 + object.sealedPayload.length * 3;
  bytesCount += 3 + object.stateKey.length * 3;
  bytesCount += 3 + object.stateKind.length * 3;
  return bytesCount;
}

void _userContactStateEntitySerialize(
  UserContactStateEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.ownerCidNumber);
  writer.writeString(offsets[1], object.sealedPayload);
  writer.writeString(offsets[2], object.stateKey);
  writer.writeString(offsets[3], object.stateKind);
}

UserContactStateEntity _userContactStateEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = UserContactStateEntity();
  object.id = id;
  object.ownerCidNumber = reader.readString(offsets[0]);
  object.sealedPayload = reader.readString(offsets[1]);
  object.stateKey = reader.readString(offsets[2]);
  object.stateKind = reader.readString(offsets[3]);
  return object;
}

P _userContactStateEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userContactStateEntityGetId(UserContactStateEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userContactStateEntityGetLinks(
  UserContactStateEntity object,
) {
  return [];
}

void _userContactStateEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  UserContactStateEntity object,
) {
  object.id = id;
}

extension UserContactStateEntityByIndex
    on IsarCollection<UserContactStateEntity> {
  Future<UserContactStateEntity?> getByStateKey(String stateKey) {
    return getByIndex(r'stateKey', [stateKey]);
  }

  UserContactStateEntity? getByStateKeySync(String stateKey) {
    return getByIndexSync(r'stateKey', [stateKey]);
  }

  Future<bool> deleteByStateKey(String stateKey) {
    return deleteByIndex(r'stateKey', [stateKey]);
  }

  bool deleteByStateKeySync(String stateKey) {
    return deleteByIndexSync(r'stateKey', [stateKey]);
  }

  Future<List<UserContactStateEntity?>> getAllByStateKey(
    List<String> stateKeyValues,
  ) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'stateKey', values);
  }

  List<UserContactStateEntity?> getAllByStateKeySync(
    List<String> stateKeyValues,
  ) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'stateKey', values);
  }

  Future<int> deleteAllByStateKey(List<String> stateKeyValues) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'stateKey', values);
  }

  int deleteAllByStateKeySync(List<String> stateKeyValues) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'stateKey', values);
  }

  Future<Id> putByStateKey(UserContactStateEntity object) {
    return putByIndex(r'stateKey', object);
  }

  Id putByStateKeySync(UserContactStateEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'stateKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByStateKey(List<UserContactStateEntity> objects) {
    return putAllByIndex(r'stateKey', objects);
  }

  List<Id> putAllByStateKeySync(
    List<UserContactStateEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'stateKey', objects, saveLinks: saveLinks);
  }
}

extension UserContactStateEntityQueryWhereSort
    on QueryBuilder<UserContactStateEntity, UserContactStateEntity, QWhere> {
  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension UserContactStateEntityQueryWhere
    on
        QueryBuilder<
          UserContactStateEntity,
          UserContactStateEntity,
          QWhereClause
        > {
  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  stateKeyEqualTo(String stateKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'stateKey', value: [stateKey]),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  stateKeyNotEqualTo(String stateKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKey',
                lower: [],
                upper: [stateKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKey',
                lower: [stateKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKey',
                lower: [stateKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKey',
                lower: [],
                upper: [stateKey],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  ownerCidNumberEqualTo(String ownerCidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'ownerCidNumber',
          value: [ownerCidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  ownerCidNumberNotEqualTo(String ownerCidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ownerCidNumber',
                lower: [],
                upper: [ownerCidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ownerCidNumber',
                lower: [ownerCidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ownerCidNumber',
                lower: [ownerCidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ownerCidNumber',
                lower: [],
                upper: [ownerCidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  stateKindEqualTo(String stateKind) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'stateKind', value: [stateKind]),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterWhereClause
  >
  stateKindNotEqualTo(String stateKind) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKind',
                lower: [],
                upper: [stateKind],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKind',
                lower: [stateKind],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKind',
                lower: [stateKind],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'stateKind',
                lower: [],
                upper: [stateKind],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension UserContactStateEntityQueryFilter
    on
        QueryBuilder<
          UserContactStateEntity,
          UserContactStateEntity,
          QFilterCondition
        > {
  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'ownerCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'ownerCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'ownerCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'ownerCidNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'ownerCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'ownerCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'ownerCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'ownerCidNumber',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'ownerCidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  ownerCidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'ownerCidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sealedPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sealedPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sealedPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sealedPayload',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sealedPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sealedPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sealedPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sealedPayload',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sealedPayload', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  sealedPayloadIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sealedPayload', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'stateKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'stateKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'stateKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'stateKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'stateKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'stateKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'stateKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'stateKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'stateKey', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'stateKey', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'stateKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'stateKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'stateKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'stateKind',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'stateKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'stateKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'stateKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'stateKind',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'stateKind', value: ''),
      );
    });
  }

  QueryBuilder<
    UserContactStateEntity,
    UserContactStateEntity,
    QAfterFilterCondition
  >
  stateKindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'stateKind', value: ''),
      );
    });
  }
}

extension UserContactStateEntityQueryObject
    on
        QueryBuilder<
          UserContactStateEntity,
          UserContactStateEntity,
          QFilterCondition
        > {}

extension UserContactStateEntityQueryLinks
    on
        QueryBuilder<
          UserContactStateEntity,
          UserContactStateEntity,
          QFilterCondition
        > {}

extension UserContactStateEntityQuerySortBy
    on QueryBuilder<UserContactStateEntity, UserContactStateEntity, QSortBy> {
  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortByOwnerCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerCidNumber', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortByOwnerCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerCidNumber', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortBySealedPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sealedPayload', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortBySealedPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sealedPayload', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortByStateKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKind', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  sortByStateKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKind', Sort.desc);
    });
  }
}

extension UserContactStateEntityQuerySortThenBy
    on
        QueryBuilder<
          UserContactStateEntity,
          UserContactStateEntity,
          QSortThenBy
        > {
  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByOwnerCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerCidNumber', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByOwnerCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerCidNumber', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenBySealedPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sealedPayload', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenBySealedPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sealedPayload', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByStateKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKind', Sort.asc);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QAfterSortBy>
  thenByStateKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKind', Sort.desc);
    });
  }
}

extension UserContactStateEntityQueryWhereDistinct
    on QueryBuilder<UserContactStateEntity, UserContactStateEntity, QDistinct> {
  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QDistinct>
  distinctByOwnerCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'ownerCidNumber',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QDistinct>
  distinctBySealedPayload({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'sealedPayload',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QDistinct>
  distinctByStateKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stateKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<UserContactStateEntity, UserContactStateEntity, QDistinct>
  distinctByStateKind({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stateKind', caseSensitive: caseSensitive);
    });
  }
}

extension UserContactStateEntityQueryProperty
    on
        QueryBuilder<
          UserContactStateEntity,
          UserContactStateEntity,
          QQueryProperty
        > {
  QueryBuilder<UserContactStateEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<UserContactStateEntity, String, QQueryOperations>
  ownerCidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ownerCidNumber');
    });
  }

  QueryBuilder<UserContactStateEntity, String, QQueryOperations>
  sealedPayloadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sealedPayload');
    });
  }

  QueryBuilder<UserContactStateEntity, String, QQueryOperations>
  stateKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stateKey');
    });
  }

  QueryBuilder<UserContactStateEntity, String, QQueryOperations>
  stateKindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stateKind');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserSettingsEntityCollection on Isar {
  IsarCollection<UserSettingsEntity> get userSettingsEntitys =>
      this.collection();
}

const UserSettingsEntitySchema = CollectionSchema(
  name: r'UserSettingsEntity',
  id: 5073917152494840320,
  properties: {
    r'governanceProvincialBankOrder': PropertySchema(
      id: 0,
      name: r'governanceProvincialBankOrder',
      type: IsarType.stringList,
    ),
    r'governanceProvincialCouncilOrder': PropertySchema(
      id: 1,
      name: r'governanceProvincialCouncilOrder',
      type: IsarType.stringList,
    ),
    r'openChatOnLaunch': PropertySchema(
      id: 2,
      name: r'openChatOnLaunch',
      type: IsarType.bool,
    ),
    r'permissionGuideSeen': PropertySchema(
      id: 3,
      name: r'permissionGuideSeen',
      type: IsarType.bool,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 4,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _userSettingsEntityEstimateSize,
  serialize: _userSettingsEntitySerialize,
  deserialize: _userSettingsEntityDeserialize,
  deserializeProp: _userSettingsEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _userSettingsEntityGetId,
  getLinks: _userSettingsEntityGetLinks,
  attach: _userSettingsEntityAttach,
  version: '3.3.2',
);

int _userSettingsEntityEstimateSize(
  UserSettingsEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.governanceProvincialBankOrder.length * 3;
  {
    for (var i = 0; i < object.governanceProvincialBankOrder.length; i++) {
      final value = object.governanceProvincialBankOrder[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.governanceProvincialCouncilOrder.length * 3;
  {
    for (var i = 0; i < object.governanceProvincialCouncilOrder.length; i++) {
      final value = object.governanceProvincialCouncilOrder[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _userSettingsEntitySerialize(
  UserSettingsEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeStringList(offsets[0], object.governanceProvincialBankOrder);
  writer.writeStringList(offsets[1], object.governanceProvincialCouncilOrder);
  writer.writeBool(offsets[2], object.openChatOnLaunch);
  writer.writeBool(offsets[3], object.permissionGuideSeen);
  writer.writeLong(offsets[4], object.updatedAtMillis);
}

UserSettingsEntity _userSettingsEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = UserSettingsEntity();
  object.governanceProvincialBankOrder =
      reader.readStringList(offsets[0]) ?? [];
  object.governanceProvincialCouncilOrder =
      reader.readStringList(offsets[1]) ?? [];
  object.id = id;
  object.openChatOnLaunch = reader.readBool(offsets[2]);
  object.permissionGuideSeen = reader.readBool(offsets[3]);
  object.updatedAtMillis = reader.readLong(offsets[4]);
  return object;
}

P _userSettingsEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringList(offset) ?? []) as P;
    case 1:
      return (reader.readStringList(offset) ?? []) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userSettingsEntityGetId(UserSettingsEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userSettingsEntityGetLinks(
  UserSettingsEntity object,
) {
  return [];
}

void _userSettingsEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  UserSettingsEntity object,
) {
  object.id = id;
}

extension UserSettingsEntityQueryWhereSort
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QWhere> {
  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension UserSettingsEntityQueryWhere
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QWhereClause> {
  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterWhereClause>
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterWhereClause>
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterWhereClause>
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterWhereClause>
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterWhereClause>
  idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension UserSettingsEntityQueryFilter
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QFilterCondition> {
  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'governanceProvincialBankOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'governanceProvincialBankOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'governanceProvincialBankOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'governanceProvincialBankOrder',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'governanceProvincialBankOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'governanceProvincialBankOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'governanceProvincialBankOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'governanceProvincialBankOrder',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'governanceProvincialBankOrder',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'governanceProvincialBankOrder',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialBankOrder',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialBankOrder',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialBankOrder',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialBankOrder',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialBankOrder',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialBankOrderLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialBankOrder',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'governanceProvincialCouncilOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'governanceProvincialCouncilOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'governanceProvincialCouncilOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'governanceProvincialCouncilOrder',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'governanceProvincialCouncilOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'governanceProvincialCouncilOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'governanceProvincialCouncilOrder',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'governanceProvincialCouncilOrder',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'governanceProvincialCouncilOrder',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'governanceProvincialCouncilOrder',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialCouncilOrder',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialCouncilOrder',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialCouncilOrder',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialCouncilOrder',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialCouncilOrder',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  governanceProvincialCouncilOrderLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'governanceProvincialCouncilOrder',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  openChatOnLaunchEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'openChatOnLaunch', value: value),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  permissionGuideSeenEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'permissionGuideSeen', value: value),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  updatedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  updatedAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  updatedAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterFilterCondition>
  updatedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension UserSettingsEntityQueryObject
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QFilterCondition> {}

extension UserSettingsEntityQueryLinks
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QFilterCondition> {}

extension UserSettingsEntityQuerySortBy
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QSortBy> {
  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  sortByOpenChatOnLaunch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'openChatOnLaunch', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  sortByOpenChatOnLaunchDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'openChatOnLaunch', Sort.desc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  sortByPermissionGuideSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'permissionGuideSeen', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  sortByPermissionGuideSeenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'permissionGuideSeen', Sort.desc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension UserSettingsEntityQuerySortThenBy
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QSortThenBy> {
  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByOpenChatOnLaunch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'openChatOnLaunch', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByOpenChatOnLaunchDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'openChatOnLaunch', Sort.desc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByPermissionGuideSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'permissionGuideSeen', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByPermissionGuideSeenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'permissionGuideSeen', Sort.desc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QAfterSortBy>
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension UserSettingsEntityQueryWhereDistinct
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QDistinct> {
  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QDistinct>
  distinctByGovernanceProvincialBankOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'governanceProvincialBankOrder');
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QDistinct>
  distinctByGovernanceProvincialCouncilOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'governanceProvincialCouncilOrder');
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QDistinct>
  distinctByOpenChatOnLaunch() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'openChatOnLaunch');
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QDistinct>
  distinctByPermissionGuideSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'permissionGuideSeen');
    });
  }

  QueryBuilder<UserSettingsEntity, UserSettingsEntity, QDistinct>
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension UserSettingsEntityQueryProperty
    on QueryBuilder<UserSettingsEntity, UserSettingsEntity, QQueryProperty> {
  QueryBuilder<UserSettingsEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<UserSettingsEntity, List<String>, QQueryOperations>
  governanceProvincialBankOrderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'governanceProvincialBankOrder');
    });
  }

  QueryBuilder<UserSettingsEntity, List<String>, QQueryOperations>
  governanceProvincialCouncilOrderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'governanceProvincialCouncilOrder');
    });
  }

  QueryBuilder<UserSettingsEntity, bool, QQueryOperations>
  openChatOnLaunchProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'openChatOnLaunch');
    });
  }

  QueryBuilder<UserSettingsEntity, bool, QQueryOperations>
  permissionGuideSeenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'permissionGuideSeen');
    });
  }

  QueryBuilder<UserSettingsEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserPublicInstitutionSubscriptionEntityCollection on Isar {
  IsarCollection<UserPublicInstitutionSubscriptionEntity>
  get userPublicInstitutionSubscriptionEntitys => this.collection();
}

const UserPublicInstitutionSubscriptionEntitySchema = CollectionSchema(
  name: r'UserPublicInstitutionSubscriptionEntity',
  id: 3567225888220971213,
  properties: {
    r'institutionCidNumber': PropertySchema(
      id: 0,
      name: r'institutionCidNumber',
      type: IsarType.string,
    ),
    r'subscribedAtMillis': PropertySchema(
      id: 1,
      name: r'subscribedAtMillis',
      type: IsarType.long,
    ),
    r'subscriberCidNumber': PropertySchema(
      id: 2,
      name: r'subscriberCidNumber',
      type: IsarType.string,
    ),
    r'subscriptionKey': PropertySchema(
      id: 3,
      name: r'subscriptionKey',
      type: IsarType.string,
    ),
  },

  estimateSize: _userPublicInstitutionSubscriptionEntityEstimateSize,
  serialize: _userPublicInstitutionSubscriptionEntitySerialize,
  deserialize: _userPublicInstitutionSubscriptionEntityDeserialize,
  deserializeProp: _userPublicInstitutionSubscriptionEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'subscriptionKey': IndexSchema(
      id: -3021161140690889130,
      name: r'subscriptionKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'subscriptionKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'subscriberCidNumber': IndexSchema(
      id: -7606147423943542076,
      name: r'subscriberCidNumber',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'subscriberCidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _userPublicInstitutionSubscriptionEntityGetId,
  getLinks: _userPublicInstitutionSubscriptionEntityGetLinks,
  attach: _userPublicInstitutionSubscriptionEntityAttach,
  version: '3.3.2',
);

int _userPublicInstitutionSubscriptionEntityEstimateSize(
  UserPublicInstitutionSubscriptionEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.institutionCidNumber.length * 3;
  bytesCount += 3 + object.subscriberCidNumber.length * 3;
  bytesCount += 3 + object.subscriptionKey.length * 3;
  return bytesCount;
}

void _userPublicInstitutionSubscriptionEntitySerialize(
  UserPublicInstitutionSubscriptionEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.institutionCidNumber);
  writer.writeLong(offsets[1], object.subscribedAtMillis);
  writer.writeString(offsets[2], object.subscriberCidNumber);
  writer.writeString(offsets[3], object.subscriptionKey);
}

UserPublicInstitutionSubscriptionEntity
_userPublicInstitutionSubscriptionEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = UserPublicInstitutionSubscriptionEntity();
  object.id = id;
  object.institutionCidNumber = reader.readString(offsets[0]);
  object.subscribedAtMillis = reader.readLong(offsets[1]);
  object.subscriberCidNumber = reader.readString(offsets[2]);
  object.subscriptionKey = reader.readString(offsets[3]);
  return object;
}

P _userPublicInstitutionSubscriptionEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userPublicInstitutionSubscriptionEntityGetId(
  UserPublicInstitutionSubscriptionEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userPublicInstitutionSubscriptionEntityGetLinks(
  UserPublicInstitutionSubscriptionEntity object,
) {
  return [];
}

void _userPublicInstitutionSubscriptionEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  UserPublicInstitutionSubscriptionEntity object,
) {
  object.id = id;
}

extension UserPublicInstitutionSubscriptionEntityByIndex
    on IsarCollection<UserPublicInstitutionSubscriptionEntity> {
  Future<UserPublicInstitutionSubscriptionEntity?> getBySubscriptionKey(
    String subscriptionKey,
  ) {
    return getByIndex(r'subscriptionKey', [subscriptionKey]);
  }

  UserPublicInstitutionSubscriptionEntity? getBySubscriptionKeySync(
    String subscriptionKey,
  ) {
    return getByIndexSync(r'subscriptionKey', [subscriptionKey]);
  }

  Future<bool> deleteBySubscriptionKey(String subscriptionKey) {
    return deleteByIndex(r'subscriptionKey', [subscriptionKey]);
  }

  bool deleteBySubscriptionKeySync(String subscriptionKey) {
    return deleteByIndexSync(r'subscriptionKey', [subscriptionKey]);
  }

  Future<List<UserPublicInstitutionSubscriptionEntity?>>
  getAllBySubscriptionKey(List<String> subscriptionKeyValues) {
    final values = subscriptionKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'subscriptionKey', values);
  }

  List<UserPublicInstitutionSubscriptionEntity?> getAllBySubscriptionKeySync(
    List<String> subscriptionKeyValues,
  ) {
    final values = subscriptionKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'subscriptionKey', values);
  }

  Future<int> deleteAllBySubscriptionKey(List<String> subscriptionKeyValues) {
    final values = subscriptionKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'subscriptionKey', values);
  }

  int deleteAllBySubscriptionKeySync(List<String> subscriptionKeyValues) {
    final values = subscriptionKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'subscriptionKey', values);
  }

  Future<Id> putBySubscriptionKey(
    UserPublicInstitutionSubscriptionEntity object,
  ) {
    return putByIndex(r'subscriptionKey', object);
  }

  Id putBySubscriptionKeySync(
    UserPublicInstitutionSubscriptionEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'subscriptionKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySubscriptionKey(
    List<UserPublicInstitutionSubscriptionEntity> objects,
  ) {
    return putAllByIndex(r'subscriptionKey', objects);
  }

  List<Id> putAllBySubscriptionKeySync(
    List<UserPublicInstitutionSubscriptionEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'subscriptionKey', objects, saveLinks: saveLinks);
  }
}

extension UserPublicInstitutionSubscriptionEntityQueryWhereSort
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QWhere
        > {
  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension UserPublicInstitutionSubscriptionEntityQueryWhere
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QWhereClause
        > {
  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  subscriptionKeyEqualTo(String subscriptionKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'subscriptionKey',
          value: [subscriptionKey],
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  subscriptionKeyNotEqualTo(String subscriptionKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriptionKey',
                lower: [],
                upper: [subscriptionKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriptionKey',
                lower: [subscriptionKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriptionKey',
                lower: [subscriptionKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriptionKey',
                lower: [],
                upper: [subscriptionKey],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  subscriberCidNumberEqualTo(String subscriberCidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'subscriberCidNumber',
          value: [subscriberCidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterWhereClause
  >
  subscriberCidNumberNotEqualTo(String subscriberCidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriberCidNumber',
                lower: [],
                upper: [subscriberCidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriberCidNumber',
                lower: [subscriberCidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriberCidNumber',
                lower: [subscriberCidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'subscriberCidNumber',
                lower: [],
                upper: [subscriberCidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension UserPublicInstitutionSubscriptionEntityQueryFilter
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QFilterCondition
        > {
  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'institutionCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'institutionCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'institutionCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'institutionCidNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'institutionCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'institutionCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'institutionCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'institutionCidNumber',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'institutionCidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  institutionCidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'institutionCidNumber',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscribedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'subscribedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscribedAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'subscribedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscribedAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'subscribedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscribedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'subscribedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'subscriberCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'subscriberCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'subscriberCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'subscriberCidNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'subscriberCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'subscriberCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'subscriberCidNumber',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'subscriberCidNumber',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'subscriberCidNumber', value: ''),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriberCidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'subscriberCidNumber',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'subscriptionKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'subscriptionKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'subscriptionKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'subscriptionKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'subscriptionKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'subscriptionKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'subscriptionKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'subscriptionKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'subscriptionKey', value: ''),
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterFilterCondition
  >
  subscriptionKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'subscriptionKey', value: ''),
      );
    });
  }
}

extension UserPublicInstitutionSubscriptionEntityQueryObject
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QFilterCondition
        > {}

extension UserPublicInstitutionSubscriptionEntityQueryLinks
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QFilterCondition
        > {}

extension UserPublicInstitutionSubscriptionEntityQuerySortBy
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QSortBy
        > {
  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortByInstitutionCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortByInstitutionCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortBySubscribedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscribedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortBySubscribedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscribedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortBySubscriberCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriberCidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortBySubscriberCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriberCidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortBySubscriptionKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriptionKey', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  sortBySubscriptionKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriptionKey', Sort.desc);
    });
  }
}

extension UserPublicInstitutionSubscriptionEntityQuerySortThenBy
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QSortThenBy
        > {
  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenByInstitutionCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenByInstitutionCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenBySubscribedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscribedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenBySubscribedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscribedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenBySubscriberCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriberCidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenBySubscriberCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriberCidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenBySubscriptionKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriptionKey', Sort.asc);
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QAfterSortBy
  >
  thenBySubscriptionKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subscriptionKey', Sort.desc);
    });
  }
}

extension UserPublicInstitutionSubscriptionEntityQueryWhereDistinct
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QDistinct
        > {
  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QDistinct
  >
  distinctByInstitutionCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'institutionCidNumber',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QDistinct
  >
  distinctBySubscribedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subscribedAtMillis');
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QDistinct
  >
  distinctBySubscriberCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'subscriberCidNumber',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    UserPublicInstitutionSubscriptionEntity,
    QDistinct
  >
  distinctBySubscriptionKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'subscriptionKey',
        caseSensitive: caseSensitive,
      );
    });
  }
}

extension UserPublicInstitutionSubscriptionEntityQueryProperty
    on
        QueryBuilder<
          UserPublicInstitutionSubscriptionEntity,
          UserPublicInstitutionSubscriptionEntity,
          QQueryProperty
        > {
  QueryBuilder<UserPublicInstitutionSubscriptionEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    String,
    QQueryOperations
  >
  institutionCidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'institutionCidNumber');
    });
  }

  QueryBuilder<UserPublicInstitutionSubscriptionEntity, int, QQueryOperations>
  subscribedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subscribedAtMillis');
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    String,
    QQueryOperations
  >
  subscriberCidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subscriberCidNumber');
    });
  }

  QueryBuilder<
    UserPublicInstitutionSubscriptionEntity,
    String,
    QQueryOperations
  >
  subscriptionKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subscriptionKey');
    });
  }
}
