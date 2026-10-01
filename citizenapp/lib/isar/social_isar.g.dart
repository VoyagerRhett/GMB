// GENERATED CODE - DO NOT MODIFY BY HAND
// 由 social_isar.dart 生成广场集合、序列化与索引查询；媒体归属和完整性由业务入口校验。

part of 'social_isar.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSquareLocalPostEntityCollection on Isar {
  IsarCollection<SquareLocalPostEntity> get squareLocalPostEntitys =>
      this.collection();
}

const SquareLocalPostEntitySchema = CollectionSchema(
  name: r'SquareLocalPostEntity',
  id: 3392182366809581442,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'chainBlock': PropertySchema(
      id: 1,
      name: r'chainBlock',
      type: IsarType.long,
    ),
    r'cidNumber': PropertySchema(
      id: 2,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'contentHash': PropertySchema(
      id: 3,
      name: r'contentHash',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 4,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'manifestBytes': PropertySchema(
      id: 5,
      name: r'manifestBytes',
      type: IsarType.byteList,
    ),
    r'postCategory': PropertySchema(
      id: 6,
      name: r'postCategory',
      type: IsarType.string,
    ),
    r'postId': PropertySchema(
      id: 7,
      name: r'postId',
      type: IsarType.string,
    ),
    r'postState': PropertySchema(
      id: 8,
      name: r'postState',
      type: IsarType.string,
    ),
    r'postType': PropertySchema(
      id: 9,
      name: r'postType',
      type: IsarType.string,
    ),
    r'storageReceiptId': PropertySchema(
      id: 10,
      name: r'storageReceiptId',
      type: IsarType.string,
    )
  },
  estimateSize: _squareLocalPostEntityEstimateSize,
  serialize: _squareLocalPostEntitySerialize,
  deserialize: _squareLocalPostEntityDeserialize,
  deserializeProp: _squareLocalPostEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'postId': IndexSchema(
      id: -544810920068516617,
      name: r'postId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'postId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
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
        )
      ],
    ),
    r'createdAt': IndexSchema(
      id: -3433535483987302584,
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _squareLocalPostEntityGetId,
  getLinks: _squareLocalPostEntityGetLinks,
  attach: _squareLocalPostEntityAttach,
  version: '3.3.2',
);

int _squareLocalPostEntityEstimateSize(
  SquareLocalPostEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.contentHash.length * 3;
  bytesCount += 3 + object.manifestBytes.length;
  bytesCount += 3 + object.postCategory.length * 3;
  bytesCount += 3 + object.postId.length * 3;
  bytesCount += 3 + object.postState.length * 3;
  bytesCount += 3 + object.postType.length * 3;
  bytesCount += 3 + object.storageReceiptId.length * 3;
  return bytesCount;
}

void _squareLocalPostEntitySerialize(
  SquareLocalPostEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeLong(offsets[1], object.chainBlock);
  writer.writeString(offsets[2], object.cidNumber);
  writer.writeString(offsets[3], object.contentHash);
  writer.writeLong(offsets[4], object.createdAt);
  writer.writeByteList(offsets[5], object.manifestBytes);
  writer.writeString(offsets[6], object.postCategory);
  writer.writeString(offsets[7], object.postId);
  writer.writeString(offsets[8], object.postState);
  writer.writeString(offsets[9], object.postType);
  writer.writeString(offsets[10], object.storageReceiptId);
}

SquareLocalPostEntity _squareLocalPostEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquareLocalPostEntity();
  object.accountId = reader.readString(offsets[0]);
  object.chainBlock = reader.readLongOrNull(offsets[1]);
  object.cidNumber = reader.readString(offsets[2]);
  object.contentHash = reader.readString(offsets[3]);
  object.createdAt = reader.readLong(offsets[4]);
  object.id = id;
  object.manifestBytes = reader.readByteList(offsets[5]) ?? [];
  object.postCategory = reader.readString(offsets[6]);
  object.postId = reader.readString(offsets[7]);
  object.postState = reader.readString(offsets[8]);
  object.postType = reader.readString(offsets[9]);
  object.storageReceiptId = reader.readString(offsets[10]);
  return object;
}

P _squareLocalPostEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLongOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readByteList(offset) ?? []) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squareLocalPostEntityGetId(SquareLocalPostEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squareLocalPostEntityGetLinks(
    SquareLocalPostEntity object) {
  return [];
}

void _squareLocalPostEntityAttach(
    IsarCollection<dynamic> col, Id id, SquareLocalPostEntity object) {
  object.id = id;
}

extension SquareLocalPostEntityByIndex
    on IsarCollection<SquareLocalPostEntity> {
  Future<SquareLocalPostEntity?> getByPostId(String postId) {
    return getByIndex(r'postId', [postId]);
  }

  SquareLocalPostEntity? getByPostIdSync(String postId) {
    return getByIndexSync(r'postId', [postId]);
  }

  Future<bool> deleteByPostId(String postId) {
    return deleteByIndex(r'postId', [postId]);
  }

  bool deleteByPostIdSync(String postId) {
    return deleteByIndexSync(r'postId', [postId]);
  }

  Future<List<SquareLocalPostEntity?>> getAllByPostId(
      List<String> postIdValues) {
    final values = postIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'postId', values);
  }

  List<SquareLocalPostEntity?> getAllByPostIdSync(List<String> postIdValues) {
    final values = postIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'postId', values);
  }

  Future<int> deleteAllByPostId(List<String> postIdValues) {
    final values = postIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'postId', values);
  }

  int deleteAllByPostIdSync(List<String> postIdValues) {
    final values = postIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'postId', values);
  }

  Future<Id> putByPostId(SquareLocalPostEntity object) {
    return putByIndex(r'postId', object);
  }

  Id putByPostIdSync(SquareLocalPostEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'postId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPostId(List<SquareLocalPostEntity> objects) {
    return putAllByIndex(r'postId', objects);
  }

  List<Id> putAllByPostIdSync(List<SquareLocalPostEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'postId', objects, saveLinks: saveLinks);
  }
}

extension SquareLocalPostEntityQueryWhereSort
    on QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QWhere> {
  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhere>
      anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }
}

extension SquareLocalPostEntityQueryWhere on QueryBuilder<SquareLocalPostEntity,
    SquareLocalPostEntity, QWhereClause> {
  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
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

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      postIdEqualTo(String postId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'postId',
        value: [postId],
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      postIdNotEqualTo(String postId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'postId',
              lower: [],
              upper: [postId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'postId',
              lower: [postId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'postId',
              lower: [postId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'postId',
              lower: [],
              upper: [postId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      cidNumberEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cidNumber',
        value: [cidNumber],
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      cidNumberNotEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      createdAtEqualTo(int createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      createdAtNotEqualTo(int createdAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      createdAtGreaterThan(
    int createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [createdAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      createdAtLessThan(
    int createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [],
        upper: [createdAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterWhereClause>
      createdAtBetween(
    int lowerCreatedAt,
    int upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [lowerCreatedAt],
        includeLower: includeLower,
        upper: [upperCreatedAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension SquareLocalPostEntityQueryFilter on QueryBuilder<
    SquareLocalPostEntity, SquareLocalPostEntity, QFilterCondition> {
  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'accountId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      accountIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      accountIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'accountId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'accountId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> accountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'accountId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> chainBlockIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'chainBlock',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> chainBlockIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'chainBlock',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> chainBlockEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'chainBlock',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> chainBlockGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'chainBlock',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> chainBlockLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'chainBlock',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> chainBlockBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'chainBlock',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cidNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      cidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      cidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cidNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contentHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contentHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contentHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contentHash',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contentHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contentHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      contentHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contentHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      contentHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contentHash',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contentHash',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> contentHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contentHash',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> createdAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> createdAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> createdAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> createdAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'manifestBytes',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'manifestBytes',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'manifestBytes',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'manifestBytes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> manifestBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'postCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'postCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'postCategory',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'postCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'postCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postCategoryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'postCategory',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postCategoryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'postCategory',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postCategory',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postCategoryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'postCategory',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'postId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'postId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'postId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'postId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'postId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'postId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'postId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'postId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'postState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'postState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'postState',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'postState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'postState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postStateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'postState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postStateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'postState',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postState',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postStateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'postState',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'postType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      postTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'postType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postType',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> postTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'postType',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'storageReceiptId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'storageReceiptId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'storageReceiptId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'storageReceiptId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'storageReceiptId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'storageReceiptId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      storageReceiptIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'storageReceiptId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
          QAfterFilterCondition>
      storageReceiptIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'storageReceiptId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'storageReceiptId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity,
      QAfterFilterCondition> storageReceiptIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'storageReceiptId',
        value: '',
      ));
    });
  }
}

extension SquareLocalPostEntityQueryObject on QueryBuilder<
    SquareLocalPostEntity, SquareLocalPostEntity, QFilterCondition> {}

extension SquareLocalPostEntityQueryLinks on QueryBuilder<SquareLocalPostEntity,
    SquareLocalPostEntity, QFilterCondition> {}

extension SquareLocalPostEntityQuerySortBy
    on QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QSortBy> {
  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByChainBlock() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByChainBlockDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByContentHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByContentHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postState', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postState', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByPostTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByStorageReceiptId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      sortByStorageReceiptIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.desc);
    });
  }
}

extension SquareLocalPostEntityQuerySortThenBy
    on QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QSortThenBy> {
  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByChainBlock() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByChainBlockDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByContentHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByContentHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postState', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postState', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByPostTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.desc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByStorageReceiptId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.asc);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QAfterSortBy>
      thenByStorageReceiptIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.desc);
    });
  }
}

extension SquareLocalPostEntityQueryWhereDistinct
    on QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct> {
  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByChainBlock() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chainBlock');
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByContentHash({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByManifestBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'manifestBytes');
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByPostCategory({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postCategory', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByPostId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByPostState({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postState', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByPostType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareLocalPostEntity, SquareLocalPostEntity, QDistinct>
      distinctByStorageReceiptId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'storageReceiptId',
          caseSensitive: caseSensitive);
    });
  }
}

extension SquareLocalPostEntityQueryProperty on QueryBuilder<
    SquareLocalPostEntity, SquareLocalPostEntity, QQueryProperty> {
  QueryBuilder<SquareLocalPostEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<SquareLocalPostEntity, int?, QQueryOperations>
      chainBlockProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chainBlock');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      contentHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentHash');
    });
  }

  QueryBuilder<SquareLocalPostEntity, int, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<SquareLocalPostEntity, List<int>, QQueryOperations>
      manifestBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'manifestBytes');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      postCategoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postCategory');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      postIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postId');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      postStateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postState');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      postTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postType');
    });
  }

  QueryBuilder<SquareLocalPostEntity, String, QQueryOperations>
      storageReceiptIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'storageReceiptId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSquareComposeDraftEntityCollection on Isar {
  IsarCollection<SquareComposeDraftEntity> get squareComposeDraftEntitys =>
      this.collection();
}

const SquareComposeDraftEntitySchema = CollectionSchema(
  name: r'SquareComposeDraftEntity',
  id: 6833934357716734959,
  properties: {
    r'cidNumber': PropertySchema(
      id: 0,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'contentSectionsJson': PropertySchema(
      id: 1,
      name: r'contentSectionsJson',
      type: IsarType.string,
    ),
    r'draftId': PropertySchema(
      id: 2,
      name: r'draftId',
      type: IsarType.string,
    ),
    r'draftKey': PropertySchema(
      id: 3,
      name: r'draftKey',
      type: IsarType.string,
    ),
    r'mediaJson': PropertySchema(
      id: 4,
      name: r'mediaJson',
      type: IsarType.string,
    ),
    r'postType': PropertySchema(
      id: 5,
      name: r'postType',
      type: IsarType.string,
    ),
    r'text': PropertySchema(
      id: 6,
      name: r'text',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 7,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 8,
      name: r'updatedAtMillis',
      type: IsarType.long,
    )
  },
  estimateSize: _squareComposeDraftEntityEstimateSize,
  serialize: _squareComposeDraftEntitySerialize,
  deserialize: _squareComposeDraftEntityDeserialize,
  deserializeProp: _squareComposeDraftEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'draftKey': IndexSchema(
      id: -6531847789214907499,
      name: r'draftKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'draftKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
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
        )
      ],
    ),
    r'updatedAtMillis': IndexSchema(
      id: -5245432295617068179,
      name: r'updatedAtMillis',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'updatedAtMillis',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _squareComposeDraftEntityGetId,
  getLinks: _squareComposeDraftEntityGetLinks,
  attach: _squareComposeDraftEntityAttach,
  version: '3.3.2',
);

int _squareComposeDraftEntityEstimateSize(
  SquareComposeDraftEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  {
    final value = object.contentSectionsJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.draftId.length * 3;
  bytesCount += 3 + object.draftKey.length * 3;
  bytesCount += 3 + object.mediaJson.length * 3;
  bytesCount += 3 + object.postType.length * 3;
  bytesCount += 3 + object.text.length * 3;
  {
    final value = object.title;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _squareComposeDraftEntitySerialize(
  SquareComposeDraftEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cidNumber);
  writer.writeString(offsets[1], object.contentSectionsJson);
  writer.writeString(offsets[2], object.draftId);
  writer.writeString(offsets[3], object.draftKey);
  writer.writeString(offsets[4], object.mediaJson);
  writer.writeString(offsets[5], object.postType);
  writer.writeString(offsets[6], object.text);
  writer.writeString(offsets[7], object.title);
  writer.writeLong(offsets[8], object.updatedAtMillis);
}

SquareComposeDraftEntity _squareComposeDraftEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquareComposeDraftEntity();
  object.cidNumber = reader.readString(offsets[0]);
  object.contentSectionsJson = reader.readStringOrNull(offsets[1]);
  object.draftId = reader.readString(offsets[2]);
  object.draftKey = reader.readString(offsets[3]);
  object.id = id;
  object.mediaJson = reader.readString(offsets[4]);
  object.postType = reader.readString(offsets[5]);
  object.text = reader.readString(offsets[6]);
  object.title = reader.readStringOrNull(offsets[7]);
  object.updatedAtMillis = reader.readLong(offsets[8]);
  return object;
}

P _squareComposeDraftEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squareComposeDraftEntityGetId(SquareComposeDraftEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squareComposeDraftEntityGetLinks(
    SquareComposeDraftEntity object) {
  return [];
}

void _squareComposeDraftEntityAttach(
    IsarCollection<dynamic> col, Id id, SquareComposeDraftEntity object) {
  object.id = id;
}

extension SquareComposeDraftEntityByIndex
    on IsarCollection<SquareComposeDraftEntity> {
  Future<SquareComposeDraftEntity?> getByDraftKey(String draftKey) {
    return getByIndex(r'draftKey', [draftKey]);
  }

  SquareComposeDraftEntity? getByDraftKeySync(String draftKey) {
    return getByIndexSync(r'draftKey', [draftKey]);
  }

  Future<bool> deleteByDraftKey(String draftKey) {
    return deleteByIndex(r'draftKey', [draftKey]);
  }

  bool deleteByDraftKeySync(String draftKey) {
    return deleteByIndexSync(r'draftKey', [draftKey]);
  }

  Future<List<SquareComposeDraftEntity?>> getAllByDraftKey(
      List<String> draftKeyValues) {
    final values = draftKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'draftKey', values);
  }

  List<SquareComposeDraftEntity?> getAllByDraftKeySync(
      List<String> draftKeyValues) {
    final values = draftKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'draftKey', values);
  }

  Future<int> deleteAllByDraftKey(List<String> draftKeyValues) {
    final values = draftKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'draftKey', values);
  }

  int deleteAllByDraftKeySync(List<String> draftKeyValues) {
    final values = draftKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'draftKey', values);
  }

  Future<Id> putByDraftKey(SquareComposeDraftEntity object) {
    return putByIndex(r'draftKey', object);
  }

  Id putByDraftKeySync(SquareComposeDraftEntity object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'draftKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByDraftKey(List<SquareComposeDraftEntity> objects) {
    return putAllByIndex(r'draftKey', objects);
  }

  List<Id> putAllByDraftKeySync(List<SquareComposeDraftEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'draftKey', objects, saveLinks: saveLinks);
  }
}

extension SquareComposeDraftEntityQueryWhereSort on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QWhere> {
  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterWhere>
      anyUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'updatedAtMillis'),
      );
    });
  }
}

extension SquareComposeDraftEntityQueryWhere on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QWhereClause> {
  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> draftKeyEqualTo(String draftKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'draftKey',
        value: [draftKey],
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> draftKeyNotEqualTo(String draftKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'draftKey',
              lower: [],
              upper: [draftKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'draftKey',
              lower: [draftKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'draftKey',
              lower: [draftKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'draftKey',
              lower: [],
              upper: [draftKey],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> cidNumberEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cidNumber',
        value: [cidNumber],
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> cidNumberNotEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> updatedAtMillisEqualTo(int updatedAtMillis) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'updatedAtMillis',
        value: [updatedAtMillis],
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> updatedAtMillisNotEqualTo(int updatedAtMillis) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAtMillis',
              lower: [],
              upper: [updatedAtMillis],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAtMillis',
              lower: [updatedAtMillis],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAtMillis',
              lower: [updatedAtMillis],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAtMillis',
              lower: [],
              upper: [updatedAtMillis],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> updatedAtMillisGreaterThan(
    int updatedAtMillis, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'updatedAtMillis',
        lower: [updatedAtMillis],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> updatedAtMillisLessThan(
    int updatedAtMillis, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'updatedAtMillis',
        lower: [],
        upper: [updatedAtMillis],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterWhereClause> updatedAtMillisBetween(
    int lowerUpdatedAtMillis,
    int upperUpdatedAtMillis, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'updatedAtMillis',
        lower: [lowerUpdatedAtMillis],
        includeLower: includeLower,
        upper: [upperUpdatedAtMillis],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension SquareComposeDraftEntityQueryFilter on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QFilterCondition> {
  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cidNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      cidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      cidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cidNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'contentSectionsJson',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'contentSectionsJson',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contentSectionsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contentSectionsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contentSectionsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contentSectionsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contentSectionsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contentSectionsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      contentSectionsJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contentSectionsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      contentSectionsJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contentSectionsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contentSectionsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> contentSectionsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contentSectionsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'draftId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      draftIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      draftIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'draftId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draftId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'draftId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draftKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'draftKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'draftKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'draftKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'draftKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'draftKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      draftKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'draftKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      draftKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'draftKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draftKey',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> draftKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'draftKey',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mediaJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mediaJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mediaJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mediaJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'mediaJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'mediaJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      mediaJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'mediaJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      mediaJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'mediaJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mediaJson',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> mediaJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'mediaJson',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'postType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      postTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'postType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      postTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'postType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postType',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> postTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'postType',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'text',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      textContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      textMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'text',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> textIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'text',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'title',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'title',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      titleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
          QAfterFilterCondition>
      titleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> updatedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAtMillis',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> updatedAtMillisGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAtMillis',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> updatedAtMillisLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAtMillis',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity,
      QAfterFilterCondition> updatedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAtMillis',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension SquareComposeDraftEntityQueryObject on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QFilterCondition> {}

extension SquareComposeDraftEntityQueryLinks on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QFilterCondition> {}

extension SquareComposeDraftEntityQuerySortBy on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QSortBy> {
  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByContentSectionsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentSectionsJson', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByContentSectionsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentSectionsJson', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByDraftId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByDraftIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByDraftKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftKey', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByDraftKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftKey', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByMediaJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaJson', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByMediaJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaJson', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByPostType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByPostTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension SquareComposeDraftEntityQuerySortThenBy on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QSortThenBy> {
  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByContentSectionsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentSectionsJson', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByContentSectionsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentSectionsJson', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByDraftId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByDraftIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByDraftKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftKey', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByDraftKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftKey', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByMediaJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaJson', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByMediaJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaJson', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByPostType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByPostTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QAfterSortBy>
      thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension SquareComposeDraftEntityQueryWhereDistinct on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct> {
  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByContentSectionsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentSectionsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByDraftId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'draftId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByDraftKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'draftKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByMediaJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByPostType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByText({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'text', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareComposeDraftEntity, SquareComposeDraftEntity, QDistinct>
      distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension SquareComposeDraftEntityQueryProperty on QueryBuilder<
    SquareComposeDraftEntity, SquareComposeDraftEntity, QQueryProperty> {
  QueryBuilder<SquareComposeDraftEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String, QQueryOperations>
      cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String?, QQueryOperations>
      contentSectionsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentSectionsJson');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String, QQueryOperations>
      draftIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'draftId');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String, QQueryOperations>
      draftKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'draftKey');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String, QQueryOperations>
      mediaJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaJson');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String, QQueryOperations>
      postTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postType');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String, QQueryOperations>
      textProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'text');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, String?, QQueryOperations>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<SquareComposeDraftEntity, int, QQueryOperations>
      updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSquarePostSyncCheckpointEntityCollection on Isar {
  IsarCollection<SquarePostSyncCheckpointEntity>
      get squarePostSyncCheckpointEntitys => this.collection();
}

const SquarePostSyncCheckpointEntitySchema = CollectionSchema(
  name: r'SquarePostSyncCheckpointEntity',
  id: -8272134114827660795,
  properties: {
    r'cidNumber': PropertySchema(
      id: 0,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'newestCreatedAt': PropertySchema(
      id: 1,
      name: r'newestCreatedAt',
      type: IsarType.long,
    ),
    r'newestPostId': PropertySchema(
      id: 2,
      name: r'newestPostId',
      type: IsarType.string,
    )
  },
  estimateSize: _squarePostSyncCheckpointEntityEstimateSize,
  serialize: _squarePostSyncCheckpointEntitySerialize,
  deserialize: _squarePostSyncCheckpointEntityDeserialize,
  deserializeProp: _squarePostSyncCheckpointEntityDeserializeProp,
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
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _squarePostSyncCheckpointEntityGetId,
  getLinks: _squarePostSyncCheckpointEntityGetLinks,
  attach: _squarePostSyncCheckpointEntityAttach,
  version: '3.3.2',
);

int _squarePostSyncCheckpointEntityEstimateSize(
  SquarePostSyncCheckpointEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  {
    final value = object.newestPostId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _squarePostSyncCheckpointEntitySerialize(
  SquarePostSyncCheckpointEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cidNumber);
  writer.writeLong(offsets[1], object.newestCreatedAt);
  writer.writeString(offsets[2], object.newestPostId);
}

SquarePostSyncCheckpointEntity _squarePostSyncCheckpointEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquarePostSyncCheckpointEntity();
  object.cidNumber = reader.readString(offsets[0]);
  object.id = id;
  object.newestCreatedAt = reader.readLong(offsets[1]);
  object.newestPostId = reader.readStringOrNull(offsets[2]);
  return object;
}

P _squarePostSyncCheckpointEntityDeserializeProp<P>(
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
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squarePostSyncCheckpointEntityGetId(SquarePostSyncCheckpointEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squarePostSyncCheckpointEntityGetLinks(
    SquarePostSyncCheckpointEntity object) {
  return [];
}

void _squarePostSyncCheckpointEntityAttach(
    IsarCollection<dynamic> col, Id id, SquarePostSyncCheckpointEntity object) {
  object.id = id;
}

extension SquarePostSyncCheckpointEntityByIndex
    on IsarCollection<SquarePostSyncCheckpointEntity> {
  Future<SquarePostSyncCheckpointEntity?> getByCidNumber(String cidNumber) {
    return getByIndex(r'cidNumber', [cidNumber]);
  }

  SquarePostSyncCheckpointEntity? getByCidNumberSync(String cidNumber) {
    return getByIndexSync(r'cidNumber', [cidNumber]);
  }

  Future<bool> deleteByCidNumber(String cidNumber) {
    return deleteByIndex(r'cidNumber', [cidNumber]);
  }

  bool deleteByCidNumberSync(String cidNumber) {
    return deleteByIndexSync(r'cidNumber', [cidNumber]);
  }

  Future<List<SquarePostSyncCheckpointEntity?>> getAllByCidNumber(
      List<String> cidNumberValues) {
    final values = cidNumberValues.map((e) => [e]).toList();
    return getAllByIndex(r'cidNumber', values);
  }

  List<SquarePostSyncCheckpointEntity?> getAllByCidNumberSync(
      List<String> cidNumberValues) {
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

  Future<Id> putByCidNumber(SquarePostSyncCheckpointEntity object) {
    return putByIndex(r'cidNumber', object);
  }

  Id putByCidNumberSync(SquarePostSyncCheckpointEntity object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'cidNumber', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCidNumber(
      List<SquarePostSyncCheckpointEntity> objects) {
    return putAllByIndex(r'cidNumber', objects);
  }

  List<Id> putAllByCidNumberSync(List<SquarePostSyncCheckpointEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'cidNumber', objects, saveLinks: saveLinks);
  }
}

extension SquarePostSyncCheckpointEntityQueryWhereSort on QueryBuilder<
    SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity, QWhere> {
  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquarePostSyncCheckpointEntityQueryWhere on QueryBuilder<
    SquarePostSyncCheckpointEntity,
    SquarePostSyncCheckpointEntity,
    QWhereClause> {
  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> cidNumberEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cidNumber',
        value: [cidNumber],
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterWhereClause> cidNumberNotEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ));
      }
    });
  }
}

extension SquarePostSyncCheckpointEntityQueryFilter on QueryBuilder<
    SquarePostSyncCheckpointEntity,
    SquarePostSyncCheckpointEntity,
    QFilterCondition> {
  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cidNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
          QAfterFilterCondition>
      cidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
          QAfterFilterCondition>
      cidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cidNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestCreatedAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'newestCreatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestCreatedAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'newestCreatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestCreatedAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'newestCreatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestCreatedAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'newestCreatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'newestPostId',
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'newestPostId',
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'newestPostId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'newestPostId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'newestPostId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'newestPostId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'newestPostId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'newestPostId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
          QAfterFilterCondition>
      newestPostIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'newestPostId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
          QAfterFilterCondition>
      newestPostIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'newestPostId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'newestPostId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterFilterCondition> newestPostIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'newestPostId',
        value: '',
      ));
    });
  }
}

extension SquarePostSyncCheckpointEntityQueryObject on QueryBuilder<
    SquarePostSyncCheckpointEntity,
    SquarePostSyncCheckpointEntity,
    QFilterCondition> {}

extension SquarePostSyncCheckpointEntityQueryLinks on QueryBuilder<
    SquarePostSyncCheckpointEntity,
    SquarePostSyncCheckpointEntity,
    QFilterCondition> {}

extension SquarePostSyncCheckpointEntityQuerySortBy on QueryBuilder<
    SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity, QSortBy> {
  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> sortByNewestCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestCreatedAt', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> sortByNewestCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestCreatedAt', Sort.desc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> sortByNewestPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestPostId', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> sortByNewestPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestPostId', Sort.desc);
    });
  }
}

extension SquarePostSyncCheckpointEntityQuerySortThenBy on QueryBuilder<
    SquarePostSyncCheckpointEntity,
    SquarePostSyncCheckpointEntity,
    QSortThenBy> {
  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByNewestCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestCreatedAt', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByNewestCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestCreatedAt', Sort.desc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByNewestPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestPostId', Sort.asc);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QAfterSortBy> thenByNewestPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'newestPostId', Sort.desc);
    });
  }
}

extension SquarePostSyncCheckpointEntityQueryWhereDistinct on QueryBuilder<
    SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity, QDistinct> {
  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QDistinct> distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QDistinct> distinctByNewestCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'newestCreatedAt');
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, SquarePostSyncCheckpointEntity,
      QDistinct> distinctByNewestPostId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'newestPostId', caseSensitive: caseSensitive);
    });
  }
}

extension SquarePostSyncCheckpointEntityQueryProperty on QueryBuilder<
    SquarePostSyncCheckpointEntity,
    SquarePostSyncCheckpointEntity,
    QQueryProperty> {
  QueryBuilder<SquarePostSyncCheckpointEntity, int, QQueryOperations>
      idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, String, QQueryOperations>
      cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, int, QQueryOperations>
      newestCreatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'newestCreatedAt');
    });
  }

  QueryBuilder<SquarePostSyncCheckpointEntity, String?, QQueryOperations>
      newestPostIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'newestPostId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSquareFileCleanupEntityCollection on Isar {
  IsarCollection<SquareFileCleanupEntity> get squareFileCleanupEntitys =>
      this.collection();
}

const SquareFileCleanupEntitySchema = CollectionSchema(
  name: r'SquareFileCleanupEntity',
  id: -7588075730518139899,
  properties: {
    r'attemptCount': PropertySchema(
      id: 0,
      name: r'attemptCount',
      type: IsarType.long,
    ),
    r'cidNumber': PropertySchema(
      id: 1,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'cleanupKey': PropertySchema(
      id: 2,
      name: r'cleanupKey',
      type: IsarType.string,
    ),
    r'cleanupKind': PropertySchema(
      id: 3,
      name: r'cleanupKind',
      type: IsarType.string,
    ),
    r'createdAtMillis': PropertySchema(
      id: 4,
      name: r'createdAtMillis',
      type: IsarType.long,
    ),
    r'draftId': PropertySchema(
      id: 5,
      name: r'draftId',
      type: IsarType.string,
    ),
    r'lastError': PropertySchema(
      id: 6,
      name: r'lastError',
      type: IsarType.string,
    )
  },
  estimateSize: _squareFileCleanupEntityEstimateSize,
  serialize: _squareFileCleanupEntitySerialize,
  deserialize: _squareFileCleanupEntityDeserialize,
  deserializeProp: _squareFileCleanupEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cleanupKey': IndexSchema(
      id: 58416111559704027,
      name: r'cleanupKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'cleanupKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
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
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _squareFileCleanupEntityGetId,
  getLinks: _squareFileCleanupEntityGetLinks,
  attach: _squareFileCleanupEntityAttach,
  version: '3.3.2',
);

int _squareFileCleanupEntityEstimateSize(
  SquareFileCleanupEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.cleanupKey.length * 3;
  bytesCount += 3 + object.cleanupKind.length * 3;
  bytesCount += 3 + object.draftId.length * 3;
  {
    final value = object.lastError;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _squareFileCleanupEntitySerialize(
  SquareFileCleanupEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.attemptCount);
  writer.writeString(offsets[1], object.cidNumber);
  writer.writeString(offsets[2], object.cleanupKey);
  writer.writeString(offsets[3], object.cleanupKind);
  writer.writeLong(offsets[4], object.createdAtMillis);
  writer.writeString(offsets[5], object.draftId);
  writer.writeString(offsets[6], object.lastError);
}

SquareFileCleanupEntity _squareFileCleanupEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquareFileCleanupEntity();
  object.attemptCount = reader.readLong(offsets[0]);
  object.cidNumber = reader.readString(offsets[1]);
  object.cleanupKey = reader.readString(offsets[2]);
  object.cleanupKind = reader.readString(offsets[3]);
  object.createdAtMillis = reader.readLong(offsets[4]);
  object.draftId = reader.readString(offsets[5]);
  object.id = id;
  object.lastError = reader.readStringOrNull(offsets[6]);
  return object;
}

P _squareFileCleanupEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squareFileCleanupEntityGetId(SquareFileCleanupEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squareFileCleanupEntityGetLinks(
    SquareFileCleanupEntity object) {
  return [];
}

void _squareFileCleanupEntityAttach(
    IsarCollection<dynamic> col, Id id, SquareFileCleanupEntity object) {
  object.id = id;
}

extension SquareFileCleanupEntityByIndex
    on IsarCollection<SquareFileCleanupEntity> {
  Future<SquareFileCleanupEntity?> getByCleanupKey(String cleanupKey) {
    return getByIndex(r'cleanupKey', [cleanupKey]);
  }

  SquareFileCleanupEntity? getByCleanupKeySync(String cleanupKey) {
    return getByIndexSync(r'cleanupKey', [cleanupKey]);
  }

  Future<bool> deleteByCleanupKey(String cleanupKey) {
    return deleteByIndex(r'cleanupKey', [cleanupKey]);
  }

  bool deleteByCleanupKeySync(String cleanupKey) {
    return deleteByIndexSync(r'cleanupKey', [cleanupKey]);
  }

  Future<List<SquareFileCleanupEntity?>> getAllByCleanupKey(
      List<String> cleanupKeyValues) {
    final values = cleanupKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'cleanupKey', values);
  }

  List<SquareFileCleanupEntity?> getAllByCleanupKeySync(
      List<String> cleanupKeyValues) {
    final values = cleanupKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'cleanupKey', values);
  }

  Future<int> deleteAllByCleanupKey(List<String> cleanupKeyValues) {
    final values = cleanupKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'cleanupKey', values);
  }

  int deleteAllByCleanupKeySync(List<String> cleanupKeyValues) {
    final values = cleanupKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'cleanupKey', values);
  }

  Future<Id> putByCleanupKey(SquareFileCleanupEntity object) {
    return putByIndex(r'cleanupKey', object);
  }

  Id putByCleanupKeySync(SquareFileCleanupEntity object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'cleanupKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCleanupKey(List<SquareFileCleanupEntity> objects) {
    return putAllByIndex(r'cleanupKey', objects);
  }

  List<Id> putAllByCleanupKeySync(List<SquareFileCleanupEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'cleanupKey', objects, saveLinks: saveLinks);
  }
}

extension SquareFileCleanupEntityQueryWhereSort
    on QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QWhere> {
  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquareFileCleanupEntityQueryWhere on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QWhereClause> {
  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> cleanupKeyEqualTo(String cleanupKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cleanupKey',
        value: [cleanupKey],
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> cleanupKeyNotEqualTo(String cleanupKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cleanupKey',
              lower: [],
              upper: [cleanupKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cleanupKey',
              lower: [cleanupKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cleanupKey',
              lower: [cleanupKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cleanupKey',
              lower: [],
              upper: [cleanupKey],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> cidNumberEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cidNumber',
        value: [cidNumber],
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterWhereClause> cidNumberNotEqualTo(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [cidNumber],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cidNumber',
              lower: [],
              upper: [cidNumber],
              includeUpper: false,
            ));
      }
    });
  }
}

extension SquareFileCleanupEntityQueryFilter on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QFilterCondition> {
  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> attemptCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attemptCount',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> attemptCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attemptCount',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> attemptCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attemptCount',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> attemptCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attemptCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cidNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      cidNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cidNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      cidNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cidNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cidNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cleanupKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cleanupKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cleanupKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cleanupKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cleanupKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cleanupKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      cleanupKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cleanupKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      cleanupKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cleanupKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cleanupKey',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cleanupKey',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cleanupKind',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cleanupKind',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cleanupKind',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cleanupKind',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cleanupKind',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cleanupKind',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      cleanupKindContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cleanupKind',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      cleanupKindMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cleanupKind',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cleanupKind',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> cleanupKindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cleanupKind',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> createdAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAtMillis',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> createdAtMillisGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAtMillis',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> createdAtMillisLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAtMillis',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> createdAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAtMillis',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'draftId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      draftIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'draftId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      draftIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'draftId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draftId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> draftIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'draftId',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastError',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastError',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastError',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'lastError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'lastError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      lastErrorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'lastError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
          QAfterFilterCondition>
      lastErrorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'lastError',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastError',
        value: '',
      ));
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity,
      QAfterFilterCondition> lastErrorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'lastError',
        value: '',
      ));
    });
  }
}

extension SquareFileCleanupEntityQueryObject on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QFilterCondition> {}

extension SquareFileCleanupEntityQueryLinks on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QFilterCondition> {}

extension SquareFileCleanupEntityQuerySortBy
    on QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QSortBy> {
  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByAttemptCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attemptCount', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByAttemptCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attemptCount', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCleanupKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKey', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCleanupKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKey', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCleanupKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKind', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCleanupKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKind', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByCreatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByDraftId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByDraftIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByLastError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastError', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      sortByLastErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastError', Sort.desc);
    });
  }
}

extension SquareFileCleanupEntityQuerySortThenBy on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QSortThenBy> {
  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByAttemptCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attemptCount', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByAttemptCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attemptCount', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCleanupKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKey', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCleanupKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKey', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCleanupKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKind', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCleanupKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupKind', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByCreatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByDraftId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByDraftIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByLastError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastError', Sort.asc);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QAfterSortBy>
      thenByLastErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastError', Sort.desc);
    });
  }
}

extension SquareFileCleanupEntityQueryWhereDistinct on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct> {
  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByAttemptCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attemptCount');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByCleanupKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cleanupKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByCleanupKind({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cleanupKind', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAtMillis');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByDraftId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'draftId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareFileCleanupEntity, SquareFileCleanupEntity, QDistinct>
      distinctByLastError({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastError', caseSensitive: caseSensitive);
    });
  }
}

extension SquareFileCleanupEntityQueryProperty on QueryBuilder<
    SquareFileCleanupEntity, SquareFileCleanupEntity, QQueryProperty> {
  QueryBuilder<SquareFileCleanupEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, int, QQueryOperations>
      attemptCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attemptCount');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, String, QQueryOperations>
      cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, String, QQueryOperations>
      cleanupKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cleanupKey');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, String, QQueryOperations>
      cleanupKindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cleanupKind');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, int, QQueryOperations>
      createdAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAtMillis');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, String, QQueryOperations>
      draftIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'draftId');
    });
  }

  QueryBuilder<SquareFileCleanupEntity, String?, QQueryOperations>
      lastErrorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastError');
    });
  }
}

extension GetSquareMediaEntityCollection on Isar {
  IsarCollection<SquareMediaEntity> get squareMediaEntitys => this.collection();
}

const SquareMediaEntitySchema = CollectionSchema(
  name: r'SquareMediaEntity',
  id: 6109766792143329361,
  properties: {
    r'byteSize': PropertySchema(id: 0, name: r'byteSize', type: IsarType.long),
    r'cidNumber': PropertySchema(
      id: 1,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'complete': PropertySchema(id: 2, name: r'complete', type: IsarType.bool),
    r'contentType': PropertySchema(
      id: 3,
      name: r'contentType',
      type: IsarType.string,
    ),
    r'mediaId': PropertySchema(id: 4, name: r'mediaId', type: IsarType.string),
    r'mediaKind': PropertySchema(
      id: 5,
      name: r'mediaKind',
      type: IsarType.string,
    ),
    r'sha256': PropertySchema(id: 6, name: r'sha256', type: IsarType.string),
  },

  estimateSize: _squareMediaEntityEstimateSize,
  serialize: _squareMediaEntitySerialize,
  deserialize: _squareMediaEntityDeserialize,
  deserializeProp: _squareMediaEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber_mediaId': IndexSchema(
      id: 3966343169766998025,
      name: r'cidNumber_mediaId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'mediaId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _squareMediaEntityGetId,
  getLinks: _squareMediaEntityGetLinks,
  attach: _squareMediaEntityAttach,
  version: '3.3.2',
);
int _squareMediaEntityEstimateSize(
  SquareMediaEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.contentType.length * 3;
  bytesCount += 3 + object.mediaId.length * 3;
  bytesCount += 3 + object.mediaKind.length * 3;
  bytesCount += 3 + object.sha256.length * 3;
  return bytesCount;
}

void _squareMediaEntitySerialize(
  SquareMediaEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.byteSize);
  writer.writeString(offsets[1], object.cidNumber);
  writer.writeBool(offsets[2], object.complete);
  writer.writeString(offsets[3], object.contentType);
  writer.writeString(offsets[4], object.mediaId);
  writer.writeString(offsets[5], object.mediaKind);
  writer.writeString(offsets[6], object.sha256);
}

SquareMediaEntity _squareMediaEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquareMediaEntity();
  object.byteSize = reader.readLong(offsets[0]);
  object.cidNumber = reader.readString(offsets[1]);
  object.complete = reader.readBool(offsets[2]);
  object.contentType = reader.readString(offsets[3]);
  object.id = id;
  object.mediaId = reader.readString(offsets[4]);
  object.mediaKind = reader.readString(offsets[5]);
  object.sha256 = reader.readString(offsets[6]);
  return object;
}

P _squareMediaEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squareMediaEntityGetId(SquareMediaEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squareMediaEntityGetLinks(
  SquareMediaEntity object,
) {
  return [];
}

void _squareMediaEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  SquareMediaEntity object,
) {
  object.id = id;
}

extension SquareMediaEntityByIndex on IsarCollection<SquareMediaEntity> {
  Future<SquareMediaEntity?> getByCidNumberMediaId(
    String cidNumber,
    String mediaId,
  ) {
    return getByIndex(r'cidNumber_mediaId', [cidNumber, mediaId]);
  }

  SquareMediaEntity? getByCidNumberMediaIdSync(
    String cidNumber,
    String mediaId,
  ) {
    return getByIndexSync(r'cidNumber_mediaId', [cidNumber, mediaId]);
  }

  Future<bool> deleteByCidNumberMediaId(String cidNumber, String mediaId) {
    return deleteByIndex(r'cidNumber_mediaId', [cidNumber, mediaId]);
  }

  bool deleteByCidNumberMediaIdSync(String cidNumber, String mediaId) {
    return deleteByIndexSync(r'cidNumber_mediaId', [cidNumber, mediaId]);
  }

  Future<List<SquareMediaEntity?>> getAllByCidNumberMediaId(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i]]);
    }

    return getAllByIndex(r'cidNumber_mediaId', values);
  }

  List<SquareMediaEntity?> getAllByCidNumberMediaIdSync(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i]]);
    }

    return getAllByIndexSync(r'cidNumber_mediaId', values);
  }

  Future<int> deleteAllByCidNumberMediaId(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i]]);
    }

    return deleteAllByIndex(r'cidNumber_mediaId', values);
  }

  int deleteAllByCidNumberMediaIdSync(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i]]);
    }

    return deleteAllByIndexSync(r'cidNumber_mediaId', values);
  }

  Future<Id> putByCidNumberMediaId(SquareMediaEntity object) {
    return putByIndex(r'cidNumber_mediaId', object);
  }

  Id putByCidNumberMediaIdSync(
    SquareMediaEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'cidNumber_mediaId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCidNumberMediaId(List<SquareMediaEntity> objects) {
    return putAllByIndex(r'cidNumber_mediaId', objects);
  }

  List<Id> putAllByCidNumberMediaIdSync(
    List<SquareMediaEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'cidNumber_mediaId',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension SquareMediaEntityQueryWhereSort
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QWhere> {
  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquareMediaEntityQueryWhere
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QWhereClause> {
  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  cidNumberEqualToAnyMediaId(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_mediaId',
          value: [cidNumber],
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  cidNumberNotEqualToAnyMediaId(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  cidNumberMediaIdEqualTo(String cidNumber, String mediaId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_mediaId',
          value: [cidNumber, mediaId],
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterWhereClause>
  cidNumberEqualToMediaIdNotEqualTo(String cidNumber, String mediaId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [cidNumber],
                upper: [cidNumber, mediaId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [cidNumber, mediaId],
                includeLower: false,
                upper: [cidNumber],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [cidNumber, mediaId],
                includeLower: false,
                upper: [cidNumber],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId',
                lower: [cidNumber],
                upper: [cidNumber, mediaId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension SquareMediaEntityQueryFilter
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QFilterCondition> {
  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  byteSizeEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'byteSize', value: value),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  byteSizeGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'byteSize',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  byteSizeLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'byteSize',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  byteSizeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'byteSize',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  completeEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'complete', value: value),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'contentType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'contentType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'contentType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'contentType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'contentType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'contentType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'contentType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'contentType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'contentType', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  contentTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'contentType', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
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

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mediaId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mediaId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mediaId', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mediaId', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mediaKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mediaKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mediaKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mediaKind',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mediaKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mediaKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mediaKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mediaKind',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mediaKind', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  mediaKindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mediaKind', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256EqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256GreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256LessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256Between(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sha256',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256StartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256EndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256Contains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256Matches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sha256',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256IsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sha256', value: ''),
      );
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterFilterCondition>
  sha256IsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sha256', value: ''),
      );
    });
  }
}

extension SquareMediaEntityQueryObject
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QFilterCondition> {}

extension SquareMediaEntityQueryLinks
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QFilterCondition> {}

extension SquareMediaEntityQuerySortBy
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QSortBy> {
  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByByteSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteSize', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByByteSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteSize', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByComplete() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'complete', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByCompleteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'complete', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByContentType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentType', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByContentTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentType', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByMediaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByMediaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByMediaKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaKind', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortByMediaKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaKind', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortBySha256() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sha256', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  sortBySha256Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sha256', Sort.desc);
    });
  }
}

extension SquareMediaEntityQuerySortThenBy
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QSortThenBy> {
  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByByteSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteSize', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByByteSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteSize', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByComplete() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'complete', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByCompleteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'complete', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByContentType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentType', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByContentTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentType', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByMediaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByMediaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByMediaKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaKind', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenByMediaKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaKind', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenBySha256() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sha256', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QAfterSortBy>
  thenBySha256Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sha256', Sort.desc);
    });
  }
}

extension SquareMediaEntityQueryWhereDistinct
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct> {
  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctByByteSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'byteSize');
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctByComplete() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'complete');
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctByContentType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctByMediaId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctByMediaKind({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaKind', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareMediaEntity, SquareMediaEntity, QDistinct>
  distinctBySha256({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sha256', caseSensitive: caseSensitive);
    });
  }
}

extension SquareMediaEntityQueryProperty
    on QueryBuilder<SquareMediaEntity, SquareMediaEntity, QQueryProperty> {
  QueryBuilder<SquareMediaEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquareMediaEntity, int, QQueryOperations> byteSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'byteSize');
    });
  }

  QueryBuilder<SquareMediaEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquareMediaEntity, bool, QQueryOperations> completeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'complete');
    });
  }

  QueryBuilder<SquareMediaEntity, String, QQueryOperations>
  contentTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentType');
    });
  }

  QueryBuilder<SquareMediaEntity, String, QQueryOperations> mediaIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaId');
    });
  }

  QueryBuilder<SquareMediaEntity, String, QQueryOperations>
  mediaKindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaKind');
    });
  }

  QueryBuilder<SquareMediaEntity, String, QQueryOperations> sha256Property() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sha256');
    });
  }
}

extension GetSquareMediaChunkEntityCollection on Isar {
  IsarCollection<SquareMediaChunkEntity> get squareMediaChunkEntitys =>
      this.collection();
}

const SquareMediaChunkEntitySchema = CollectionSchema(
  name: r'SquareMediaChunkEntity',
  id: -4156534603567877490,
  properties: {
    r'chunkBytes': PropertySchema(
      id: 0,
      name: r'chunkBytes',
      type: IsarType.byteList,
    ),
    r'chunkIndex': PropertySchema(
      id: 1,
      name: r'chunkIndex',
      type: IsarType.long,
    ),
    r'chunkSha256': PropertySchema(
      id: 2,
      name: r'chunkSha256',
      type: IsarType.string,
    ),
    r'cidNumber': PropertySchema(
      id: 3,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'mediaId': PropertySchema(id: 4, name: r'mediaId', type: IsarType.string),
  },

  estimateSize: _squareMediaChunkEntityEstimateSize,
  serialize: _squareMediaChunkEntitySerialize,
  deserialize: _squareMediaChunkEntityDeserialize,
  deserializeProp: _squareMediaChunkEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber_mediaId_chunkIndex': IndexSchema(
      id: -2984211745779613259,
      name: r'cidNumber_mediaId_chunkIndex',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'mediaId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'chunkIndex',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _squareMediaChunkEntityGetId,
  getLinks: _squareMediaChunkEntityGetLinks,
  attach: _squareMediaChunkEntityAttach,
  version: '3.3.2',
);
int _squareMediaChunkEntityEstimateSize(
  SquareMediaChunkEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.chunkBytes.length;
  bytesCount += 3 + object.chunkSha256.length * 3;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.mediaId.length * 3;
  return bytesCount;
}

void _squareMediaChunkEntitySerialize(
  SquareMediaChunkEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeByteList(offsets[0], object.chunkBytes);
  writer.writeLong(offsets[1], object.chunkIndex);
  writer.writeString(offsets[2], object.chunkSha256);
  writer.writeString(offsets[3], object.cidNumber);
  writer.writeString(offsets[4], object.mediaId);
}

SquareMediaChunkEntity _squareMediaChunkEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquareMediaChunkEntity();
  object.chunkBytes = reader.readByteList(offsets[0]) ?? [];
  object.chunkIndex = reader.readLong(offsets[1]);
  object.chunkSha256 = reader.readString(offsets[2]);
  object.cidNumber = reader.readString(offsets[3]);
  object.id = id;
  object.mediaId = reader.readString(offsets[4]);
  return object;
}

P _squareMediaChunkEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readByteList(offset) ?? []) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squareMediaChunkEntityGetId(SquareMediaChunkEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squareMediaChunkEntityGetLinks(
  SquareMediaChunkEntity object,
) {
  return [];
}

void _squareMediaChunkEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  SquareMediaChunkEntity object,
) {
  object.id = id;
}

extension SquareMediaChunkEntityByIndex
    on IsarCollection<SquareMediaChunkEntity> {
  Future<SquareMediaChunkEntity?> getByCidNumberMediaIdChunkIndex(
    String cidNumber,
    String mediaId,
    int chunkIndex,
  ) {
    return getByIndex(r'cidNumber_mediaId_chunkIndex', [
      cidNumber,
      mediaId,
      chunkIndex,
    ]);
  }

  SquareMediaChunkEntity? getByCidNumberMediaIdChunkIndexSync(
    String cidNumber,
    String mediaId,
    int chunkIndex,
  ) {
    return getByIndexSync(r'cidNumber_mediaId_chunkIndex', [
      cidNumber,
      mediaId,
      chunkIndex,
    ]);
  }

  Future<bool> deleteByCidNumberMediaIdChunkIndex(
    String cidNumber,
    String mediaId,
    int chunkIndex,
  ) {
    return deleteByIndex(r'cidNumber_mediaId_chunkIndex', [
      cidNumber,
      mediaId,
      chunkIndex,
    ]);
  }

  bool deleteByCidNumberMediaIdChunkIndexSync(
    String cidNumber,
    String mediaId,
    int chunkIndex,
  ) {
    return deleteByIndexSync(r'cidNumber_mediaId_chunkIndex', [
      cidNumber,
      mediaId,
      chunkIndex,
    ]);
  }

  Future<List<SquareMediaChunkEntity?>> getAllByCidNumberMediaIdChunkIndex(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
    List<int> chunkIndexValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len && chunkIndexValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i], chunkIndexValues[i]]);
    }

    return getAllByIndex(r'cidNumber_mediaId_chunkIndex', values);
  }

  List<SquareMediaChunkEntity?> getAllByCidNumberMediaIdChunkIndexSync(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
    List<int> chunkIndexValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len && chunkIndexValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i], chunkIndexValues[i]]);
    }

    return getAllByIndexSync(r'cidNumber_mediaId_chunkIndex', values);
  }

  Future<int> deleteAllByCidNumberMediaIdChunkIndex(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
    List<int> chunkIndexValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len && chunkIndexValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i], chunkIndexValues[i]]);
    }

    return deleteAllByIndex(r'cidNumber_mediaId_chunkIndex', values);
  }

  int deleteAllByCidNumberMediaIdChunkIndexSync(
    List<String> cidNumberValues,
    List<String> mediaIdValues,
    List<int> chunkIndexValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      mediaIdValues.length == len && chunkIndexValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], mediaIdValues[i], chunkIndexValues[i]]);
    }

    return deleteAllByIndexSync(r'cidNumber_mediaId_chunkIndex', values);
  }

  Future<Id> putByCidNumberMediaIdChunkIndex(SquareMediaChunkEntity object) {
    return putByIndex(r'cidNumber_mediaId_chunkIndex', object);
  }

  Id putByCidNumberMediaIdChunkIndexSync(
    SquareMediaChunkEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(
      r'cidNumber_mediaId_chunkIndex',
      object,
      saveLinks: saveLinks,
    );
  }

  Future<List<Id>> putAllByCidNumberMediaIdChunkIndex(
    List<SquareMediaChunkEntity> objects,
  ) {
    return putAllByIndex(r'cidNumber_mediaId_chunkIndex', objects);
  }

  List<Id> putAllByCidNumberMediaIdChunkIndexSync(
    List<SquareMediaChunkEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'cidNumber_mediaId_chunkIndex',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension SquareMediaChunkEntityQueryWhereSort
    on QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QWhere> {
  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquareMediaChunkEntityQueryWhere
    on
        QueryBuilder<
          SquareMediaChunkEntity,
          SquareMediaChunkEntity,
          QWhereClause
        > {
  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberEqualToAnyMediaIdChunkIndex(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_mediaId_chunkIndex',
          value: [cidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberNotEqualToAnyMediaIdChunkIndex(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberMediaIdEqualToAnyChunkIndex(String cidNumber, String mediaId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_mediaId_chunkIndex',
          value: [cidNumber, mediaId],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberEqualToMediaIdNotEqualToAnyChunkIndex(
    String cidNumber,
    String mediaId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber],
                upper: [cidNumber, mediaId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber, mediaId],
                includeLower: false,
                upper: [cidNumber],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber, mediaId],
                includeLower: false,
                upper: [cidNumber],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber],
                upper: [cidNumber, mediaId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberMediaIdChunkIndexEqualTo(
    String cidNumber,
    String mediaId,
    int chunkIndex,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_mediaId_chunkIndex',
          value: [cidNumber, mediaId, chunkIndex],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberMediaIdEqualToChunkIndexNotEqualTo(
    String cidNumber,
    String mediaId,
    int chunkIndex,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber, mediaId],
                upper: [cidNumber, mediaId, chunkIndex],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber, mediaId, chunkIndex],
                includeLower: false,
                upper: [cidNumber, mediaId],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber, mediaId, chunkIndex],
                includeLower: false,
                upper: [cidNumber, mediaId],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_mediaId_chunkIndex',
                lower: [cidNumber, mediaId],
                upper: [cidNumber, mediaId, chunkIndex],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberMediaIdEqualToChunkIndexGreaterThan(
    String cidNumber,
    String mediaId,
    int chunkIndex, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cidNumber_mediaId_chunkIndex',
          lower: [cidNumber, mediaId, chunkIndex],
          includeLower: include,
          upper: [cidNumber, mediaId],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberMediaIdEqualToChunkIndexLessThan(
    String cidNumber,
    String mediaId,
    int chunkIndex, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cidNumber_mediaId_chunkIndex',
          lower: [cidNumber, mediaId],
          upper: [cidNumber, mediaId, chunkIndex],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterWhereClause
  >
  cidNumberMediaIdEqualToChunkIndexBetween(
    String cidNumber,
    String mediaId,
    int lowerChunkIndex,
    int upperChunkIndex, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cidNumber_mediaId_chunkIndex',
          lower: [cidNumber, mediaId, lowerChunkIndex],
          includeLower: includeLower,
          upper: [cidNumber, mediaId, upperChunkIndex],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension SquareMediaChunkEntityQueryFilter
    on
        QueryBuilder<
          SquareMediaChunkEntity,
          SquareMediaChunkEntity,
          QFilterCondition
        > {
  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'chunkBytes', value: value),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'chunkBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'chunkBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'chunkBytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'chunkBytes', length, true, length, true);
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'chunkBytes', 0, true, 0, true);
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'chunkBytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'chunkBytes', 0, true, length, include);
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'chunkBytes', length, include, 999999, true);
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'chunkBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'chunkIndex', value: value),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'chunkIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'chunkIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'chunkIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256EqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'chunkSha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256GreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'chunkSha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256LessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'chunkSha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256Between(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'chunkSha256',
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256StartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'chunkSha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256EndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'chunkSha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256Contains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'chunkSha256',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256Matches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'chunkSha256',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256IsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'chunkSha256', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  chunkSha256IsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'chunkSha256', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mediaId',
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
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mediaId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mediaId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaChunkEntity,
    SquareMediaChunkEntity,
    QAfterFilterCondition
  >
  mediaIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mediaId', value: ''),
      );
    });
  }
}

extension SquareMediaChunkEntityQueryObject
    on
        QueryBuilder<
          SquareMediaChunkEntity,
          SquareMediaChunkEntity,
          QFilterCondition
        > {}

extension SquareMediaChunkEntityQueryLinks
    on
        QueryBuilder<
          SquareMediaChunkEntity,
          SquareMediaChunkEntity,
          QFilterCondition
        > {}

extension SquareMediaChunkEntityQuerySortBy
    on QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QSortBy> {
  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByChunkIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkIndex', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByChunkIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkIndex', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByChunkSha256() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkSha256', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByChunkSha256Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkSha256', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByMediaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  sortByMediaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.desc);
    });
  }
}

extension SquareMediaChunkEntityQuerySortThenBy
    on
        QueryBuilder<
          SquareMediaChunkEntity,
          SquareMediaChunkEntity,
          QSortThenBy
        > {
  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByChunkIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkIndex', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByChunkIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkIndex', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByChunkSha256() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkSha256', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByChunkSha256Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chunkSha256', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByMediaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.asc);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QAfterSortBy>
  thenByMediaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.desc);
    });
  }
}

extension SquareMediaChunkEntityQueryWhereDistinct
    on QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QDistinct> {
  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QDistinct>
  distinctByChunkBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chunkBytes');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QDistinct>
  distinctByChunkIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chunkIndex');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QDistinct>
  distinctByChunkSha256({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chunkSha256', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QDistinct>
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquareMediaChunkEntity, SquareMediaChunkEntity, QDistinct>
  distinctByMediaId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaId', caseSensitive: caseSensitive);
    });
  }
}

extension SquareMediaChunkEntityQueryProperty
    on
        QueryBuilder<
          SquareMediaChunkEntity,
          SquareMediaChunkEntity,
          QQueryProperty
        > {
  QueryBuilder<SquareMediaChunkEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, List<int>, QQueryOperations>
  chunkBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chunkBytes');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, int, QQueryOperations>
  chunkIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chunkIndex');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, String, QQueryOperations>
  chunkSha256Property() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chunkSha256');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquareMediaChunkEntity, String, QQueryOperations>
  mediaIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaId');
    });
  }
}

extension GetSquareMediaReferenceEntityCollection on Isar {
  IsarCollection<SquareMediaReferenceEntity> get squareMediaReferenceEntitys =>
      this.collection();
}

const SquareMediaReferenceEntitySchema = CollectionSchema(
  name: r'SquareMediaReferenceEntity',
  id: -4797320234518084862,
  properties: {
    r'cidNumber': PropertySchema(
      id: 0,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'contentId': PropertySchema(
      id: 1,
      name: r'contentId',
      type: IsarType.string,
    ),
    r'contentKind': PropertySchema(
      id: 2,
      name: r'contentKind',
      type: IsarType.string,
    ),
    r'mediaId': PropertySchema(id: 3, name: r'mediaId', type: IsarType.string),
    r'mediaIndex': PropertySchema(
      id: 4,
      name: r'mediaIndex',
      type: IsarType.long,
    ),
    r'mediaRole': PropertySchema(
      id: 5,
      name: r'mediaRole',
      type: IsarType.string,
    ),
    r'referenceKey': PropertySchema(
      id: 6,
      name: r'referenceKey',
      type: IsarType.string,
    ),
  },

  estimateSize: _squareMediaReferenceEntityEstimateSize,
  serialize: _squareMediaReferenceEntitySerialize,
  deserialize: _squareMediaReferenceEntityDeserialize,
  deserializeProp: _squareMediaReferenceEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber_referenceKey': IndexSchema(
      id: 7278021372600719211,
      name: r'cidNumber_referenceKey',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'referenceKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'mediaId_cidNumber': IndexSchema(
      id: -7563655419905482321,
      name: r'mediaId_cidNumber',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'mediaId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'contentId_cidNumber_contentKind': IndexSchema(
      id: -4232330474872255915,
      name: r'contentId_cidNumber_contentKind',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'contentId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'contentKind',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _squareMediaReferenceEntityGetId,
  getLinks: _squareMediaReferenceEntityGetLinks,
  attach: _squareMediaReferenceEntityAttach,
  version: '3.3.2',
);
int _squareMediaReferenceEntityEstimateSize(
  SquareMediaReferenceEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.contentId.length * 3;
  bytesCount += 3 + object.contentKind.length * 3;
  bytesCount += 3 + object.mediaId.length * 3;
  bytesCount += 3 + object.mediaRole.length * 3;
  bytesCount += 3 + object.referenceKey.length * 3;
  return bytesCount;
}

void _squareMediaReferenceEntitySerialize(
  SquareMediaReferenceEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cidNumber);
  writer.writeString(offsets[1], object.contentId);
  writer.writeString(offsets[2], object.contentKind);
  writer.writeString(offsets[3], object.mediaId);
  writer.writeLong(offsets[4], object.mediaIndex);
  writer.writeString(offsets[5], object.mediaRole);
  writer.writeString(offsets[6], object.referenceKey);
}

SquareMediaReferenceEntity _squareMediaReferenceEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquareMediaReferenceEntity();
  object.cidNumber = reader.readString(offsets[0]);
  object.contentId = reader.readString(offsets[1]);
  object.contentKind = reader.readString(offsets[2]);
  object.id = id;
  object.mediaId = reader.readString(offsets[3]);
  object.mediaIndex = reader.readLong(offsets[4]);
  object.mediaRole = reader.readString(offsets[5]);
  object.referenceKey = reader.readString(offsets[6]);
  return object;
}

P _squareMediaReferenceEntityDeserializeProp<P>(
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
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squareMediaReferenceEntityGetId(SquareMediaReferenceEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squareMediaReferenceEntityGetLinks(
  SquareMediaReferenceEntity object,
) {
  return [];
}

void _squareMediaReferenceEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  SquareMediaReferenceEntity object,
) {
  object.id = id;
}

extension SquareMediaReferenceEntityByIndex
    on IsarCollection<SquareMediaReferenceEntity> {
  Future<SquareMediaReferenceEntity?> getByCidNumberReferenceKey(
    String cidNumber,
    String referenceKey,
  ) {
    return getByIndex(r'cidNumber_referenceKey', [cidNumber, referenceKey]);
  }

  SquareMediaReferenceEntity? getByCidNumberReferenceKeySync(
    String cidNumber,
    String referenceKey,
  ) {
    return getByIndexSync(r'cidNumber_referenceKey', [cidNumber, referenceKey]);
  }

  Future<bool> deleteByCidNumberReferenceKey(
    String cidNumber,
    String referenceKey,
  ) {
    return deleteByIndex(r'cidNumber_referenceKey', [cidNumber, referenceKey]);
  }

  bool deleteByCidNumberReferenceKeySync(
    String cidNumber,
    String referenceKey,
  ) {
    return deleteByIndexSync(r'cidNumber_referenceKey', [
      cidNumber,
      referenceKey,
    ]);
  }

  Future<List<SquareMediaReferenceEntity?>> getAllByCidNumberReferenceKey(
    List<String> cidNumberValues,
    List<String> referenceKeyValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      referenceKeyValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], referenceKeyValues[i]]);
    }

    return getAllByIndex(r'cidNumber_referenceKey', values);
  }

  List<SquareMediaReferenceEntity?> getAllByCidNumberReferenceKeySync(
    List<String> cidNumberValues,
    List<String> referenceKeyValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      referenceKeyValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], referenceKeyValues[i]]);
    }

    return getAllByIndexSync(r'cidNumber_referenceKey', values);
  }

  Future<int> deleteAllByCidNumberReferenceKey(
    List<String> cidNumberValues,
    List<String> referenceKeyValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      referenceKeyValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], referenceKeyValues[i]]);
    }

    return deleteAllByIndex(r'cidNumber_referenceKey', values);
  }

  int deleteAllByCidNumberReferenceKeySync(
    List<String> cidNumberValues,
    List<String> referenceKeyValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      referenceKeyValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], referenceKeyValues[i]]);
    }

    return deleteAllByIndexSync(r'cidNumber_referenceKey', values);
  }

  Future<Id> putByCidNumberReferenceKey(SquareMediaReferenceEntity object) {
    return putByIndex(r'cidNumber_referenceKey', object);
  }

  Id putByCidNumberReferenceKeySync(
    SquareMediaReferenceEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(
      r'cidNumber_referenceKey',
      object,
      saveLinks: saveLinks,
    );
  }

  Future<List<Id>> putAllByCidNumberReferenceKey(
    List<SquareMediaReferenceEntity> objects,
  ) {
    return putAllByIndex(r'cidNumber_referenceKey', objects);
  }

  List<Id> putAllByCidNumberReferenceKeySync(
    List<SquareMediaReferenceEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'cidNumber_referenceKey',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension SquareMediaReferenceEntityQueryWhereSort
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QWhere
        > {
  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquareMediaReferenceEntityQueryWhere
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QWhereClause
        > {
  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  cidNumberEqualToAnyReferenceKey(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_referenceKey',
          value: [cidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  cidNumberNotEqualToAnyReferenceKey(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  cidNumberReferenceKeyEqualTo(String cidNumber, String referenceKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_referenceKey',
          value: [cidNumber, referenceKey],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  cidNumberEqualToReferenceKeyNotEqualTo(
    String cidNumber,
    String referenceKey,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [cidNumber],
                upper: [cidNumber, referenceKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [cidNumber, referenceKey],
                includeLower: false,
                upper: [cidNumber],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [cidNumber, referenceKey],
                includeLower: false,
                upper: [cidNumber],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_referenceKey',
                lower: [cidNumber],
                upper: [cidNumber, referenceKey],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  mediaIdEqualToAnyCidNumber(String mediaId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'mediaId_cidNumber',
          value: [mediaId],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  mediaIdNotEqualToAnyCidNumber(String mediaId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [],
                upper: [mediaId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [mediaId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [mediaId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [],
                upper: [mediaId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  mediaIdCidNumberEqualTo(String mediaId, String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'mediaId_cidNumber',
          value: [mediaId, cidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  mediaIdEqualToCidNumberNotEqualTo(String mediaId, String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [mediaId],
                upper: [mediaId, cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [mediaId, cidNumber],
                includeLower: false,
                upper: [mediaId],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [mediaId, cidNumber],
                includeLower: false,
                upper: [mediaId],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mediaId_cidNumber',
                lower: [mediaId],
                upper: [mediaId, cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  contentIdEqualToAnyCidNumberContentKind(String contentId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'contentId_cidNumber_contentKind',
          value: [contentId],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  contentIdNotEqualToAnyCidNumberContentKind(String contentId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [],
                upper: [contentId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [],
                upper: [contentId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  contentIdCidNumberEqualToAnyContentKind(String contentId, String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'contentId_cidNumber_contentKind',
          value: [contentId, cidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  contentIdEqualToCidNumberNotEqualToAnyContentKind(
    String contentId,
    String cidNumber,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId],
                upper: [contentId, cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId, cidNumber],
                includeLower: false,
                upper: [contentId],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId, cidNumber],
                includeLower: false,
                upper: [contentId],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId],
                upper: [contentId, cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  contentIdCidNumberContentKindEqualTo(
    String contentId,
    String cidNumber,
    String contentKind,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'contentId_cidNumber_contentKind',
          value: [contentId, cidNumber, contentKind],
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterWhereClause
  >
  contentIdCidNumberEqualToContentKindNotEqualTo(
    String contentId,
    String cidNumber,
    String contentKind,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId, cidNumber],
                upper: [contentId, cidNumber, contentKind],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId, cidNumber, contentKind],
                includeLower: false,
                upper: [contentId, cidNumber],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId, cidNumber, contentKind],
                includeLower: false,
                upper: [contentId, cidNumber],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'contentId_cidNumber_contentKind',
                lower: [contentId, cidNumber],
                upper: [contentId, cidNumber, contentKind],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension SquareMediaReferenceEntityQueryFilter
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QFilterCondition
        > {
  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'contentId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'contentId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'contentId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'contentId',
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'contentId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'contentId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'contentId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'contentId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'contentId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'contentId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'contentKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'contentKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'contentKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'contentKind',
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'contentKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'contentKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'contentKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'contentKind',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'contentKind', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  contentKindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'contentKind', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mediaId',
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mediaId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mediaId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mediaId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mediaId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mediaIndex', value: value),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mediaIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mediaIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mediaIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mediaRole',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mediaRole',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mediaRole',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mediaRole',
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mediaRole',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mediaRole',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mediaRole',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mediaRole',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mediaRole', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  mediaRoleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mediaRole', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'referenceKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'referenceKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'referenceKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'referenceKey',
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
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'referenceKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'referenceKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'referenceKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'referenceKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'referenceKey', value: ''),
      );
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterFilterCondition
  >
  referenceKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'referenceKey', value: ''),
      );
    });
  }
}

extension SquareMediaReferenceEntityQueryObject
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QFilterCondition
        > {}

extension SquareMediaReferenceEntityQueryLinks
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QFilterCondition
        > {}

extension SquareMediaReferenceEntityQuerySortBy
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QSortBy
        > {
  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByContentId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentId', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByContentIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentId', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByContentKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentKind', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByContentKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentKind', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByMediaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByMediaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByMediaIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaIndex', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByMediaIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaIndex', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByMediaRole() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaRole', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByMediaRoleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaRole', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByReferenceKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'referenceKey', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  sortByReferenceKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'referenceKey', Sort.desc);
    });
  }
}

extension SquareMediaReferenceEntityQuerySortThenBy
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QSortThenBy
        > {
  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByContentId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentId', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByContentIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentId', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByContentKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentKind', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByContentKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentKind', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByMediaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByMediaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaId', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByMediaIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaIndex', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByMediaIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaIndex', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByMediaRole() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaRole', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByMediaRoleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaRole', Sort.desc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByReferenceKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'referenceKey', Sort.asc);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QAfterSortBy
  >
  thenByReferenceKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'referenceKey', Sort.desc);
    });
  }
}

extension SquareMediaReferenceEntityQueryWhereDistinct
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QDistinct
        > {
  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByContentId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByContentKind({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentKind', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByMediaId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByMediaIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaIndex');
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByMediaRole({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaRole', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    SquareMediaReferenceEntity,
    SquareMediaReferenceEntity,
    QDistinct
  >
  distinctByReferenceKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'referenceKey', caseSensitive: caseSensitive);
    });
  }
}

extension SquareMediaReferenceEntityQueryProperty
    on
        QueryBuilder<
          SquareMediaReferenceEntity,
          SquareMediaReferenceEntity,
          QQueryProperty
        > {
  QueryBuilder<SquareMediaReferenceEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, String, QQueryOperations>
  contentIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentId');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, String, QQueryOperations>
  contentKindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentKind');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, String, QQueryOperations>
  mediaIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaId');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, int, QQueryOperations>
  mediaIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaIndex');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, String, QQueryOperations>
  mediaRoleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaRole');
    });
  }

  QueryBuilder<SquareMediaReferenceEntity, String, QQueryOperations>
  referenceKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'referenceKey');
    });
  }
}


extension GetSquarePublicationEntityCollection on Isar {
  IsarCollection<SquarePublicationEntity> get squarePublicationEntitys =>
      this.collection();
}

const SquarePublicationEntitySchema = CollectionSchema(
  name: r'SquarePublicationEntity',
  id: -3650787915143539292,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'blockHash': PropertySchema(
      id: 1,
      name: r'blockHash',
      type: IsarType.string,
    ),
    r'chainBlock': PropertySchema(
      id: 2,
      name: r'chainBlock',
      type: IsarType.long,
    ),
    r'cidNumber': PropertySchema(
      id: 3,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'contentHash': PropertySchema(
      id: 4,
      name: r'contentHash',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 5,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'draftId': PropertySchema(id: 6, name: r'draftId', type: IsarType.string),
    r'manifestBytes': PropertySchema(
      id: 7,
      name: r'manifestBytes',
      type: IsarType.byteList,
    ),
    r'postCategory': PropertySchema(
      id: 8,
      name: r'postCategory',
      type: IsarType.string,
    ),
    r'postId': PropertySchema(id: 9, name: r'postId', type: IsarType.string),
    r'postType': PropertySchema(
      id: 10,
      name: r'postType',
      type: IsarType.string,
    ),
    r'publicationState': PropertySchema(
      id: 11,
      name: r'publicationState',
      type: IsarType.string,
    ),
    r'replacePostId': PropertySchema(
      id: 12,
      name: r'replacePostId',
      type: IsarType.string,
    ),
    r'storageReceiptId': PropertySchema(
      id: 13,
      name: r'storageReceiptId',
      type: IsarType.string,
    ),
    r'transactionHash': PropertySchema(
      id: 14,
      name: r'transactionHash',
      type: IsarType.string,
    ),
    r'uploadId': PropertySchema(
      id: 15,
      name: r'uploadId',
      type: IsarType.string,
    ),
  },

  estimateSize: _squarePublicationEntityEstimateSize,
  serialize: _squarePublicationEntitySerialize,
  deserialize: _squarePublicationEntityDeserialize,
  deserializeProp: _squarePublicationEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber_draftId': IndexSchema(
      id: 7412092932619659019,
      name: r'cidNumber_draftId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'draftId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _squarePublicationEntityGetId,
  getLinks: _squarePublicationEntityGetLinks,
  attach: _squarePublicationEntityAttach,
  version: '3.3.2',
);
int _squarePublicationEntityEstimateSize(
  SquarePublicationEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  {
    final value = object.blockHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.contentHash.length * 3;
  bytesCount += 3 + object.draftId.length * 3;
  bytesCount += 3 + object.manifestBytes.length;
  {
    final value = object.postCategory;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.postId.length * 3;
  bytesCount += 3 + object.postType.length * 3;
  bytesCount += 3 + object.publicationState.length * 3;
  {
    final value = object.replacePostId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.storageReceiptId.length * 3;
  {
    final value = object.transactionHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.uploadId.length * 3;
  return bytesCount;
}

void _squarePublicationEntitySerialize(
  SquarePublicationEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.blockHash);
  writer.writeLong(offsets[2], object.chainBlock);
  writer.writeString(offsets[3], object.cidNumber);
  writer.writeString(offsets[4], object.contentHash);
  writer.writeLong(offsets[5], object.createdAt);
  writer.writeString(offsets[6], object.draftId);
  writer.writeByteList(offsets[7], object.manifestBytes);
  writer.writeString(offsets[8], object.postCategory);
  writer.writeString(offsets[9], object.postId);
  writer.writeString(offsets[10], object.postType);
  writer.writeString(offsets[11], object.publicationState);
  writer.writeString(offsets[12], object.replacePostId);
  writer.writeString(offsets[13], object.storageReceiptId);
  writer.writeString(offsets[14], object.transactionHash);
  writer.writeString(offsets[15], object.uploadId);
}

SquarePublicationEntity _squarePublicationEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquarePublicationEntity();
  object.accountId = reader.readString(offsets[0]);
  object.blockHash = reader.readStringOrNull(offsets[1]);
  object.chainBlock = reader.readLongOrNull(offsets[2]);
  object.cidNumber = reader.readString(offsets[3]);
  object.contentHash = reader.readString(offsets[4]);
  object.createdAt = reader.readLongOrNull(offsets[5]);
  object.draftId = reader.readString(offsets[6]);
  object.id = id;
  object.manifestBytes = reader.readByteList(offsets[7]) ?? [];
  object.postCategory = reader.readStringOrNull(offsets[8]);
  object.postId = reader.readString(offsets[9]);
  object.postType = reader.readString(offsets[10]);
  object.publicationState = reader.readString(offsets[11]);
  object.replacePostId = reader.readStringOrNull(offsets[12]);
  object.storageReceiptId = reader.readString(offsets[13]);
  object.transactionHash = reader.readStringOrNull(offsets[14]);
  object.uploadId = reader.readString(offsets[15]);
  return object;
}

P _squarePublicationEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readByteList(offset) ?? []) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readString(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squarePublicationEntityGetId(SquarePublicationEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squarePublicationEntityGetLinks(
  SquarePublicationEntity object,
) {
  return [];
}

void _squarePublicationEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  SquarePublicationEntity object,
) {
  object.id = id;
}

extension SquarePublicationEntityByIndex
    on IsarCollection<SquarePublicationEntity> {
  Future<SquarePublicationEntity?> getByCidNumberDraftId(
    String cidNumber,
    String draftId,
  ) {
    return getByIndex(r'cidNumber_draftId', [cidNumber, draftId]);
  }

  SquarePublicationEntity? getByCidNumberDraftIdSync(
    String cidNumber,
    String draftId,
  ) {
    return getByIndexSync(r'cidNumber_draftId', [cidNumber, draftId]);
  }

  Future<bool> deleteByCidNumberDraftId(String cidNumber, String draftId) {
    return deleteByIndex(r'cidNumber_draftId', [cidNumber, draftId]);
  }

  bool deleteByCidNumberDraftIdSync(String cidNumber, String draftId) {
    return deleteByIndexSync(r'cidNumber_draftId', [cidNumber, draftId]);
  }

  Future<List<SquarePublicationEntity?>> getAllByCidNumberDraftId(
    List<String> cidNumberValues,
    List<String> draftIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      draftIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], draftIdValues[i]]);
    }

    return getAllByIndex(r'cidNumber_draftId', values);
  }

  List<SquarePublicationEntity?> getAllByCidNumberDraftIdSync(
    List<String> cidNumberValues,
    List<String> draftIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      draftIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], draftIdValues[i]]);
    }

    return getAllByIndexSync(r'cidNumber_draftId', values);
  }

  Future<int> deleteAllByCidNumberDraftId(
    List<String> cidNumberValues,
    List<String> draftIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      draftIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], draftIdValues[i]]);
    }

    return deleteAllByIndex(r'cidNumber_draftId', values);
  }

  int deleteAllByCidNumberDraftIdSync(
    List<String> cidNumberValues,
    List<String> draftIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      draftIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], draftIdValues[i]]);
    }

    return deleteAllByIndexSync(r'cidNumber_draftId', values);
  }

  Future<Id> putByCidNumberDraftId(SquarePublicationEntity object) {
    return putByIndex(r'cidNumber_draftId', object);
  }

  Id putByCidNumberDraftIdSync(
    SquarePublicationEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'cidNumber_draftId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCidNumberDraftId(
    List<SquarePublicationEntity> objects,
  ) {
    return putAllByIndex(r'cidNumber_draftId', objects);
  }

  List<Id> putAllByCidNumberDraftIdSync(
    List<SquarePublicationEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'cidNumber_draftId',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension SquarePublicationEntityQueryWhereSort
    on QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QWhere> {
  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquarePublicationEntityQueryWhere
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QWhereClause
        > {
  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterWhereClause
  >
  cidNumberEqualToAnyDraftId(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_draftId',
          value: [cidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterWhereClause
  >
  cidNumberNotEqualToAnyDraftId(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterWhereClause
  >
  cidNumberDraftIdEqualTo(String cidNumber, String draftId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_draftId',
          value: [cidNumber, draftId],
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterWhereClause
  >
  cidNumberEqualToDraftIdNotEqualTo(String cidNumber, String draftId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [cidNumber],
                upper: [cidNumber, draftId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [cidNumber, draftId],
                includeLower: false,
                upper: [cidNumber],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [cidNumber, draftId],
                includeLower: false,
                upper: [cidNumber],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_draftId',
                lower: [cidNumber],
                upper: [cidNumber, draftId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension SquarePublicationEntityQueryFilter
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QFilterCondition
        > {
  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  accountIdEqualTo(String value, {bool caseSensitive = true}) {
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  accountIdGreaterThan(
    String value, {
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  accountIdLessThan(
    String value, {
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  accountIdBetween(
    String lower,
    String upper, {
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'blockHash'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'blockHash'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'blockHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'blockHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'blockHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'blockHash',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'blockHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'blockHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'blockHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'blockHash',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'blockHash', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  blockHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'blockHash', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  chainBlockIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'chainBlock'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  chainBlockIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'chainBlock'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  chainBlockEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'chainBlock', value: value),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  chainBlockGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'chainBlock',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  chainBlockLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'chainBlock',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  chainBlockBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'chainBlock',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'contentHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'contentHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'contentHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'contentHash',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'contentHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'contentHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'contentHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'contentHash',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'contentHash', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  contentHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'contentHash', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  createdAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'createdAt'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  createdAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'createdAt'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  createdAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  createdAtGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  createdAtLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  createdAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'draftId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'draftId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'draftId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'draftId',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'draftId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'draftId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'draftId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'draftId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'draftId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  draftIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'draftId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'manifestBytes', value: value),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'manifestBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'manifestBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'manifestBytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'manifestBytes', length, true, length, true);
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'manifestBytes', 0, true, 0, true);
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'manifestBytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'manifestBytes', 0, true, length, include);
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'manifestBytes', length, include, 999999, true);
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  manifestBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'manifestBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'postCategory'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'postCategory'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'postCategory',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'postCategory',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'postCategory',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'postCategory',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'postCategory',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'postCategory',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'postCategory',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'postCategory',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'postCategory', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postCategoryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'postCategory', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'postId',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'postId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'postId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'postId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'postType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'postType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'postType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'postType',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'postType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'postType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'postType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'postType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'postType', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  postTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'postType', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'publicationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'publicationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'publicationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'publicationState',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'publicationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'publicationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'publicationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'publicationState',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'publicationState', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  publicationStateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'publicationState', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'replacePostId'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'replacePostId'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'replacePostId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'replacePostId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'replacePostId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'replacePostId',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'replacePostId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'replacePostId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'replacePostId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'replacePostId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'replacePostId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  replacePostIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'replacePostId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'storageReceiptId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'storageReceiptId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'storageReceiptId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'storageReceiptId',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'storageReceiptId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'storageReceiptId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'storageReceiptId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'storageReceiptId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'storageReceiptId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  storageReceiptIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'storageReceiptId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'transactionHash'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'transactionHash'),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'transactionHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'transactionHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'transactionHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'transactionHash',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'transactionHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'transactionHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'transactionHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'transactionHash',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'transactionHash', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  transactionHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'transactionHash', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'uploadId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'uploadId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'uploadId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'uploadId',
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
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'uploadId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'uploadId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'uploadId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'uploadId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'uploadId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePublicationEntity,
    SquarePublicationEntity,
    QAfterFilterCondition
  >
  uploadIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'uploadId', value: ''),
      );
    });
  }
}

extension SquarePublicationEntityQueryObject
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QFilterCondition
        > {}

extension SquarePublicationEntityQueryLinks
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QFilterCondition
        > {}

extension SquarePublicationEntityQuerySortBy
    on QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QSortBy> {
  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByBlockHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByBlockHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByChainBlock() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByChainBlockDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByContentHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByContentHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByDraftId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByDraftIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPostCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPostCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPostType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPostTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPublicationState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicationState', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByPublicationStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicationState', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByReplacePostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replacePostId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByReplacePostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replacePostId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByStorageReceiptId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByStorageReceiptIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByTransactionHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionHash', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByTransactionHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionHash', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByUploadId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uploadId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  sortByUploadIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uploadId', Sort.desc);
    });
  }
}

extension SquarePublicationEntityQuerySortThenBy
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QSortThenBy
        > {
  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByBlockHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByBlockHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByChainBlock() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByChainBlockDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chainBlock', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByContentHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByContentHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentHash', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByDraftId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByDraftIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draftId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPostCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPostCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postCategory', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPostType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPostTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postType', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPublicationState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicationState', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByPublicationStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicationState', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByReplacePostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replacePostId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByReplacePostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replacePostId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByStorageReceiptId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByStorageReceiptIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storageReceiptId', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByTransactionHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionHash', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByTransactionHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionHash', Sort.desc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByUploadId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uploadId', Sort.asc);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QAfterSortBy>
  thenByUploadIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uploadId', Sort.desc);
    });
  }
}

extension SquarePublicationEntityQueryWhereDistinct
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QDistinct
        > {
  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByBlockHash({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'blockHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByChainBlock() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chainBlock');
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByContentHash({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByDraftId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'draftId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByManifestBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'manifestBytes');
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByPostCategory({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postCategory', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByPostId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByPostType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByPublicationState({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'publicationState',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByReplacePostId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'replacePostId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByStorageReceiptId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'storageReceiptId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByTransactionHash({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'transactionHash',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SquarePublicationEntity, SquarePublicationEntity, QDistinct>
  distinctByUploadId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'uploadId', caseSensitive: caseSensitive);
    });
  }
}

extension SquarePublicationEntityQueryProperty
    on
        QueryBuilder<
          SquarePublicationEntity,
          SquarePublicationEntity,
          QQueryProperty
        > {
  QueryBuilder<SquarePublicationEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<SquarePublicationEntity, String?, QQueryOperations>
  blockHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'blockHash');
    });
  }

  QueryBuilder<SquarePublicationEntity, int?, QQueryOperations>
  chainBlockProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chainBlock');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  contentHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentHash');
    });
  }

  QueryBuilder<SquarePublicationEntity, int?, QQueryOperations>
  createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  draftIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'draftId');
    });
  }

  QueryBuilder<SquarePublicationEntity, List<int>, QQueryOperations>
  manifestBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'manifestBytes');
    });
  }

  QueryBuilder<SquarePublicationEntity, String?, QQueryOperations>
  postCategoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postCategory');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  postIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postId');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  postTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postType');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  publicationStateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'publicationState');
    });
  }

  QueryBuilder<SquarePublicationEntity, String?, QQueryOperations>
  replacePostIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'replacePostId');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  storageReceiptIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'storageReceiptId');
    });
  }

  QueryBuilder<SquarePublicationEntity, String?, QQueryOperations>
  transactionHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'transactionHash');
    });
  }

  QueryBuilder<SquarePublicationEntity, String, QQueryOperations>
  uploadIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'uploadId');
    });
  }
}

extension GetSquarePostDeletionEntityCollection on Isar {
  IsarCollection<SquarePostDeletionEntity> get squarePostDeletionEntitys =>
      this.collection();
}

const SquarePostDeletionEntitySchema = CollectionSchema(
  name: r'SquarePostDeletionEntity',
  id: 6088620848993647631,
  properties: {
    r'cidNumber': PropertySchema(
      id: 0,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'operationState': PropertySchema(
      id: 1,
      name: r'operationState',
      type: IsarType.string,
    ),
    r'postId': PropertySchema(id: 2, name: r'postId', type: IsarType.string),
  },

  estimateSize: _squarePostDeletionEntityEstimateSize,
  serialize: _squarePostDeletionEntitySerialize,
  deserialize: _squarePostDeletionEntityDeserialize,
  deserializeProp: _squarePostDeletionEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'cidNumber_postId': IndexSchema(
      id: 1858134955169433678,
      name: r'cidNumber_postId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'postId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _squarePostDeletionEntityGetId,
  getLinks: _squarePostDeletionEntityGetLinks,
  attach: _squarePostDeletionEntityAttach,
  version: '3.3.2',
);
int _squarePostDeletionEntityEstimateSize(
  SquarePostDeletionEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cidNumber.length * 3;
  bytesCount += 3 + object.operationState.length * 3;
  bytesCount += 3 + object.postId.length * 3;
  return bytesCount;
}

void _squarePostDeletionEntitySerialize(
  SquarePostDeletionEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cidNumber);
  writer.writeString(offsets[1], object.operationState);
  writer.writeString(offsets[2], object.postId);
}

SquarePostDeletionEntity _squarePostDeletionEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SquarePostDeletionEntity();
  object.cidNumber = reader.readString(offsets[0]);
  object.id = id;
  object.operationState = reader.readString(offsets[1]);
  object.postId = reader.readString(offsets[2]);
  return object;
}

P _squarePostDeletionEntityDeserializeProp<P>(
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
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _squarePostDeletionEntityGetId(SquarePostDeletionEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _squarePostDeletionEntityGetLinks(
  SquarePostDeletionEntity object,
) {
  return [];
}

void _squarePostDeletionEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  SquarePostDeletionEntity object,
) {
  object.id = id;
}

extension SquarePostDeletionEntityByIndex
    on IsarCollection<SquarePostDeletionEntity> {
  Future<SquarePostDeletionEntity?> getByCidNumberPostId(
    String cidNumber,
    String postId,
  ) {
    return getByIndex(r'cidNumber_postId', [cidNumber, postId]);
  }

  SquarePostDeletionEntity? getByCidNumberPostIdSync(
    String cidNumber,
    String postId,
  ) {
    return getByIndexSync(r'cidNumber_postId', [cidNumber, postId]);
  }

  Future<bool> deleteByCidNumberPostId(String cidNumber, String postId) {
    return deleteByIndex(r'cidNumber_postId', [cidNumber, postId]);
  }

  bool deleteByCidNumberPostIdSync(String cidNumber, String postId) {
    return deleteByIndexSync(r'cidNumber_postId', [cidNumber, postId]);
  }

  Future<List<SquarePostDeletionEntity?>> getAllByCidNumberPostId(
    List<String> cidNumberValues,
    List<String> postIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      postIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], postIdValues[i]]);
    }

    return getAllByIndex(r'cidNumber_postId', values);
  }

  List<SquarePostDeletionEntity?> getAllByCidNumberPostIdSync(
    List<String> cidNumberValues,
    List<String> postIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      postIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], postIdValues[i]]);
    }

    return getAllByIndexSync(r'cidNumber_postId', values);
  }

  Future<int> deleteAllByCidNumberPostId(
    List<String> cidNumberValues,
    List<String> postIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      postIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], postIdValues[i]]);
    }

    return deleteAllByIndex(r'cidNumber_postId', values);
  }

  int deleteAllByCidNumberPostIdSync(
    List<String> cidNumberValues,
    List<String> postIdValues,
  ) {
    final len = cidNumberValues.length;
    assert(
      postIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([cidNumberValues[i], postIdValues[i]]);
    }

    return deleteAllByIndexSync(r'cidNumber_postId', values);
  }

  Future<Id> putByCidNumberPostId(SquarePostDeletionEntity object) {
    return putByIndex(r'cidNumber_postId', object);
  }

  Id putByCidNumberPostIdSync(
    SquarePostDeletionEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'cidNumber_postId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCidNumberPostId(
    List<SquarePostDeletionEntity> objects,
  ) {
    return putAllByIndex(r'cidNumber_postId', objects);
  }

  List<Id> putAllByCidNumberPostIdSync(
    List<SquarePostDeletionEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'cidNumber_postId',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension SquarePostDeletionEntityQueryObject
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QFilterCondition
        > {}

extension SquarePostDeletionEntityQueryLinks
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QFilterCondition
        > {}

extension SquarePostDeletionEntityQuerySortBy
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QSortBy
        > {
  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  sortByOperationState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationState', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  sortByOperationStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationState', Sort.desc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  sortByPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  sortByPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.desc);
    });
  }
}

extension SquarePostDeletionEntityQuerySortThenBy
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QSortThenBy
        > {
  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByOperationState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationState', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByOperationStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'operationState', Sort.desc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByPostId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.asc);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterSortBy>
  thenByPostIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postId', Sort.desc);
    });
  }
}

extension SquarePostDeletionEntityQueryWhereDistinct
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QDistinct
        > {
  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QDistinct>
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QDistinct>
  distinctByOperationState({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'operationState',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QDistinct>
  distinctByPostId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postId', caseSensitive: caseSensitive);
    });
  }
}

extension SquarePostDeletionEntityQueryProperty
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QQueryProperty
        > {
  QueryBuilder<SquarePostDeletionEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SquarePostDeletionEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<SquarePostDeletionEntity, String, QQueryOperations>
  operationStateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'operationState');
    });
  }

  QueryBuilder<SquarePostDeletionEntity, String, QQueryOperations>
  postIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postId');
    });
  }
}

extension SquarePostDeletionEntityQueryWhereSort
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QWhere
        > {
  QueryBuilder<SquarePostDeletionEntity, SquarePostDeletionEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SquarePostDeletionEntityQueryWhere
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QWhereClause
        > {
  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterWhereClause
  >
  cidNumberEqualToAnyPostId(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_postId',
          value: [cidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterWhereClause
  >
  cidNumberNotEqualToAnyPostId(String cidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [cidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [],
                upper: [cidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterWhereClause
  >
  cidNumberPostIdEqualTo(String cidNumber, String postId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'cidNumber_postId',
          value: [cidNumber, postId],
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterWhereClause
  >
  cidNumberEqualToPostIdNotEqualTo(String cidNumber, String postId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [cidNumber],
                upper: [cidNumber, postId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [cidNumber, postId],
                includeLower: false,
                upper: [cidNumber],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [cidNumber, postId],
                includeLower: false,
                upper: [cidNumber],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cidNumber_postId',
                lower: [cidNumber],
                upper: [cidNumber, postId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension SquarePostDeletionEntityQueryFilter
    on
        QueryBuilder<
          SquarePostDeletionEntity,
          SquarePostDeletionEntity,
          QFilterCondition
        > {
  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'operationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'operationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'operationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'operationState',
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'operationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'operationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'operationState',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'operationState',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'operationState', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  operationStateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'operationState', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'postId',
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
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'postId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'postId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'postId', value: ''),
      );
    });
  }

  QueryBuilder<
    SquarePostDeletionEntity,
    SquarePostDeletionEntity,
    QAfterFilterCondition
  >
  postIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'postId', value: ''),
      );
    });
  }
}
