// GENERATED CODE - DO NOT MODIFY BY HAND
// 本生成文件只提供 CitizenApp 业务实体的 Isar schema、序列化和查询扩展；
// 钱包密钥、签名和链交易底层仍由 CitizenSDK 唯一承担。

part of 'wallet_isar.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletAccountDataHandoverEntityCollection on Isar {
  IsarCollection<WalletAccountDataHandoverEntity>
  get walletAccountDataHandoverEntitys => this.collection();
}

const WalletAccountDataHandoverEntitySchema = CollectionSchema(
  name: r'WalletAccountDataHandoverEntity',
  id: -2151249112946021068,
  properties: {
    r'payloadJson': PropertySchema(
      id: 0,
      name: r'payloadJson',
      type: IsarType.string,
    ),
  },

  estimateSize: _walletAccountDataHandoverEntityEstimateSize,
  serialize: _walletAccountDataHandoverEntitySerialize,
  deserialize: _walletAccountDataHandoverEntityDeserialize,
  deserializeProp: _walletAccountDataHandoverEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _walletAccountDataHandoverEntityGetId,
  getLinks: _walletAccountDataHandoverEntityGetLinks,
  attach: _walletAccountDataHandoverEntityAttach,
  version: '3.3.2',
);

int _walletAccountDataHandoverEntityEstimateSize(
  WalletAccountDataHandoverEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payloadJson.length * 3;
  return bytesCount;
}

void _walletAccountDataHandoverEntitySerialize(
  WalletAccountDataHandoverEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.payloadJson);
}

WalletAccountDataHandoverEntity _walletAccountDataHandoverEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletAccountDataHandoverEntity();
  object.id = id;
  object.payloadJson = reader.readString(offsets[0]);
  return object;
}

P _walletAccountDataHandoverEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletAccountDataHandoverEntityGetId(
  WalletAccountDataHandoverEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletAccountDataHandoverEntityGetLinks(
  WalletAccountDataHandoverEntity object,
) {
  return [];
}

void _walletAccountDataHandoverEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletAccountDataHandoverEntity object,
) {
  object.id = id;
}

extension WalletAccountDataHandoverEntityQueryWhereSort
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QWhere
        > {
  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletAccountDataHandoverEntityQueryWhere
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
}

extension WalletAccountDataHandoverEntityQueryFilter
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }
}

extension WalletAccountDataHandoverEntityQueryObject
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QFilterCondition
        > {}

extension WalletAccountDataHandoverEntityQueryLinks
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QFilterCondition
        > {}

extension WalletAccountDataHandoverEntityQuerySortBy
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }
}

extension WalletAccountDataHandoverEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }
}

extension WalletAccountDataHandoverEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletAccountDataHandoverEntity,
    WalletAccountDataHandoverEntity,
    QDistinct
  >
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }
}

extension WalletAccountDataHandoverEntityQueryProperty
    on
        QueryBuilder<
          WalletAccountDataHandoverEntity,
          WalletAccountDataHandoverEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletAccountDataHandoverEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletAccountDataHandoverEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletAttestationEntityCollection on Isar {
  IsarCollection<WalletAttestationEntity> get walletAttestationEntitys =>
      this.collection();
}

const WalletAttestationEntitySchema = CollectionSchema(
  name: r'WalletAttestationEntity',
  id: 7556985157355099590,
  properties: {
    r'expiresAtMillis': PropertySchema(
      id: 0,
      name: r'expiresAtMillis',
      type: IsarType.long,
    ),
    r'lastRequestPayload': PropertySchema(
      id: 1,
      name: r'lastRequestPayload',
      type: IsarType.string,
    ),
    r'policy': PropertySchema(id: 2, name: r'policy', type: IsarType.string),
  },

  estimateSize: _walletAttestationEntityEstimateSize,
  serialize: _walletAttestationEntitySerialize,
  deserialize: _walletAttestationEntityDeserialize,
  deserializeProp: _walletAttestationEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _walletAttestationEntityGetId,
  getLinks: _walletAttestationEntityGetLinks,
  attach: _walletAttestationEntityAttach,
  version: '3.3.2',
);

int _walletAttestationEntityEstimateSize(
  WalletAttestationEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.lastRequestPayload;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.policy;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _walletAttestationEntitySerialize(
  WalletAttestationEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.expiresAtMillis);
  writer.writeString(offsets[1], object.lastRequestPayload);
  writer.writeString(offsets[2], object.policy);
}

WalletAttestationEntity _walletAttestationEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletAttestationEntity();
  object.expiresAtMillis = reader.readLongOrNull(offsets[0]);
  object.id = id;
  object.lastRequestPayload = reader.readStringOrNull(offsets[1]);
  object.policy = reader.readStringOrNull(offsets[2]);
  return object;
}

P _walletAttestationEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletAttestationEntityGetId(WalletAttestationEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletAttestationEntityGetLinks(
  WalletAttestationEntity object,
) {
  return [];
}

void _walletAttestationEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletAttestationEntity object,
) {
  object.id = id;
}

extension WalletAttestationEntityQueryWhereSort
    on QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QWhere> {
  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletAttestationEntityQueryWhere
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
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
}

extension WalletAttestationEntityQueryFilter
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  expiresAtMillisIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'expiresAtMillis'),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  expiresAtMillisIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'expiresAtMillis'),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  expiresAtMillisEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'expiresAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  expiresAtMillisGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'expiresAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  expiresAtMillisLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'expiresAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  expiresAtMillisBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'expiresAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
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
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastRequestPayload'),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastRequestPayload'),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lastRequestPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastRequestPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastRequestPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastRequestPayload',
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
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'lastRequestPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'lastRequestPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'lastRequestPayload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'lastRequestPayload',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastRequestPayload', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  lastRequestPayloadIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'lastRequestPayload', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'policy'),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'policy'),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'policy',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'policy',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'policy',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'policy',
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
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'policy',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'policy',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'policy',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'policy',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'policy', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAttestationEntity,
    WalletAttestationEntity,
    QAfterFilterCondition
  >
  policyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'policy', value: ''),
      );
    });
  }
}

extension WalletAttestationEntityQueryObject
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QFilterCondition
        > {}

extension WalletAttestationEntityQueryLinks
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QFilterCondition
        > {}

extension WalletAttestationEntityQuerySortBy
    on QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QSortBy> {
  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  sortByExpiresAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAtMillis', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  sortByExpiresAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAtMillis', Sort.desc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  sortByLastRequestPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRequestPayload', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  sortByLastRequestPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRequestPayload', Sort.desc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  sortByPolicy() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'policy', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  sortByPolicyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'policy', Sort.desc);
    });
  }
}

extension WalletAttestationEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QSortThenBy
        > {
  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByExpiresAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAtMillis', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByExpiresAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAtMillis', Sort.desc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByLastRequestPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRequestPayload', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByLastRequestPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRequestPayload', Sort.desc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByPolicy() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'policy', Sort.asc);
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QAfterSortBy>
  thenByPolicyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'policy', Sort.desc);
    });
  }
}

extension WalletAttestationEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QDistinct
        > {
  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QDistinct>
  distinctByExpiresAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'expiresAtMillis');
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QDistinct>
  distinctByLastRequestPayload({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'lastRequestPayload',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<WalletAttestationEntity, WalletAttestationEntity, QDistinct>
  distinctByPolicy({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'policy', caseSensitive: caseSensitive);
    });
  }
}

extension WalletAttestationEntityQueryProperty
    on
        QueryBuilder<
          WalletAttestationEntity,
          WalletAttestationEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletAttestationEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletAttestationEntity, int?, QQueryOperations>
  expiresAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'expiresAtMillis');
    });
  }

  QueryBuilder<WalletAttestationEntity, String?, QQueryOperations>
  lastRequestPayloadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastRequestPayload');
    });
  }

  QueryBuilder<WalletAttestationEntity, String?, QQueryOperations>
  policyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'policy');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletAccountBalanceSnapshotEntityCollection on Isar {
  IsarCollection<WalletAccountBalanceSnapshotEntity>
  get walletAccountBalanceSnapshotEntitys => this.collection();
}

const WalletAccountBalanceSnapshotEntitySchema = CollectionSchema(
  name: r'WalletAccountBalanceSnapshotEntity',
  id: 9168480637758939913,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'payloadJson': PropertySchema(
      id: 1,
      name: r'payloadJson',
      type: IsarType.string,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 2,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _walletAccountBalanceSnapshotEntityEstimateSize,
  serialize: _walletAccountBalanceSnapshotEntitySerialize,
  deserialize: _walletAccountBalanceSnapshotEntityDeserialize,
  deserializeProp: _walletAccountBalanceSnapshotEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'accountId': IndexSchema(
      id: -1591555361937770434,
      name: r'accountId',
      unique: true,
      replace: true,
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

  getId: _walletAccountBalanceSnapshotEntityGetId,
  getLinks: _walletAccountBalanceSnapshotEntityGetLinks,
  attach: _walletAccountBalanceSnapshotEntityAttach,
  version: '3.3.2',
);

int _walletAccountBalanceSnapshotEntityEstimateSize(
  WalletAccountBalanceSnapshotEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  bytesCount += 3 + object.payloadJson.length * 3;
  return bytesCount;
}

void _walletAccountBalanceSnapshotEntitySerialize(
  WalletAccountBalanceSnapshotEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.payloadJson);
  writer.writeLong(offsets[2], object.updatedAtMillis);
}

WalletAccountBalanceSnapshotEntity
_walletAccountBalanceSnapshotEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletAccountBalanceSnapshotEntity();
  object.accountId = reader.readString(offsets[0]);
  object.id = id;
  object.payloadJson = reader.readString(offsets[1]);
  object.updatedAtMillis = reader.readLong(offsets[2]);
  return object;
}

P _walletAccountBalanceSnapshotEntityDeserializeProp<P>(
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
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletAccountBalanceSnapshotEntityGetId(
  WalletAccountBalanceSnapshotEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletAccountBalanceSnapshotEntityGetLinks(
  WalletAccountBalanceSnapshotEntity object,
) {
  return [];
}

void _walletAccountBalanceSnapshotEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletAccountBalanceSnapshotEntity object,
) {
  object.id = id;
}

extension WalletAccountBalanceSnapshotEntityByIndex
    on IsarCollection<WalletAccountBalanceSnapshotEntity> {
  Future<WalletAccountBalanceSnapshotEntity?> getByAccountId(String accountId) {
    return getByIndex(r'accountId', [accountId]);
  }

  WalletAccountBalanceSnapshotEntity? getByAccountIdSync(String accountId) {
    return getByIndexSync(r'accountId', [accountId]);
  }

  Future<bool> deleteByAccountId(String accountId) {
    return deleteByIndex(r'accountId', [accountId]);
  }

  bool deleteByAccountIdSync(String accountId) {
    return deleteByIndexSync(r'accountId', [accountId]);
  }

  Future<List<WalletAccountBalanceSnapshotEntity?>> getAllByAccountId(
    List<String> accountIdValues,
  ) {
    final values = accountIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'accountId', values);
  }

  List<WalletAccountBalanceSnapshotEntity?> getAllByAccountIdSync(
    List<String> accountIdValues,
  ) {
    final values = accountIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'accountId', values);
  }

  Future<int> deleteAllByAccountId(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'accountId', values);
  }

  int deleteAllByAccountIdSync(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'accountId', values);
  }

  Future<Id> putByAccountId(WalletAccountBalanceSnapshotEntity object) {
    return putByIndex(r'accountId', object);
  }

  Id putByAccountIdSync(
    WalletAccountBalanceSnapshotEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'accountId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByAccountId(
    List<WalletAccountBalanceSnapshotEntity> objects,
  ) {
    return putAllByIndex(r'accountId', objects);
  }

  List<Id> putAllByAccountIdSync(
    List<WalletAccountBalanceSnapshotEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'accountId', objects, saveLinks: saveLinks);
  }
}

extension WalletAccountBalanceSnapshotEntityQueryWhereSort
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QWhere
        > {
  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletAccountBalanceSnapshotEntityQueryWhere
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterWhereClause
  >
  accountIdEqualTo(String accountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'accountId', value: [accountId]),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterWhereClause
  >
  accountIdNotEqualTo(String accountId) {
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

extension WalletAccountBalanceSnapshotEntityQueryFilter
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
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

extension WalletAccountBalanceSnapshotEntityQueryObject
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QFilterCondition
        > {}

extension WalletAccountBalanceSnapshotEntityQueryLinks
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QFilterCondition
        > {}

extension WalletAccountBalanceSnapshotEntityQuerySortBy
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletAccountBalanceSnapshotEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletAccountBalanceSnapshotEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QDistinct
  >
  distinctByAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QDistinct
  >
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletAccountBalanceSnapshotEntity,
    WalletAccountBalanceSnapshotEntity,
    QDistinct
  >
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension WalletAccountBalanceSnapshotEntityQueryProperty
    on
        QueryBuilder<
          WalletAccountBalanceSnapshotEntity,
          WalletAccountBalanceSnapshotEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletAccountBalanceSnapshotEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletAccountBalanceSnapshotEntity, String, QQueryOperations>
  accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<WalletAccountBalanceSnapshotEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }

  QueryBuilder<WalletAccountBalanceSnapshotEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletPersonalMultisigStateEntityCollection on Isar {
  IsarCollection<WalletPersonalMultisigStateEntity>
  get walletPersonalMultisigStateEntitys => this.collection();
}

const WalletPersonalMultisigStateEntitySchema = CollectionSchema(
  name: r'WalletPersonalMultisigStateEntity',
  id: 8188823230043134314,
  properties: {
    r'detailJson': PropertySchema(
      id: 0,
      name: r'detailJson',
      type: IsarType.string,
    ),
    r'detailUpdatedAtMillis': PropertySchema(
      id: 1,
      name: r'detailUpdatedAtMillis',
      type: IsarType.long,
    ),
    r'lastSyncAtMillis': PropertySchema(
      id: 2,
      name: r'lastSyncAtMillis',
      type: IsarType.long,
    ),
    r'personalAccountId': PropertySchema(
      id: 3,
      name: r'personalAccountId',
      type: IsarType.string,
    ),
    r'status': PropertySchema(id: 4, name: r'status', type: IsarType.string),
  },

  estimateSize: _walletPersonalMultisigStateEntityEstimateSize,
  serialize: _walletPersonalMultisigStateEntitySerialize,
  deserialize: _walletPersonalMultisigStateEntityDeserialize,
  deserializeProp: _walletPersonalMultisigStateEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'personalAccountId': IndexSchema(
      id: 8622025977711198945,
      name: r'personalAccountId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'personalAccountId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletPersonalMultisigStateEntityGetId,
  getLinks: _walletPersonalMultisigStateEntityGetLinks,
  attach: _walletPersonalMultisigStateEntityAttach,
  version: '3.3.2',
);

int _walletPersonalMultisigStateEntityEstimateSize(
  WalletPersonalMultisigStateEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.detailJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.personalAccountId.length * 3;
  {
    final value = object.status;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _walletPersonalMultisigStateEntitySerialize(
  WalletPersonalMultisigStateEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.detailJson);
  writer.writeLong(offsets[1], object.detailUpdatedAtMillis);
  writer.writeLong(offsets[2], object.lastSyncAtMillis);
  writer.writeString(offsets[3], object.personalAccountId);
  writer.writeString(offsets[4], object.status);
}

WalletPersonalMultisigStateEntity _walletPersonalMultisigStateEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletPersonalMultisigStateEntity();
  object.detailJson = reader.readStringOrNull(offsets[0]);
  object.detailUpdatedAtMillis = reader.readLongOrNull(offsets[1]);
  object.id = id;
  object.lastSyncAtMillis = reader.readLongOrNull(offsets[2]);
  object.personalAccountId = reader.readString(offsets[3]);
  object.status = reader.readStringOrNull(offsets[4]);
  return object;
}

P _walletPersonalMultisigStateEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readLongOrNull(offset)) as P;
    case 2:
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletPersonalMultisigStateEntityGetId(
  WalletPersonalMultisigStateEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletPersonalMultisigStateEntityGetLinks(
  WalletPersonalMultisigStateEntity object,
) {
  return [];
}

void _walletPersonalMultisigStateEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletPersonalMultisigStateEntity object,
) {
  object.id = id;
}

extension WalletPersonalMultisigStateEntityByIndex
    on IsarCollection<WalletPersonalMultisigStateEntity> {
  Future<WalletPersonalMultisigStateEntity?> getByPersonalAccountId(
    String personalAccountId,
  ) {
    return getByIndex(r'personalAccountId', [personalAccountId]);
  }

  WalletPersonalMultisigStateEntity? getByPersonalAccountIdSync(
    String personalAccountId,
  ) {
    return getByIndexSync(r'personalAccountId', [personalAccountId]);
  }

  Future<bool> deleteByPersonalAccountId(String personalAccountId) {
    return deleteByIndex(r'personalAccountId', [personalAccountId]);
  }

  bool deleteByPersonalAccountIdSync(String personalAccountId) {
    return deleteByIndexSync(r'personalAccountId', [personalAccountId]);
  }

  Future<List<WalletPersonalMultisigStateEntity?>> getAllByPersonalAccountId(
    List<String> personalAccountIdValues,
  ) {
    final values = personalAccountIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'personalAccountId', values);
  }

  List<WalletPersonalMultisigStateEntity?> getAllByPersonalAccountIdSync(
    List<String> personalAccountIdValues,
  ) {
    final values = personalAccountIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'personalAccountId', values);
  }

  Future<int> deleteAllByPersonalAccountId(
    List<String> personalAccountIdValues,
  ) {
    final values = personalAccountIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'personalAccountId', values);
  }

  int deleteAllByPersonalAccountIdSync(List<String> personalAccountIdValues) {
    final values = personalAccountIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'personalAccountId', values);
  }

  Future<Id> putByPersonalAccountId(WalletPersonalMultisigStateEntity object) {
    return putByIndex(r'personalAccountId', object);
  }

  Id putByPersonalAccountIdSync(
    WalletPersonalMultisigStateEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'personalAccountId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPersonalAccountId(
    List<WalletPersonalMultisigStateEntity> objects,
  ) {
    return putAllByIndex(r'personalAccountId', objects);
  }

  List<Id> putAllByPersonalAccountIdSync(
    List<WalletPersonalMultisigStateEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'personalAccountId',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension WalletPersonalMultisigStateEntityQueryWhereSort
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QWhere
        > {
  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletPersonalMultisigStateEntityQueryWhere
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterWhereClause
  >
  personalAccountIdEqualTo(String personalAccountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'personalAccountId',
          value: [personalAccountId],
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterWhereClause
  >
  personalAccountIdNotEqualTo(String personalAccountId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId',
                lower: [],
                upper: [personalAccountId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId',
                lower: [personalAccountId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId',
                lower: [personalAccountId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId',
                lower: [],
                upper: [personalAccountId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension WalletPersonalMultisigStateEntityQueryFilter
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'detailJson'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'detailJson'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'detailJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'detailJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'detailJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'detailJson',
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'detailJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'detailJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'detailJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'detailJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'detailJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'detailJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailUpdatedAtMillisIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'detailUpdatedAtMillis'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailUpdatedAtMillisIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'detailUpdatedAtMillis'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailUpdatedAtMillisEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'detailUpdatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailUpdatedAtMillisGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'detailUpdatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailUpdatedAtMillisLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'detailUpdatedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  detailUpdatedAtMillisBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'detailUpdatedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  lastSyncAtMillisIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastSyncAtMillis'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  lastSyncAtMillisIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastSyncAtMillis'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  lastSyncAtMillisEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastSyncAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  lastSyncAtMillisGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastSyncAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  lastSyncAtMillisLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastSyncAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  lastSyncAtMillisBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastSyncAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'personalAccountId',
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'personalAccountId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'personalAccountId', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  personalAccountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'personalAccountId', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'status'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'status'),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'status',
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
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'status',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'status', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterFilterCondition
  >
  statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'status', value: ''),
      );
    });
  }
}

extension WalletPersonalMultisigStateEntityQueryObject
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QFilterCondition
        > {}

extension WalletPersonalMultisigStateEntityQueryLinks
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QFilterCondition
        > {}

extension WalletPersonalMultisigStateEntityQuerySortBy
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByDetailJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByDetailJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByDetailUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailUpdatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByDetailUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailUpdatedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByLastSyncAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByLastSyncAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByPersonalAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByPersonalAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }
}

extension WalletPersonalMultisigStateEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByDetailJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByDetailJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByDetailUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailUpdatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByDetailUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailUpdatedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByLastSyncAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByLastSyncAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByPersonalAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByPersonalAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QAfterSortBy
  >
  thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }
}

extension WalletPersonalMultisigStateEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QDistinct
  >
  distinctByDetailJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'detailJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QDistinct
  >
  distinctByDetailUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'detailUpdatedAtMillis');
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QDistinct
  >
  distinctByLastSyncAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAtMillis');
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QDistinct
  >
  distinctByPersonalAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'personalAccountId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigStateEntity,
    WalletPersonalMultisigStateEntity,
    QDistinct
  >
  distinctByStatus({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }
}

extension WalletPersonalMultisigStateEntityQueryProperty
    on
        QueryBuilder<
          WalletPersonalMultisigStateEntity,
          WalletPersonalMultisigStateEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletPersonalMultisigStateEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletPersonalMultisigStateEntity, String?, QQueryOperations>
  detailJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'detailJson');
    });
  }

  QueryBuilder<WalletPersonalMultisigStateEntity, int?, QQueryOperations>
  detailUpdatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'detailUpdatedAtMillis');
    });
  }

  QueryBuilder<WalletPersonalMultisigStateEntity, int?, QQueryOperations>
  lastSyncAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAtMillis');
    });
  }

  QueryBuilder<WalletPersonalMultisigStateEntity, String, QQueryOperations>
  personalAccountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'personalAccountId');
    });
  }

  QueryBuilder<WalletPersonalMultisigStateEntity, String?, QQueryOperations>
  statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletPersonalMultisigDiscoveryEntityCollection on Isar {
  IsarCollection<WalletPersonalMultisigDiscoveryEntity>
  get walletPersonalMultisigDiscoveryEntitys => this.collection();
}

const WalletPersonalMultisigDiscoveryEntitySchema = CollectionSchema(
  name: r'WalletPersonalMultisigDiscoveryEntity',
  id: -2725940258924644165,
  properties: {
    r'updatedAtMillis': PropertySchema(
      id: 0,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
    r'walletFingerprint': PropertySchema(
      id: 1,
      name: r'walletFingerprint',
      type: IsarType.string,
    ),
  },

  estimateSize: _walletPersonalMultisigDiscoveryEntityEstimateSize,
  serialize: _walletPersonalMultisigDiscoveryEntitySerialize,
  deserialize: _walletPersonalMultisigDiscoveryEntityDeserialize,
  deserializeProp: _walletPersonalMultisigDiscoveryEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _walletPersonalMultisigDiscoveryEntityGetId,
  getLinks: _walletPersonalMultisigDiscoveryEntityGetLinks,
  attach: _walletPersonalMultisigDiscoveryEntityAttach,
  version: '3.3.2',
);

int _walletPersonalMultisigDiscoveryEntityEstimateSize(
  WalletPersonalMultisigDiscoveryEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.walletFingerprint.length * 3;
  return bytesCount;
}

void _walletPersonalMultisigDiscoveryEntitySerialize(
  WalletPersonalMultisigDiscoveryEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.updatedAtMillis);
  writer.writeString(offsets[1], object.walletFingerprint);
}

WalletPersonalMultisigDiscoveryEntity
_walletPersonalMultisigDiscoveryEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletPersonalMultisigDiscoveryEntity();
  object.id = id;
  object.updatedAtMillis = reader.readLong(offsets[0]);
  object.walletFingerprint = reader.readString(offsets[1]);
  return object;
}

P _walletPersonalMultisigDiscoveryEntityDeserializeProp<P>(
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
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletPersonalMultisigDiscoveryEntityGetId(
  WalletPersonalMultisigDiscoveryEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletPersonalMultisigDiscoveryEntityGetLinks(
  WalletPersonalMultisigDiscoveryEntity object,
) {
  return [];
}

void _walletPersonalMultisigDiscoveryEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletPersonalMultisigDiscoveryEntity object,
) {
  object.id = id;
}

extension WalletPersonalMultisigDiscoveryEntityQueryWhereSort
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QWhere
        > {
  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletPersonalMultisigDiscoveryEntityQueryWhere
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
}

extension WalletPersonalMultisigDiscoveryEntityQueryFilter
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
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

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'walletFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'walletFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'walletFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'walletFingerprint',
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
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'walletFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'walletFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'walletFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'walletFingerprint',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'walletFingerprint', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterFilterCondition
  >
  walletFingerprintIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'walletFingerprint', value: ''),
      );
    });
  }
}

extension WalletPersonalMultisigDiscoveryEntityQueryObject
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QFilterCondition
        > {}

extension WalletPersonalMultisigDiscoveryEntityQueryLinks
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QFilterCondition
        > {}

extension WalletPersonalMultisigDiscoveryEntityQuerySortBy
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  sortByWalletFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'walletFingerprint', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  sortByWalletFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'walletFingerprint', Sort.desc);
    });
  }
}

extension WalletPersonalMultisigDiscoveryEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  thenByWalletFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'walletFingerprint', Sort.asc);
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QAfterSortBy
  >
  thenByWalletFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'walletFingerprint', Sort.desc);
    });
  }
}

extension WalletPersonalMultisigDiscoveryEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QDistinct
  >
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }

  QueryBuilder<
    WalletPersonalMultisigDiscoveryEntity,
    WalletPersonalMultisigDiscoveryEntity,
    QDistinct
  >
  distinctByWalletFingerprint({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'walletFingerprint',
        caseSensitive: caseSensitive,
      );
    });
  }
}

extension WalletPersonalMultisigDiscoveryEntityQueryProperty
    on
        QueryBuilder<
          WalletPersonalMultisigDiscoveryEntity,
          WalletPersonalMultisigDiscoveryEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletPersonalMultisigDiscoveryEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletPersonalMultisigDiscoveryEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }

  QueryBuilder<WalletPersonalMultisigDiscoveryEntity, String, QQueryOperations>
  walletFingerprintProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'walletFingerprint');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletProposalSummaryEntityCollection on Isar {
  IsarCollection<WalletProposalSummaryEntity>
  get walletProposalSummaryEntitys => this.collection();
}

const WalletProposalSummaryEntitySchema = CollectionSchema(
  name: r'WalletProposalSummaryEntity',
  id: 4788448962574646216,
  properties: {
    r'payloadJson': PropertySchema(
      id: 0,
      name: r'payloadJson',
      type: IsarType.string,
    ),
    r'proposalId': PropertySchema(
      id: 1,
      name: r'proposalId',
      type: IsarType.long,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 2,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _walletProposalSummaryEntityEstimateSize,
  serialize: _walletProposalSummaryEntitySerialize,
  deserialize: _walletProposalSummaryEntityDeserialize,
  deserializeProp: _walletProposalSummaryEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'proposalId': IndexSchema(
      id: -3329764516456808925,
      name: r'proposalId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'proposalId',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletProposalSummaryEntityGetId,
  getLinks: _walletProposalSummaryEntityGetLinks,
  attach: _walletProposalSummaryEntityAttach,
  version: '3.3.2',
);

int _walletProposalSummaryEntityEstimateSize(
  WalletProposalSummaryEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payloadJson.length * 3;
  return bytesCount;
}

void _walletProposalSummaryEntitySerialize(
  WalletProposalSummaryEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.payloadJson);
  writer.writeLong(offsets[1], object.proposalId);
  writer.writeLong(offsets[2], object.updatedAtMillis);
}

WalletProposalSummaryEntity _walletProposalSummaryEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletProposalSummaryEntity();
  object.id = id;
  object.payloadJson = reader.readString(offsets[0]);
  object.proposalId = reader.readLong(offsets[1]);
  object.updatedAtMillis = reader.readLong(offsets[2]);
  return object;
}

P _walletProposalSummaryEntityDeserializeProp<P>(
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
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletProposalSummaryEntityGetId(WalletProposalSummaryEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletProposalSummaryEntityGetLinks(
  WalletProposalSummaryEntity object,
) {
  return [];
}

void _walletProposalSummaryEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletProposalSummaryEntity object,
) {
  object.id = id;
}

extension WalletProposalSummaryEntityByIndex
    on IsarCollection<WalletProposalSummaryEntity> {
  Future<WalletProposalSummaryEntity?> getByProposalId(int proposalId) {
    return getByIndex(r'proposalId', [proposalId]);
  }

  WalletProposalSummaryEntity? getByProposalIdSync(int proposalId) {
    return getByIndexSync(r'proposalId', [proposalId]);
  }

  Future<bool> deleteByProposalId(int proposalId) {
    return deleteByIndex(r'proposalId', [proposalId]);
  }

  bool deleteByProposalIdSync(int proposalId) {
    return deleteByIndexSync(r'proposalId', [proposalId]);
  }

  Future<List<WalletProposalSummaryEntity?>> getAllByProposalId(
    List<int> proposalIdValues,
  ) {
    final values = proposalIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'proposalId', values);
  }

  List<WalletProposalSummaryEntity?> getAllByProposalIdSync(
    List<int> proposalIdValues,
  ) {
    final values = proposalIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'proposalId', values);
  }

  Future<int> deleteAllByProposalId(List<int> proposalIdValues) {
    final values = proposalIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'proposalId', values);
  }

  int deleteAllByProposalIdSync(List<int> proposalIdValues) {
    final values = proposalIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'proposalId', values);
  }

  Future<Id> putByProposalId(WalletProposalSummaryEntity object) {
    return putByIndex(r'proposalId', object);
  }

  Id putByProposalIdSync(
    WalletProposalSummaryEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'proposalId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByProposalId(
    List<WalletProposalSummaryEntity> objects,
  ) {
    return putAllByIndex(r'proposalId', objects);
  }

  List<Id> putAllByProposalIdSync(
    List<WalletProposalSummaryEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'proposalId', objects, saveLinks: saveLinks);
  }
}

extension WalletProposalSummaryEntityQueryWhereSort
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QWhere
        > {
  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhere
  >
  anyProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'proposalId'),
      );
    });
  }
}

extension WalletProposalSummaryEntityQueryWhere
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhereClause
  >
  proposalIdEqualTo(int proposalId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'proposalId', value: [proposalId]),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhereClause
  >
  proposalIdNotEqualTo(int proposalId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalId',
                lower: [],
                upper: [proposalId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalId',
                lower: [proposalId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalId',
                lower: [proposalId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalId',
                lower: [],
                upper: [proposalId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhereClause
  >
  proposalIdGreaterThan(int proposalId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'proposalId',
          lower: [proposalId],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhereClause
  >
  proposalIdLessThan(int proposalId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'proposalId',
          lower: [],
          upper: [proposalId],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterWhereClause
  >
  proposalIdBetween(
    int lowerProposalId,
    int upperProposalId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'proposalId',
          lower: [lowerProposalId],
          includeLower: includeLower,
          upper: [upperProposalId],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension WalletProposalSummaryEntityQueryFilter
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  proposalIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'proposalId', value: value),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  proposalIdGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'proposalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  proposalIdLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'proposalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterFilterCondition
  >
  proposalIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'proposalId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
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

extension WalletProposalSummaryEntityQueryObject
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QFilterCondition
        > {}

extension WalletProposalSummaryEntityQueryLinks
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QFilterCondition
        > {}

extension WalletProposalSummaryEntityQuerySortBy
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  sortByProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  sortByProposalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletProposalSummaryEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByProposalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletProposalSummaryEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QDistinct
  >
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QDistinct
  >
  distinctByProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'proposalId');
    });
  }

  QueryBuilder<
    WalletProposalSummaryEntity,
    WalletProposalSummaryEntity,
    QDistinct
  >
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension WalletProposalSummaryEntityQueryProperty
    on
        QueryBuilder<
          WalletProposalSummaryEntity,
          WalletProposalSummaryEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletProposalSummaryEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletProposalSummaryEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }

  QueryBuilder<WalletProposalSummaryEntity, int, QQueryOperations>
  proposalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'proposalId');
    });
  }

  QueryBuilder<WalletProposalSummaryEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletProposalIndexEntityCollection on Isar {
  IsarCollection<WalletProposalIndexEntity> get walletProposalIndexEntitys =>
      this.collection();
}

const WalletProposalIndexEntitySchema = CollectionSchema(
  name: r'WalletProposalIndexEntity',
  id: -6458255306946374770,
  properties: {
    r'institutionCidNumber': PropertySchema(
      id: 0,
      name: r'institutionCidNumber',
      type: IsarType.string,
    ),
    r'payloadJson': PropertySchema(
      id: 1,
      name: r'payloadJson',
      type: IsarType.string,
    ),
    r'syncedAtMillis': PropertySchema(
      id: 2,
      name: r'syncedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _walletProposalIndexEntityEstimateSize,
  serialize: _walletProposalIndexEntitySerialize,
  deserialize: _walletProposalIndexEntityDeserialize,
  deserializeProp: _walletProposalIndexEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'institutionCidNumber': IndexSchema(
      id: 1201115748929989764,
      name: r'institutionCidNumber',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'institutionCidNumber',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletProposalIndexEntityGetId,
  getLinks: _walletProposalIndexEntityGetLinks,
  attach: _walletProposalIndexEntityAttach,
  version: '3.3.2',
);

int _walletProposalIndexEntityEstimateSize(
  WalletProposalIndexEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.institutionCidNumber.length * 3;
  bytesCount += 3 + object.payloadJson.length * 3;
  return bytesCount;
}

void _walletProposalIndexEntitySerialize(
  WalletProposalIndexEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.institutionCidNumber);
  writer.writeString(offsets[1], object.payloadJson);
  writer.writeLong(offsets[2], object.syncedAtMillis);
}

WalletProposalIndexEntity _walletProposalIndexEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletProposalIndexEntity();
  object.id = id;
  object.institutionCidNumber = reader.readString(offsets[0]);
  object.payloadJson = reader.readString(offsets[1]);
  object.syncedAtMillis = reader.readLong(offsets[2]);
  return object;
}

P _walletProposalIndexEntityDeserializeProp<P>(
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
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletProposalIndexEntityGetId(WalletProposalIndexEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletProposalIndexEntityGetLinks(
  WalletProposalIndexEntity object,
) {
  return [];
}

void _walletProposalIndexEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletProposalIndexEntity object,
) {
  object.id = id;
}

extension WalletProposalIndexEntityByIndex
    on IsarCollection<WalletProposalIndexEntity> {
  Future<WalletProposalIndexEntity?> getByInstitutionCidNumber(
    String institutionCidNumber,
  ) {
    return getByIndex(r'institutionCidNumber', [institutionCidNumber]);
  }

  WalletProposalIndexEntity? getByInstitutionCidNumberSync(
    String institutionCidNumber,
  ) {
    return getByIndexSync(r'institutionCidNumber', [institutionCidNumber]);
  }

  Future<bool> deleteByInstitutionCidNumber(String institutionCidNumber) {
    return deleteByIndex(r'institutionCidNumber', [institutionCidNumber]);
  }

  bool deleteByInstitutionCidNumberSync(String institutionCidNumber) {
    return deleteByIndexSync(r'institutionCidNumber', [institutionCidNumber]);
  }

  Future<List<WalletProposalIndexEntity?>> getAllByInstitutionCidNumber(
    List<String> institutionCidNumberValues,
  ) {
    final values = institutionCidNumberValues.map((e) => [e]).toList();
    return getAllByIndex(r'institutionCidNumber', values);
  }

  List<WalletProposalIndexEntity?> getAllByInstitutionCidNumberSync(
    List<String> institutionCidNumberValues,
  ) {
    final values = institutionCidNumberValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'institutionCidNumber', values);
  }

  Future<int> deleteAllByInstitutionCidNumber(
    List<String> institutionCidNumberValues,
  ) {
    final values = institutionCidNumberValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'institutionCidNumber', values);
  }

  int deleteAllByInstitutionCidNumberSync(
    List<String> institutionCidNumberValues,
  ) {
    final values = institutionCidNumberValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'institutionCidNumber', values);
  }

  Future<Id> putByInstitutionCidNumber(WalletProposalIndexEntity object) {
    return putByIndex(r'institutionCidNumber', object);
  }

  Id putByInstitutionCidNumberSync(
    WalletProposalIndexEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(
      r'institutionCidNumber',
      object,
      saveLinks: saveLinks,
    );
  }

  Future<List<Id>> putAllByInstitutionCidNumber(
    List<WalletProposalIndexEntity> objects,
  ) {
    return putAllByIndex(r'institutionCidNumber', objects);
  }

  List<Id> putAllByInstitutionCidNumberSync(
    List<WalletProposalIndexEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'institutionCidNumber',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension WalletProposalIndexEntityQueryWhereSort
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QWhere
        > {
  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletProposalIndexEntityQueryWhere
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterWhereClause
  >
  institutionCidNumberEqualTo(String institutionCidNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'institutionCidNumber',
          value: [institutionCidNumber],
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterWhereClause
  >
  institutionCidNumberNotEqualTo(String institutionCidNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'institutionCidNumber',
                lower: [],
                upper: [institutionCidNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'institutionCidNumber',
                lower: [institutionCidNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'institutionCidNumber',
                lower: [institutionCidNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'institutionCidNumber',
                lower: [],
                upper: [institutionCidNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension WalletProposalIndexEntityQueryFilter
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  syncedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  syncedAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'syncedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  syncedAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'syncedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterFilterCondition
  >
  syncedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'syncedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension WalletProposalIndexEntityQueryObject
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QFilterCondition
        > {}

extension WalletProposalIndexEntityQueryLinks
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QFilterCondition
        > {}

extension WalletProposalIndexEntityQuerySortBy
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  sortByInstitutionCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  sortByInstitutionCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  sortBySyncedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  sortBySyncedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedAtMillis', Sort.desc);
    });
  }
}

extension WalletProposalIndexEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenByInstitutionCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenByInstitutionCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionCidNumber', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenBySyncedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalIndexEntity,
    WalletProposalIndexEntity,
    QAfterSortBy
  >
  thenBySyncedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedAtMillis', Sort.desc);
    });
  }
}

extension WalletProposalIndexEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QDistinct
        > {
  QueryBuilder<WalletProposalIndexEntity, WalletProposalIndexEntity, QDistinct>
  distinctByInstitutionCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'institutionCidNumber',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<WalletProposalIndexEntity, WalletProposalIndexEntity, QDistinct>
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<WalletProposalIndexEntity, WalletProposalIndexEntity, QDistinct>
  distinctBySyncedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncedAtMillis');
    });
  }
}

extension WalletProposalIndexEntityQueryProperty
    on
        QueryBuilder<
          WalletProposalIndexEntity,
          WalletProposalIndexEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletProposalIndexEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletProposalIndexEntity, String, QQueryOperations>
  institutionCidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'institutionCidNumber');
    });
  }

  QueryBuilder<WalletProposalIndexEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }

  QueryBuilder<WalletProposalIndexEntity, int, QQueryOperations>
  syncedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletProposalDetailEntityCollection on Isar {
  IsarCollection<WalletProposalDetailEntity> get walletProposalDetailEntitys =>
      this.collection();
}

const WalletProposalDetailEntitySchema = CollectionSchema(
  name: r'WalletProposalDetailEntity',
  id: -8714071496325104634,
  properties: {
    r'isFinal': PropertySchema(id: 0, name: r'isFinal', type: IsarType.bool),
    r'payloadJson': PropertySchema(
      id: 1,
      name: r'payloadJson',
      type: IsarType.string,
    ),
    r'proposalKey': PropertySchema(
      id: 2,
      name: r'proposalKey',
      type: IsarType.string,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 3,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _walletProposalDetailEntityEstimateSize,
  serialize: _walletProposalDetailEntitySerialize,
  deserialize: _walletProposalDetailEntityDeserialize,
  deserializeProp: _walletProposalDetailEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'proposalKey': IndexSchema(
      id: 6651127227922992106,
      name: r'proposalKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'proposalKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletProposalDetailEntityGetId,
  getLinks: _walletProposalDetailEntityGetLinks,
  attach: _walletProposalDetailEntityAttach,
  version: '3.3.2',
);

int _walletProposalDetailEntityEstimateSize(
  WalletProposalDetailEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payloadJson.length * 3;
  bytesCount += 3 + object.proposalKey.length * 3;
  return bytesCount;
}

void _walletProposalDetailEntitySerialize(
  WalletProposalDetailEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.isFinal);
  writer.writeString(offsets[1], object.payloadJson);
  writer.writeString(offsets[2], object.proposalKey);
  writer.writeLong(offsets[3], object.updatedAtMillis);
}

WalletProposalDetailEntity _walletProposalDetailEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletProposalDetailEntity();
  object.id = id;
  object.isFinal = reader.readBool(offsets[0]);
  object.payloadJson = reader.readString(offsets[1]);
  object.proposalKey = reader.readString(offsets[2]);
  object.updatedAtMillis = reader.readLong(offsets[3]);
  return object;
}

P _walletProposalDetailEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletProposalDetailEntityGetId(WalletProposalDetailEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletProposalDetailEntityGetLinks(
  WalletProposalDetailEntity object,
) {
  return [];
}

void _walletProposalDetailEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletProposalDetailEntity object,
) {
  object.id = id;
}

extension WalletProposalDetailEntityByIndex
    on IsarCollection<WalletProposalDetailEntity> {
  Future<WalletProposalDetailEntity?> getByProposalKey(String proposalKey) {
    return getByIndex(r'proposalKey', [proposalKey]);
  }

  WalletProposalDetailEntity? getByProposalKeySync(String proposalKey) {
    return getByIndexSync(r'proposalKey', [proposalKey]);
  }

  Future<bool> deleteByProposalKey(String proposalKey) {
    return deleteByIndex(r'proposalKey', [proposalKey]);
  }

  bool deleteByProposalKeySync(String proposalKey) {
    return deleteByIndexSync(r'proposalKey', [proposalKey]);
  }

  Future<List<WalletProposalDetailEntity?>> getAllByProposalKey(
    List<String> proposalKeyValues,
  ) {
    final values = proposalKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'proposalKey', values);
  }

  List<WalletProposalDetailEntity?> getAllByProposalKeySync(
    List<String> proposalKeyValues,
  ) {
    final values = proposalKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'proposalKey', values);
  }

  Future<int> deleteAllByProposalKey(List<String> proposalKeyValues) {
    final values = proposalKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'proposalKey', values);
  }

  int deleteAllByProposalKeySync(List<String> proposalKeyValues) {
    final values = proposalKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'proposalKey', values);
  }

  Future<Id> putByProposalKey(WalletProposalDetailEntity object) {
    return putByIndex(r'proposalKey', object);
  }

  Id putByProposalKeySync(
    WalletProposalDetailEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'proposalKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByProposalKey(
    List<WalletProposalDetailEntity> objects,
  ) {
    return putAllByIndex(r'proposalKey', objects);
  }

  List<Id> putAllByProposalKeySync(
    List<WalletProposalDetailEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'proposalKey', objects, saveLinks: saveLinks);
  }
}

extension WalletProposalDetailEntityQueryWhereSort
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QWhere
        > {
  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletProposalDetailEntityQueryWhere
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterWhereClause
  >
  proposalKeyEqualTo(String proposalKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'proposalKey',
          value: [proposalKey],
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterWhereClause
  >
  proposalKeyNotEqualTo(String proposalKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalKey',
                lower: [],
                upper: [proposalKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalKey',
                lower: [proposalKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalKey',
                lower: [proposalKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'proposalKey',
                lower: [],
                upper: [proposalKey],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension WalletProposalDetailEntityQueryFilter
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  isFinalEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isFinal', value: value),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'proposalKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'proposalKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'proposalKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'proposalKey',
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'proposalKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'proposalKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'proposalKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'proposalKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'proposalKey', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterFilterCondition
  >
  proposalKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'proposalKey', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
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

extension WalletProposalDetailEntityQueryObject
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QFilterCondition
        > {}

extension WalletProposalDetailEntityQueryLinks
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QFilterCondition
        > {}

extension WalletProposalDetailEntityQuerySortBy
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByIsFinal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFinal', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByIsFinalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFinal', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByProposalKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalKey', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByProposalKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalKey', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletProposalDetailEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByIsFinal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFinal', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByIsFinalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFinal', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByProposalKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalKey', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByProposalKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalKey', Sort.desc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletProposalDetailEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QDistinct
  >
  distinctByIsFinal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isFinal');
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QDistinct
  >
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QDistinct
  >
  distinctByProposalKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'proposalKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletProposalDetailEntity,
    WalletProposalDetailEntity,
    QDistinct
  >
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension WalletProposalDetailEntityQueryProperty
    on
        QueryBuilder<
          WalletProposalDetailEntity,
          WalletProposalDetailEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletProposalDetailEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletProposalDetailEntity, bool, QQueryOperations>
  isFinalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isFinal');
    });
  }

  QueryBuilder<WalletProposalDetailEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }

  QueryBuilder<WalletProposalDetailEntity, String, QQueryOperations>
  proposalKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'proposalKey');
    });
  }

  QueryBuilder<WalletProposalDetailEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletLegislationSnapshotEntityCollection on Isar {
  IsarCollection<WalletLegislationSnapshotEntity>
  get walletLegislationSnapshotEntitys => this.collection();
}

const WalletLegislationSnapshotEntitySchema = CollectionSchema(
  name: r'WalletLegislationSnapshotEntity',
  id: -2623012805661519943,
  properties: {
    r'rawHex': PropertySchema(id: 0, name: r'rawHex', type: IsarType.string),
    r'stateKey': PropertySchema(
      id: 1,
      name: r'stateKey',
      type: IsarType.string,
    ),
    r'updatedAtMillis': PropertySchema(
      id: 2,
      name: r'updatedAtMillis',
      type: IsarType.long,
    ),
  },

  estimateSize: _walletLegislationSnapshotEntityEstimateSize,
  serialize: _walletLegislationSnapshotEntitySerialize,
  deserialize: _walletLegislationSnapshotEntityDeserialize,
  deserializeProp: _walletLegislationSnapshotEntityDeserializeProp,
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
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletLegislationSnapshotEntityGetId,
  getLinks: _walletLegislationSnapshotEntityGetLinks,
  attach: _walletLegislationSnapshotEntityAttach,
  version: '3.3.2',
);

int _walletLegislationSnapshotEntityEstimateSize(
  WalletLegislationSnapshotEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.rawHex.length * 3;
  bytesCount += 3 + object.stateKey.length * 3;
  return bytesCount;
}

void _walletLegislationSnapshotEntitySerialize(
  WalletLegislationSnapshotEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.rawHex);
  writer.writeString(offsets[1], object.stateKey);
  writer.writeLong(offsets[2], object.updatedAtMillis);
}

WalletLegislationSnapshotEntity _walletLegislationSnapshotEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletLegislationSnapshotEntity();
  object.id = id;
  object.rawHex = reader.readString(offsets[0]);
  object.stateKey = reader.readString(offsets[1]);
  object.updatedAtMillis = reader.readLong(offsets[2]);
  return object;
}

P _walletLegislationSnapshotEntityDeserializeProp<P>(
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
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletLegislationSnapshotEntityGetId(
  WalletLegislationSnapshotEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletLegislationSnapshotEntityGetLinks(
  WalletLegislationSnapshotEntity object,
) {
  return [];
}

void _walletLegislationSnapshotEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletLegislationSnapshotEntity object,
) {
  object.id = id;
}

extension WalletLegislationSnapshotEntityByIndex
    on IsarCollection<WalletLegislationSnapshotEntity> {
  Future<WalletLegislationSnapshotEntity?> getByStateKey(String stateKey) {
    return getByIndex(r'stateKey', [stateKey]);
  }

  WalletLegislationSnapshotEntity? getByStateKeySync(String stateKey) {
    return getByIndexSync(r'stateKey', [stateKey]);
  }

  Future<bool> deleteByStateKey(String stateKey) {
    return deleteByIndex(r'stateKey', [stateKey]);
  }

  bool deleteByStateKeySync(String stateKey) {
    return deleteByIndexSync(r'stateKey', [stateKey]);
  }

  Future<List<WalletLegislationSnapshotEntity?>> getAllByStateKey(
    List<String> stateKeyValues,
  ) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'stateKey', values);
  }

  List<WalletLegislationSnapshotEntity?> getAllByStateKeySync(
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

  Future<Id> putByStateKey(WalletLegislationSnapshotEntity object) {
    return putByIndex(r'stateKey', object);
  }

  Id putByStateKeySync(
    WalletLegislationSnapshotEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'stateKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByStateKey(
    List<WalletLegislationSnapshotEntity> objects,
  ) {
    return putAllByIndex(r'stateKey', objects);
  }

  List<Id> putAllByStateKeySync(
    List<WalletLegislationSnapshotEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'stateKey', objects, saveLinks: saveLinks);
  }
}

extension WalletLegislationSnapshotEntityQueryWhereSort
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QWhere
        > {
  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletLegislationSnapshotEntityQueryWhere
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
}

extension WalletLegislationSnapshotEntityQueryFilter
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'rawHex',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'rawHex',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'rawHex',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'rawHex',
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'rawHex',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'rawHex',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'rawHex',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'rawHex',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'rawHex', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterFilterCondition
  >
  rawHexIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'rawHex', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
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

extension WalletLegislationSnapshotEntityQueryObject
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QFilterCondition
        > {}

extension WalletLegislationSnapshotEntityQueryLinks
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QFilterCondition
        > {}

extension WalletLegislationSnapshotEntityQuerySortBy
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  sortByRawHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawHex', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  sortByRawHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawHex', Sort.desc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  sortByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  sortByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  sortByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletLegislationSnapshotEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByRawHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawHex', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByRawHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rawHex', Sort.desc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QAfterSortBy
  >
  thenByUpdatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAtMillis', Sort.desc);
    });
  }
}

extension WalletLegislationSnapshotEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QDistinct
  >
  distinctByRawHex({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rawHex', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QDistinct
  >
  distinctByStateKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stateKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletLegislationSnapshotEntity,
    WalletLegislationSnapshotEntity,
    QDistinct
  >
  distinctByUpdatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAtMillis');
    });
  }
}

extension WalletLegislationSnapshotEntityQueryProperty
    on
        QueryBuilder<
          WalletLegislationSnapshotEntity,
          WalletLegislationSnapshotEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletLegislationSnapshotEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletLegislationSnapshotEntity, String, QQueryOperations>
  rawHexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rawHex');
    });
  }

  QueryBuilder<WalletLegislationSnapshotEntity, String, QQueryOperations>
  stateKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stateKey');
    });
  }

  QueryBuilder<WalletLegislationSnapshotEntity, int, QQueryOperations>
  updatedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAtMillis');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletAdminActivationStateEntityCollection on Isar {
  IsarCollection<WalletAdminActivationStateEntity>
  get walletAdminActivationStateEntitys => this.collection();
}

const WalletAdminActivationStateEntitySchema = CollectionSchema(
  name: r'WalletAdminActivationStateEntity',
  id: -3651227439625847917,
  properties: {
    r'payloadJson': PropertySchema(
      id: 0,
      name: r'payloadJson',
      type: IsarType.string,
    ),
  },

  estimateSize: _walletAdminActivationStateEntityEstimateSize,
  serialize: _walletAdminActivationStateEntitySerialize,
  deserialize: _walletAdminActivationStateEntityDeserialize,
  deserializeProp: _walletAdminActivationStateEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _walletAdminActivationStateEntityGetId,
  getLinks: _walletAdminActivationStateEntityGetLinks,
  attach: _walletAdminActivationStateEntityAttach,
  version: '3.3.2',
);

int _walletAdminActivationStateEntityEstimateSize(
  WalletAdminActivationStateEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payloadJson.length * 3;
  return bytesCount;
}

void _walletAdminActivationStateEntitySerialize(
  WalletAdminActivationStateEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.payloadJson);
}

WalletAdminActivationStateEntity _walletAdminActivationStateEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletAdminActivationStateEntity();
  object.id = id;
  object.payloadJson = reader.readString(offsets[0]);
  return object;
}

P _walletAdminActivationStateEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _walletAdminActivationStateEntityGetId(
  WalletAdminActivationStateEntity object,
) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletAdminActivationStateEntityGetLinks(
  WalletAdminActivationStateEntity object,
) {
  return [];
}

void _walletAdminActivationStateEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletAdminActivationStateEntity object,
) {
  object.id = id;
}

extension WalletAdminActivationStateEntityQueryWhereSort
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QWhere
        > {
  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletAdminActivationStateEntityQueryWhere
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
}

extension WalletAdminActivationStateEntityQueryFilter
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }
}

extension WalletAdminActivationStateEntityQueryObject
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QFilterCondition
        > {}

extension WalletAdminActivationStateEntityQueryLinks
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QFilterCondition
        > {}

extension WalletAdminActivationStateEntityQuerySortBy
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }
}

extension WalletAdminActivationStateEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }
}

extension WalletAdminActivationStateEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletAdminActivationStateEntity,
    WalletAdminActivationStateEntity,
    QDistinct
  >
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }
}

extension WalletAdminActivationStateEntityQueryProperty
    on
        QueryBuilder<
          WalletAdminActivationStateEntity,
          WalletAdminActivationStateEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletAdminActivationStateEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletAdminActivationStateEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletMembershipStateEntityCollection on Isar {
  IsarCollection<WalletMembershipStateEntity>
  get walletMembershipStateEntitys => this.collection();
}

const WalletMembershipStateEntitySchema = CollectionSchema(
  name: r'WalletMembershipStateEntity',
  id: 556827875662804835,
  properties: {
    r'payloadJson': PropertySchema(
      id: 0,
      name: r'payloadJson',
      type: IsarType.string,
    ),
    r'stateKey': PropertySchema(
      id: 1,
      name: r'stateKey',
      type: IsarType.string,
    ),
  },

  estimateSize: _walletMembershipStateEntityEstimateSize,
  serialize: _walletMembershipStateEntitySerialize,
  deserialize: _walletMembershipStateEntityDeserialize,
  deserializeProp: _walletMembershipStateEntityDeserializeProp,
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
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletMembershipStateEntityGetId,
  getLinks: _walletMembershipStateEntityGetLinks,
  attach: _walletMembershipStateEntityAttach,
  version: '3.3.2',
);

int _walletMembershipStateEntityEstimateSize(
  WalletMembershipStateEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payloadJson.length * 3;
  bytesCount += 3 + object.stateKey.length * 3;
  return bytesCount;
}

void _walletMembershipStateEntitySerialize(
  WalletMembershipStateEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.payloadJson);
  writer.writeString(offsets[1], object.stateKey);
}

WalletMembershipStateEntity _walletMembershipStateEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletMembershipStateEntity();
  object.id = id;
  object.payloadJson = reader.readString(offsets[0]);
  object.stateKey = reader.readString(offsets[1]);
  return object;
}

P _walletMembershipStateEntityDeserializeProp<P>(
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

Id _walletMembershipStateEntityGetId(WalletMembershipStateEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletMembershipStateEntityGetLinks(
  WalletMembershipStateEntity object,
) {
  return [];
}

void _walletMembershipStateEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletMembershipStateEntity object,
) {
  object.id = id;
}

extension WalletMembershipStateEntityByIndex
    on IsarCollection<WalletMembershipStateEntity> {
  Future<WalletMembershipStateEntity?> getByStateKey(String stateKey) {
    return getByIndex(r'stateKey', [stateKey]);
  }

  WalletMembershipStateEntity? getByStateKeySync(String stateKey) {
    return getByIndexSync(r'stateKey', [stateKey]);
  }

  Future<bool> deleteByStateKey(String stateKey) {
    return deleteByIndex(r'stateKey', [stateKey]);
  }

  bool deleteByStateKeySync(String stateKey) {
    return deleteByIndexSync(r'stateKey', [stateKey]);
  }

  Future<List<WalletMembershipStateEntity?>> getAllByStateKey(
    List<String> stateKeyValues,
  ) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'stateKey', values);
  }

  List<WalletMembershipStateEntity?> getAllByStateKeySync(
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

  Future<Id> putByStateKey(WalletMembershipStateEntity object) {
    return putByIndex(r'stateKey', object);
  }

  Id putByStateKeySync(
    WalletMembershipStateEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'stateKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByStateKey(List<WalletMembershipStateEntity> objects) {
    return putAllByIndex(r'stateKey', objects);
  }

  List<Id> putAllByStateKeySync(
    List<WalletMembershipStateEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'stateKey', objects, saveLinks: saveLinks);
  }
}

extension WalletMembershipStateEntityQueryWhereSort
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QWhere
        > {
  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletMembershipStateEntityQueryWhere
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
}

extension WalletMembershipStateEntityQueryFilter
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
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
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterFilterCondition
  >
  stateKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'stateKey', value: ''),
      );
    });
  }
}

extension WalletMembershipStateEntityQueryObject
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QFilterCondition
        > {}

extension WalletMembershipStateEntityQueryLinks
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QFilterCondition
        > {}

extension WalletMembershipStateEntityQuerySortBy
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QSortBy
        > {
  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  sortByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  sortByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }
}

extension WalletMembershipStateEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QSortThenBy
        > {
  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  thenByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QAfterSortBy
  >
  thenByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }
}

extension WalletMembershipStateEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QDistinct
        > {
  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QDistinct
  >
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    WalletMembershipStateEntity,
    WalletMembershipStateEntity,
    QDistinct
  >
  distinctByStateKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stateKey', caseSensitive: caseSensitive);
    });
  }
}

extension WalletMembershipStateEntityQueryProperty
    on
        QueryBuilder<
          WalletMembershipStateEntity,
          WalletMembershipStateEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletMembershipStateEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletMembershipStateEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }

  QueryBuilder<WalletMembershipStateEntity, String, QQueryOperations>
  stateKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stateKey');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetWalletCreatorStateEntityCollection on Isar {
  IsarCollection<WalletCreatorStateEntity> get walletCreatorStateEntitys =>
      this.collection();
}

const WalletCreatorStateEntitySchema = CollectionSchema(
  name: r'WalletCreatorStateEntity',
  id: 6007752183687900354,
  properties: {
    r'payloadJson': PropertySchema(
      id: 0,
      name: r'payloadJson',
      type: IsarType.string,
    ),
    r'stateKey': PropertySchema(
      id: 1,
      name: r'stateKey',
      type: IsarType.string,
    ),
  },

  estimateSize: _walletCreatorStateEntityEstimateSize,
  serialize: _walletCreatorStateEntitySerialize,
  deserialize: _walletCreatorStateEntityDeserialize,
  deserializeProp: _walletCreatorStateEntityDeserializeProp,
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
  },
  links: {},
  embeddedSchemas: {},

  getId: _walletCreatorStateEntityGetId,
  getLinks: _walletCreatorStateEntityGetLinks,
  attach: _walletCreatorStateEntityAttach,
  version: '3.3.2',
);

int _walletCreatorStateEntityEstimateSize(
  WalletCreatorStateEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payloadJson.length * 3;
  bytesCount += 3 + object.stateKey.length * 3;
  return bytesCount;
}

void _walletCreatorStateEntitySerialize(
  WalletCreatorStateEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.payloadJson);
  writer.writeString(offsets[1], object.stateKey);
}

WalletCreatorStateEntity _walletCreatorStateEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = WalletCreatorStateEntity();
  object.id = id;
  object.payloadJson = reader.readString(offsets[0]);
  object.stateKey = reader.readString(offsets[1]);
  return object;
}

P _walletCreatorStateEntityDeserializeProp<P>(
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

Id _walletCreatorStateEntityGetId(WalletCreatorStateEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _walletCreatorStateEntityGetLinks(
  WalletCreatorStateEntity object,
) {
  return [];
}

void _walletCreatorStateEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  WalletCreatorStateEntity object,
) {
  object.id = id;
}

extension WalletCreatorStateEntityByIndex
    on IsarCollection<WalletCreatorStateEntity> {
  Future<WalletCreatorStateEntity?> getByStateKey(String stateKey) {
    return getByIndex(r'stateKey', [stateKey]);
  }

  WalletCreatorStateEntity? getByStateKeySync(String stateKey) {
    return getByIndexSync(r'stateKey', [stateKey]);
  }

  Future<bool> deleteByStateKey(String stateKey) {
    return deleteByIndex(r'stateKey', [stateKey]);
  }

  bool deleteByStateKeySync(String stateKey) {
    return deleteByIndexSync(r'stateKey', [stateKey]);
  }

  Future<List<WalletCreatorStateEntity?>> getAllByStateKey(
    List<String> stateKeyValues,
  ) {
    final values = stateKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'stateKey', values);
  }

  List<WalletCreatorStateEntity?> getAllByStateKeySync(
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

  Future<Id> putByStateKey(WalletCreatorStateEntity object) {
    return putByIndex(r'stateKey', object);
  }

  Id putByStateKeySync(
    WalletCreatorStateEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'stateKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByStateKey(List<WalletCreatorStateEntity> objects) {
    return putAllByIndex(r'stateKey', objects);
  }

  List<Id> putAllByStateKeySync(
    List<WalletCreatorStateEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'stateKey', objects, saveLinks: saveLinks);
  }
}

extension WalletCreatorStateEntityQueryWhereSort
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QWhere
        > {
  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension WalletCreatorStateEntityQueryWhere
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QWhereClause
        > {
  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
}

extension WalletCreatorStateEntityQueryFilter
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QFilterCondition
        > {
  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadJson',
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payloadJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payloadJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  payloadJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payloadJson', value: ''),
      );
    });
  }

  QueryBuilder<
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
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
    WalletCreatorStateEntity,
    WalletCreatorStateEntity,
    QAfterFilterCondition
  >
  stateKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'stateKey', value: ''),
      );
    });
  }
}

extension WalletCreatorStateEntityQueryObject
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QFilterCondition
        > {}

extension WalletCreatorStateEntityQueryLinks
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QFilterCondition
        > {}

extension WalletCreatorStateEntityQuerySortBy
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QSortBy
        > {
  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  sortByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  sortByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  sortByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  sortByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }
}

extension WalletCreatorStateEntityQuerySortThenBy
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QSortThenBy
        > {
  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  thenByPayloadJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.asc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  thenByPayloadJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payloadJson', Sort.desc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  thenByStateKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.asc);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QAfterSortBy>
  thenByStateKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stateKey', Sort.desc);
    });
  }
}

extension WalletCreatorStateEntityQueryWhereDistinct
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QDistinct
        > {
  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QDistinct>
  distinctByPayloadJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<WalletCreatorStateEntity, WalletCreatorStateEntity, QDistinct>
  distinctByStateKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stateKey', caseSensitive: caseSensitive);
    });
  }
}

extension WalletCreatorStateEntityQueryProperty
    on
        QueryBuilder<
          WalletCreatorStateEntity,
          WalletCreatorStateEntity,
          QQueryProperty
        > {
  QueryBuilder<WalletCreatorStateEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<WalletCreatorStateEntity, String, QQueryOperations>
  payloadJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadJson');
    });
  }

  QueryBuilder<WalletCreatorStateEntity, String, QQueryOperations>
  stateKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stateKey');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPersonalAccountEntityCollection on Isar {
  IsarCollection<PersonalAccountEntity> get personalAccountEntitys =>
      this.collection();
}

const PersonalAccountEntitySchema = CollectionSchema(
  name: r'PersonalAccountEntity',
  id: -1077055029010259870,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'accountName': PropertySchema(
      id: 1,
      name: r'accountName',
      type: IsarType.string,
    ),
    r'addedAtMillis': PropertySchema(
      id: 2,
      name: r'addedAtMillis',
      type: IsarType.long,
    ),
    r'creatorAccountId': PropertySchema(
      id: 3,
      name: r'creatorAccountId',
      type: IsarType.string,
    ),
    r'discoveredViaAdmin': PropertySchema(
      id: 4,
      name: r'discoveredViaAdmin',
      type: IsarType.bool,
    ),
    r'matchedAdminAccountIds': PropertySchema(
      id: 5,
      name: r'matchedAdminAccountIds',
      type: IsarType.stringList,
    ),
  },

  estimateSize: _personalAccountEntityEstimateSize,
  serialize: _personalAccountEntitySerialize,
  deserialize: _personalAccountEntityDeserialize,
  deserializeProp: _personalAccountEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'accountId': IndexSchema(
      id: -1591555361937770434,
      name: r'accountId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'accountId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'addedAtMillis': IndexSchema(
      id: -1059979261930735929,
      name: r'addedAtMillis',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'addedAtMillis',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'discoveredViaAdmin': IndexSchema(
      id: 7499132730782160372,
      name: r'discoveredViaAdmin',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'discoveredViaAdmin',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _personalAccountEntityGetId,
  getLinks: _personalAccountEntityGetLinks,
  attach: _personalAccountEntityAttach,
  version: '3.3.2',
);

int _personalAccountEntityEstimateSize(
  PersonalAccountEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  bytesCount += 3 + object.accountName.length * 3;
  bytesCount += 3 + object.creatorAccountId.length * 3;
  bytesCount += 3 + object.matchedAdminAccountIds.length * 3;
  {
    for (var i = 0; i < object.matchedAdminAccountIds.length; i++) {
      final value = object.matchedAdminAccountIds[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _personalAccountEntitySerialize(
  PersonalAccountEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.accountName);
  writer.writeLong(offsets[2], object.addedAtMillis);
  writer.writeString(offsets[3], object.creatorAccountId);
  writer.writeBool(offsets[4], object.discoveredViaAdmin);
  writer.writeStringList(offsets[5], object.matchedAdminAccountIds);
}

PersonalAccountEntity _personalAccountEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PersonalAccountEntity();
  object.accountId = reader.readString(offsets[0]);
  object.accountName = reader.readString(offsets[1]);
  object.addedAtMillis = reader.readLong(offsets[2]);
  object.creatorAccountId = reader.readString(offsets[3]);
  object.discoveredViaAdmin = reader.readBool(offsets[4]);
  object.id = id;
  object.matchedAdminAccountIds = reader.readStringList(offsets[5]) ?? [];
  return object;
}

P _personalAccountEntityDeserializeProp<P>(
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
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readStringList(offset) ?? []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _personalAccountEntityGetId(PersonalAccountEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _personalAccountEntityGetLinks(
  PersonalAccountEntity object,
) {
  return [];
}

void _personalAccountEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  PersonalAccountEntity object,
) {
  object.id = id;
}

extension PersonalAccountEntityByIndex
    on IsarCollection<PersonalAccountEntity> {
  Future<PersonalAccountEntity?> getByAccountId(String accountId) {
    return getByIndex(r'accountId', [accountId]);
  }

  PersonalAccountEntity? getByAccountIdSync(String accountId) {
    return getByIndexSync(r'accountId', [accountId]);
  }

  Future<bool> deleteByAccountId(String accountId) {
    return deleteByIndex(r'accountId', [accountId]);
  }

  bool deleteByAccountIdSync(String accountId) {
    return deleteByIndexSync(r'accountId', [accountId]);
  }

  Future<List<PersonalAccountEntity?>> getAllByAccountId(
    List<String> accountIdValues,
  ) {
    final values = accountIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'accountId', values);
  }

  List<PersonalAccountEntity?> getAllByAccountIdSync(
    List<String> accountIdValues,
  ) {
    final values = accountIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'accountId', values);
  }

  Future<int> deleteAllByAccountId(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'accountId', values);
  }

  int deleteAllByAccountIdSync(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'accountId', values);
  }

  Future<Id> putByAccountId(PersonalAccountEntity object) {
    return putByIndex(r'accountId', object);
  }

  Id putByAccountIdSync(PersonalAccountEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'accountId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByAccountId(List<PersonalAccountEntity> objects) {
    return putAllByIndex(r'accountId', objects);
  }

  List<Id> putAllByAccountIdSync(
    List<PersonalAccountEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'accountId', objects, saveLinks: saveLinks);
  }
}

extension PersonalAccountEntityQueryWhereSort
    on QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QWhere> {
  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhere>
  anyAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'addedAtMillis'),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhere>
  anyDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'discoveredViaAdmin'),
      );
    });
  }
}

extension PersonalAccountEntityQueryWhere
    on
        QueryBuilder<
          PersonalAccountEntity,
          PersonalAccountEntity,
          QWhereClause
        > {
  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
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

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
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

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  accountIdEqualTo(String accountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'accountId', value: [accountId]),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  accountIdNotEqualTo(String accountId) {
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

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  addedAtMillisEqualTo(int addedAtMillis) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'addedAtMillis',
          value: [addedAtMillis],
        ),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  addedAtMillisNotEqualTo(int addedAtMillis) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [],
                upper: [addedAtMillis],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [addedAtMillis],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [addedAtMillis],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [],
                upper: [addedAtMillis],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  addedAtMillisGreaterThan(int addedAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'addedAtMillis',
          lower: [addedAtMillis],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  addedAtMillisLessThan(int addedAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'addedAtMillis',
          lower: [],
          upper: [addedAtMillis],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  addedAtMillisBetween(
    int lowerAddedAtMillis,
    int upperAddedAtMillis, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'addedAtMillis',
          lower: [lowerAddedAtMillis],
          includeLower: includeLower,
          upper: [upperAddedAtMillis],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  discoveredViaAdminEqualTo(bool discoveredViaAdmin) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'discoveredViaAdmin',
          value: [discoveredViaAdmin],
        ),
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterWhereClause>
  discoveredViaAdminNotEqualTo(bool discoveredViaAdmin) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [],
                upper: [discoveredViaAdmin],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [discoveredViaAdmin],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [discoveredViaAdmin],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [],
                upper: [discoveredViaAdmin],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension PersonalAccountEntityQueryFilter
    on
        QueryBuilder<
          PersonalAccountEntity,
          PersonalAccountEntity,
          QFilterCondition
        > {
  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'accountName',
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
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'accountName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'accountName', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  accountNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'accountName', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  addedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'addedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  addedAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'addedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  addedAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'addedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  addedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'addedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'creatorAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'creatorAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'creatorAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'creatorAccountId',
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
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'creatorAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'creatorAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'creatorAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'creatorAccountId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'creatorAccountId', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  creatorAccountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'creatorAccountId', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  discoveredViaAdminEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'discoveredViaAdmin', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
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
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'matchedAdminAccountIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'matchedAdminAccountIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'matchedAdminAccountIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'matchedAdminAccountIds',
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
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'matchedAdminAccountIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'matchedAdminAccountIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'matchedAdminAccountIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'matchedAdminAccountIds',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'matchedAdminAccountIds', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'matchedAdminAccountIds',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'matchedAdminAccountIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'matchedAdminAccountIds', 0, true, 0, true);
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'matchedAdminAccountIds',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'matchedAdminAccountIds',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'matchedAdminAccountIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<
    PersonalAccountEntity,
    PersonalAccountEntity,
    QAfterFilterCondition
  >
  matchedAdminAccountIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'matchedAdminAccountIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension PersonalAccountEntityQueryObject
    on
        QueryBuilder<
          PersonalAccountEntity,
          PersonalAccountEntity,
          QFilterCondition
        > {}

extension PersonalAccountEntityQueryLinks
    on
        QueryBuilder<
          PersonalAccountEntity,
          PersonalAccountEntity,
          QFilterCondition
        > {}

extension PersonalAccountEntityQuerySortBy
    on QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QSortBy> {
  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByAccountName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByAccountNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByAddedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByCreatorAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorAccountId', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByCreatorAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorAccountId', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  sortByDiscoveredViaAdminDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.desc);
    });
  }
}

extension PersonalAccountEntityQuerySortThenBy
    on QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QSortThenBy> {
  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByAccountName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByAccountNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByAddedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByCreatorAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorAccountId', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByCreatorAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorAccountId', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByDiscoveredViaAdminDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.desc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }
}

extension PersonalAccountEntityQueryWhereDistinct
    on QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct> {
  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct>
  distinctByAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct>
  distinctByAccountName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct>
  distinctByAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'addedAtMillis');
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct>
  distinctByCreatorAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'creatorAccountId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct>
  distinctByDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'discoveredViaAdmin');
    });
  }

  QueryBuilder<PersonalAccountEntity, PersonalAccountEntity, QDistinct>
  distinctByMatchedAdminAccountIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'matchedAdminAccountIds');
    });
  }
}

extension PersonalAccountEntityQueryProperty
    on
        QueryBuilder<
          PersonalAccountEntity,
          PersonalAccountEntity,
          QQueryProperty
        > {
  QueryBuilder<PersonalAccountEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PersonalAccountEntity, String, QQueryOperations>
  accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<PersonalAccountEntity, String, QQueryOperations>
  accountNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountName');
    });
  }

  QueryBuilder<PersonalAccountEntity, int, QQueryOperations>
  addedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'addedAtMillis');
    });
  }

  QueryBuilder<PersonalAccountEntity, String, QQueryOperations>
  creatorAccountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'creatorAccountId');
    });
  }

  QueryBuilder<PersonalAccountEntity, bool, QQueryOperations>
  discoveredViaAdminProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'discoveredViaAdmin');
    });
  }

  QueryBuilder<PersonalAccountEntity, List<String>, QQueryOperations>
  matchedAdminAccountIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'matchedAdminAccountIds');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPersonalAccountProposalEntityCollection on Isar {
  IsarCollection<PersonalAccountProposalEntity>
  get personalAccountProposalEntitys => this.collection();
}

const PersonalAccountProposalEntitySchema = CollectionSchema(
  name: r'PersonalAccountProposalEntity',
  id: -3411966394002169445,
  properties: {
    r'action': PropertySchema(id: 0, name: r'action', type: IsarType.string),
    r'createdAtMillis': PropertySchema(
      id: 1,
      name: r'createdAtMillis',
      type: IsarType.long,
    ),
    r'finalStatusAtMillis': PropertySchema(
      id: 2,
      name: r'finalStatusAtMillis',
      type: IsarType.long,
    ),
    r'noVotes': PropertySchema(id: 3, name: r'noVotes', type: IsarType.long),
    r'personalAccountId': PropertySchema(
      id: 4,
      name: r'personalAccountId',
      type: IsarType.string,
    ),
    r'proposalId': PropertySchema(
      id: 5,
      name: r'proposalId',
      type: IsarType.long,
    ),
    r'snapshotJson': PropertySchema(
      id: 6,
      name: r'snapshotJson',
      type: IsarType.string,
    ),
    r'status': PropertySchema(id: 7, name: r'status', type: IsarType.string),
    r'yesVotes': PropertySchema(id: 8, name: r'yesVotes', type: IsarType.long),
  },

  estimateSize: _personalAccountProposalEntityEstimateSize,
  serialize: _personalAccountProposalEntitySerialize,
  deserialize: _personalAccountProposalEntityDeserialize,
  deserializeProp: _personalAccountProposalEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'personalAccountId_proposalId': IndexSchema(
      id: -642338065193233772,
      name: r'personalAccountId_proposalId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'personalAccountId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'proposalId',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'action': IndexSchema(
      id: -2948318935682215514,
      name: r'action',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'action',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'status': IndexSchema(
      id: -107785170620420283,
      name: r'status',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'status',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'createdAtMillis': IndexSchema(
      id: -2739706252225730577,
      name: r'createdAtMillis',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAtMillis',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _personalAccountProposalEntityGetId,
  getLinks: _personalAccountProposalEntityGetLinks,
  attach: _personalAccountProposalEntityAttach,
  version: '3.3.2',
);

int _personalAccountProposalEntityEstimateSize(
  PersonalAccountProposalEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.action.length * 3;
  bytesCount += 3 + object.personalAccountId.length * 3;
  {
    final value = object.snapshotJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.status.length * 3;
  return bytesCount;
}

void _personalAccountProposalEntitySerialize(
  PersonalAccountProposalEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.action);
  writer.writeLong(offsets[1], object.createdAtMillis);
  writer.writeLong(offsets[2], object.finalStatusAtMillis);
  writer.writeLong(offsets[3], object.noVotes);
  writer.writeString(offsets[4], object.personalAccountId);
  writer.writeLong(offsets[5], object.proposalId);
  writer.writeString(offsets[6], object.snapshotJson);
  writer.writeString(offsets[7], object.status);
  writer.writeLong(offsets[8], object.yesVotes);
}

PersonalAccountProposalEntity _personalAccountProposalEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PersonalAccountProposalEntity();
  object.action = reader.readString(offsets[0]);
  object.createdAtMillis = reader.readLong(offsets[1]);
  object.finalStatusAtMillis = reader.readLongOrNull(offsets[2]);
  object.id = id;
  object.noVotes = reader.readLong(offsets[3]);
  object.personalAccountId = reader.readString(offsets[4]);
  object.proposalId = reader.readLong(offsets[5]);
  object.snapshotJson = reader.readStringOrNull(offsets[6]);
  object.status = reader.readString(offsets[7]);
  object.yesVotes = reader.readLong(offsets[8]);
  return object;
}

P _personalAccountProposalEntityDeserializeProp<P>(
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
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _personalAccountProposalEntityGetId(PersonalAccountProposalEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _personalAccountProposalEntityGetLinks(
  PersonalAccountProposalEntity object,
) {
  return [];
}

void _personalAccountProposalEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  PersonalAccountProposalEntity object,
) {
  object.id = id;
}

extension PersonalAccountProposalEntityByIndex
    on IsarCollection<PersonalAccountProposalEntity> {
  Future<PersonalAccountProposalEntity?> getByPersonalAccountIdProposalId(
    String personalAccountId,
    int proposalId,
  ) {
    return getByIndex(r'personalAccountId_proposalId', [
      personalAccountId,
      proposalId,
    ]);
  }

  PersonalAccountProposalEntity? getByPersonalAccountIdProposalIdSync(
    String personalAccountId,
    int proposalId,
  ) {
    return getByIndexSync(r'personalAccountId_proposalId', [
      personalAccountId,
      proposalId,
    ]);
  }

  Future<bool> deleteByPersonalAccountIdProposalId(
    String personalAccountId,
    int proposalId,
  ) {
    return deleteByIndex(r'personalAccountId_proposalId', [
      personalAccountId,
      proposalId,
    ]);
  }

  bool deleteByPersonalAccountIdProposalIdSync(
    String personalAccountId,
    int proposalId,
  ) {
    return deleteByIndexSync(r'personalAccountId_proposalId', [
      personalAccountId,
      proposalId,
    ]);
  }

  Future<List<PersonalAccountProposalEntity?>>
  getAllByPersonalAccountIdProposalId(
    List<String> personalAccountIdValues,
    List<int> proposalIdValues,
  ) {
    final len = personalAccountIdValues.length;
    assert(
      proposalIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([personalAccountIdValues[i], proposalIdValues[i]]);
    }

    return getAllByIndex(r'personalAccountId_proposalId', values);
  }

  List<PersonalAccountProposalEntity?> getAllByPersonalAccountIdProposalIdSync(
    List<String> personalAccountIdValues,
    List<int> proposalIdValues,
  ) {
    final len = personalAccountIdValues.length;
    assert(
      proposalIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([personalAccountIdValues[i], proposalIdValues[i]]);
    }

    return getAllByIndexSync(r'personalAccountId_proposalId', values);
  }

  Future<int> deleteAllByPersonalAccountIdProposalId(
    List<String> personalAccountIdValues,
    List<int> proposalIdValues,
  ) {
    final len = personalAccountIdValues.length;
    assert(
      proposalIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([personalAccountIdValues[i], proposalIdValues[i]]);
    }

    return deleteAllByIndex(r'personalAccountId_proposalId', values);
  }

  int deleteAllByPersonalAccountIdProposalIdSync(
    List<String> personalAccountIdValues,
    List<int> proposalIdValues,
  ) {
    final len = personalAccountIdValues.length;
    assert(
      proposalIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([personalAccountIdValues[i], proposalIdValues[i]]);
    }

    return deleteAllByIndexSync(r'personalAccountId_proposalId', values);
  }

  Future<Id> putByPersonalAccountIdProposalId(
    PersonalAccountProposalEntity object,
  ) {
    return putByIndex(r'personalAccountId_proposalId', object);
  }

  Id putByPersonalAccountIdProposalIdSync(
    PersonalAccountProposalEntity object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(
      r'personalAccountId_proposalId',
      object,
      saveLinks: saveLinks,
    );
  }

  Future<List<Id>> putAllByPersonalAccountIdProposalId(
    List<PersonalAccountProposalEntity> objects,
  ) {
    return putAllByIndex(r'personalAccountId_proposalId', objects);
  }

  List<Id> putAllByPersonalAccountIdProposalIdSync(
    List<PersonalAccountProposalEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'personalAccountId_proposalId',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension PersonalAccountProposalEntityQueryWhereSort
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QWhere
        > {
  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhere
  >
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhere
  >
  anyCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAtMillis'),
      );
    });
  }
}

extension PersonalAccountProposalEntityQueryWhere
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QWhereClause
        > {
  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdEqualToAnyProposalId(String personalAccountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'personalAccountId_proposalId',
          value: [personalAccountId],
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdNotEqualToAnyProposalId(String personalAccountId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [],
                upper: [personalAccountId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [personalAccountId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [personalAccountId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [],
                upper: [personalAccountId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdProposalIdEqualTo(String personalAccountId, int proposalId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'personalAccountId_proposalId',
          value: [personalAccountId, proposalId],
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdEqualToProposalIdNotEqualTo(
    String personalAccountId,
    int proposalId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [personalAccountId],
                upper: [personalAccountId, proposalId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [personalAccountId, proposalId],
                includeLower: false,
                upper: [personalAccountId],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [personalAccountId, proposalId],
                includeLower: false,
                upper: [personalAccountId],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'personalAccountId_proposalId',
                lower: [personalAccountId],
                upper: [personalAccountId, proposalId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdEqualToProposalIdGreaterThan(
    String personalAccountId,
    int proposalId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'personalAccountId_proposalId',
          lower: [personalAccountId, proposalId],
          includeLower: include,
          upper: [personalAccountId],
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdEqualToProposalIdLessThan(
    String personalAccountId,
    int proposalId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'personalAccountId_proposalId',
          lower: [personalAccountId],
          upper: [personalAccountId, proposalId],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  personalAccountIdEqualToProposalIdBetween(
    String personalAccountId,
    int lowerProposalId,
    int upperProposalId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'personalAccountId_proposalId',
          lower: [personalAccountId, lowerProposalId],
          includeLower: includeLower,
          upper: [personalAccountId, upperProposalId],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  actionEqualTo(String action) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'action', value: [action]),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  actionNotEqualTo(String action) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'action',
                lower: [],
                upper: [action],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'action',
                lower: [action],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'action',
                lower: [action],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'action',
                lower: [],
                upper: [action],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  statusEqualTo(String status) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'status', value: [status]),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  statusNotEqualTo(String status) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'status',
                lower: [],
                upper: [status],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'status',
                lower: [status],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'status',
                lower: [status],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'status',
                lower: [],
                upper: [status],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  createdAtMillisEqualTo(int createdAtMillis) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'createdAtMillis',
          value: [createdAtMillis],
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  createdAtMillisNotEqualTo(int createdAtMillis) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [],
                upper: [createdAtMillis],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [createdAtMillis],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [createdAtMillis],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [],
                upper: [createdAtMillis],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  createdAtMillisGreaterThan(int createdAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAtMillis',
          lower: [createdAtMillis],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  createdAtMillisLessThan(int createdAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAtMillis',
          lower: [],
          upper: [createdAtMillis],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterWhereClause
  >
  createdAtMillisBetween(
    int lowerCreatedAtMillis,
    int upperCreatedAtMillis, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAtMillis',
          lower: [lowerCreatedAtMillis],
          includeLower: includeLower,
          upper: [upperCreatedAtMillis],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension PersonalAccountProposalEntityQueryFilter
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QFilterCondition
        > {
  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'action',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'action',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'action',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'action',
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'action',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'action',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'action',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'action',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'action', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  actionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'action', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  createdAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  createdAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  createdAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  createdAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  finalStatusAtMillisIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'finalStatusAtMillis'),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  finalStatusAtMillisIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'finalStatusAtMillis'),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  finalStatusAtMillisEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'finalStatusAtMillis', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  finalStatusAtMillisGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'finalStatusAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  finalStatusAtMillisLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'finalStatusAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  finalStatusAtMillisBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'finalStatusAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  noVotesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'noVotes', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  noVotesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'noVotes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  noVotesLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'noVotes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  noVotesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'noVotes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'personalAccountId',
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'personalAccountId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'personalAccountId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'personalAccountId', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  personalAccountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'personalAccountId', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  proposalIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'proposalId', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  proposalIdGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'proposalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  proposalIdLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'proposalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  proposalIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'proposalId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'snapshotJson'),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'snapshotJson'),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'snapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'snapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'snapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'snapshotJson',
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'snapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'snapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'snapshotJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'snapshotJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'snapshotJson', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  snapshotJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'snapshotJson', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'status',
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
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'status',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'status', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'status', value: ''),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  yesVotesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'yesVotes', value: value),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  yesVotesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'yesVotes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  yesVotesLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'yesVotes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterFilterCondition
  >
  yesVotesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'yesVotes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension PersonalAccountProposalEntityQueryObject
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QFilterCondition
        > {}

extension PersonalAccountProposalEntityQueryLinks
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QFilterCondition
        > {}

extension PersonalAccountProposalEntityQuerySortBy
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QSortBy
        > {
  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByAction() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'action', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByActionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'action', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByCreatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByFinalStatusAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'finalStatusAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByFinalStatusAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'finalStatusAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByNoVotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noVotes', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByNoVotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noVotes', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByPersonalAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByPersonalAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByProposalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortBySnapshotJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'snapshotJson', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortBySnapshotJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'snapshotJson', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByYesVotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yesVotes', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  sortByYesVotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yesVotes', Sort.desc);
    });
  }
}

extension PersonalAccountProposalEntityQuerySortThenBy
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QSortThenBy
        > {
  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByAction() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'action', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByActionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'action', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByCreatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByFinalStatusAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'finalStatusAtMillis', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByFinalStatusAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'finalStatusAtMillis', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByNoVotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noVotes', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByNoVotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'noVotes', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByPersonalAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByPersonalAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personalAccountId', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByProposalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proposalId', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenBySnapshotJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'snapshotJson', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenBySnapshotJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'snapshotJson', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByYesVotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yesVotes', Sort.asc);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QAfterSortBy
  >
  thenByYesVotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yesVotes', Sort.desc);
    });
  }
}

extension PersonalAccountProposalEntityQueryWhereDistinct
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QDistinct
        > {
  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByAction({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'action', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAtMillis');
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByFinalStatusAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'finalStatusAtMillis');
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByNoVotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'noVotes');
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByPersonalAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'personalAccountId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByProposalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'proposalId');
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctBySnapshotJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'snapshotJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByStatus({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<
    PersonalAccountProposalEntity,
    PersonalAccountProposalEntity,
    QDistinct
  >
  distinctByYesVotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'yesVotes');
    });
  }
}

extension PersonalAccountProposalEntityQueryProperty
    on
        QueryBuilder<
          PersonalAccountProposalEntity,
          PersonalAccountProposalEntity,
          QQueryProperty
        > {
  QueryBuilder<PersonalAccountProposalEntity, int, QQueryOperations>
  idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, String, QQueryOperations>
  actionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'action');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, int, QQueryOperations>
  createdAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAtMillis');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, int?, QQueryOperations>
  finalStatusAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'finalStatusAtMillis');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, int, QQueryOperations>
  noVotesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'noVotes');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, String, QQueryOperations>
  personalAccountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'personalAccountId');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, int, QQueryOperations>
  proposalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'proposalId');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, String?, QQueryOperations>
  snapshotJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'snapshotJson');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, String, QQueryOperations>
  statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<PersonalAccountProposalEntity, int, QQueryOperations>
  yesVotesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'yesVotes');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetInstitutionEntityCollection on Isar {
  IsarCollection<InstitutionEntity> get institutionEntitys => this.collection();
}

const InstitutionEntitySchema = CollectionSchema(
  name: r'InstitutionEntity',
  id: -5851359460125618519,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'accountName': PropertySchema(
      id: 1,
      name: r'accountName',
      type: IsarType.string,
    ),
    r'addedAtMillis': PropertySchema(
      id: 2,
      name: r'addedAtMillis',
      type: IsarType.long,
    ),
    r'adminAccountCode': PropertySchema(
      id: 3,
      name: r'adminAccountCode',
      type: IsarType.string,
    ),
    r'cidNumber': PropertySchema(
      id: 4,
      name: r'cidNumber',
      type: IsarType.string,
    ),
    r'discoveredViaAdmin': PropertySchema(
      id: 5,
      name: r'discoveredViaAdmin',
      type: IsarType.bool,
    ),
  },

  estimateSize: _institutionEntityEstimateSize,
  serialize: _institutionEntitySerialize,
  deserialize: _institutionEntityDeserialize,
  deserializeProp: _institutionEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'accountId': IndexSchema(
      id: -1591555361937770434,
      name: r'accountId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'accountId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'addedAtMillis': IndexSchema(
      id: -1059979261930735929,
      name: r'addedAtMillis',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'addedAtMillis',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'discoveredViaAdmin': IndexSchema(
      id: 7499132730782160372,
      name: r'discoveredViaAdmin',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'discoveredViaAdmin',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _institutionEntityGetId,
  getLinks: _institutionEntityGetLinks,
  attach: _institutionEntityAttach,
  version: '3.3.2',
);

int _institutionEntityEstimateSize(
  InstitutionEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  bytesCount += 3 + object.accountName.length * 3;
  {
    final value = object.adminAccountCode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.cidNumber.length * 3;
  return bytesCount;
}

void _institutionEntitySerialize(
  InstitutionEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.accountName);
  writer.writeLong(offsets[2], object.addedAtMillis);
  writer.writeString(offsets[3], object.adminAccountCode);
  writer.writeString(offsets[4], object.cidNumber);
  writer.writeBool(offsets[5], object.discoveredViaAdmin);
}

InstitutionEntity _institutionEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = InstitutionEntity();
  object.accountId = reader.readString(offsets[0]);
  object.accountName = reader.readString(offsets[1]);
  object.addedAtMillis = reader.readLong(offsets[2]);
  object.adminAccountCode = reader.readStringOrNull(offsets[3]);
  object.cidNumber = reader.readString(offsets[4]);
  object.discoveredViaAdmin = reader.readBool(offsets[5]);
  object.id = id;
  return object;
}

P _institutionEntityDeserializeProp<P>(
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
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _institutionEntityGetId(InstitutionEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _institutionEntityGetLinks(
  InstitutionEntity object,
) {
  return [];
}

void _institutionEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  InstitutionEntity object,
) {
  object.id = id;
}

extension InstitutionEntityByIndex on IsarCollection<InstitutionEntity> {
  Future<InstitutionEntity?> getByAccountId(String accountId) {
    return getByIndex(r'accountId', [accountId]);
  }

  InstitutionEntity? getByAccountIdSync(String accountId) {
    return getByIndexSync(r'accountId', [accountId]);
  }

  Future<bool> deleteByAccountId(String accountId) {
    return deleteByIndex(r'accountId', [accountId]);
  }

  bool deleteByAccountIdSync(String accountId) {
    return deleteByIndexSync(r'accountId', [accountId]);
  }

  Future<List<InstitutionEntity?>> getAllByAccountId(
    List<String> accountIdValues,
  ) {
    final values = accountIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'accountId', values);
  }

  List<InstitutionEntity?> getAllByAccountIdSync(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'accountId', values);
  }

  Future<int> deleteAllByAccountId(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'accountId', values);
  }

  int deleteAllByAccountIdSync(List<String> accountIdValues) {
    final values = accountIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'accountId', values);
  }

  Future<Id> putByAccountId(InstitutionEntity object) {
    return putByIndex(r'accountId', object);
  }

  Id putByAccountIdSync(InstitutionEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'accountId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByAccountId(List<InstitutionEntity> objects) {
    return putAllByIndex(r'accountId', objects);
  }

  List<Id> putAllByAccountIdSync(
    List<InstitutionEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'accountId', objects, saveLinks: saveLinks);
  }
}

extension InstitutionEntityQueryWhereSort
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QWhere> {
  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhere>
  anyAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'addedAtMillis'),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhere>
  anyDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'discoveredViaAdmin'),
      );
    });
  }
}

extension InstitutionEntityQueryWhere
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QWhereClause> {
  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  accountIdEqualTo(String accountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'accountId', value: [accountId]),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  accountIdNotEqualTo(String accountId) {
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  addedAtMillisEqualTo(int addedAtMillis) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'addedAtMillis',
          value: [addedAtMillis],
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  addedAtMillisNotEqualTo(int addedAtMillis) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [],
                upper: [addedAtMillis],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [addedAtMillis],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [addedAtMillis],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'addedAtMillis',
                lower: [],
                upper: [addedAtMillis],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  addedAtMillisGreaterThan(int addedAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'addedAtMillis',
          lower: [addedAtMillis],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  addedAtMillisLessThan(int addedAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'addedAtMillis',
          lower: [],
          upper: [addedAtMillis],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  addedAtMillisBetween(
    int lowerAddedAtMillis,
    int upperAddedAtMillis, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'addedAtMillis',
          lower: [lowerAddedAtMillis],
          includeLower: includeLower,
          upper: [upperAddedAtMillis],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  discoveredViaAdminEqualTo(bool discoveredViaAdmin) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'discoveredViaAdmin',
          value: [discoveredViaAdmin],
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterWhereClause>
  discoveredViaAdminNotEqualTo(bool discoveredViaAdmin) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [],
                upper: [discoveredViaAdmin],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [discoveredViaAdmin],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [discoveredViaAdmin],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'discoveredViaAdmin',
                lower: [],
                upper: [discoveredViaAdmin],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension InstitutionEntityQueryFilter
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QFilterCondition> {
  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'accountId', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'accountId', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'accountName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'accountName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'accountName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'accountName', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  accountNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'accountName', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  addedAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'addedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  addedAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'addedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  addedAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'addedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  addedAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'addedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'adminAccountCode'),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'adminAccountCode'),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'adminAccountCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'adminAccountCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'adminAccountCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'adminAccountCode',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'adminAccountCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'adminAccountCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'adminAccountCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'adminAccountCode',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'adminAccountCode', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  adminAccountCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'adminAccountCode', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  cidNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  cidNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'cidNumber', value: ''),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  discoveredViaAdminEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'discoveredViaAdmin', value: value),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterFilterCondition>
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
}

extension InstitutionEntityQueryObject
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QFilterCondition> {}

extension InstitutionEntityQueryLinks
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QFilterCondition> {}

extension InstitutionEntityQuerySortBy
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QSortBy> {
  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAccountName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAccountNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAddedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAdminAccountCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adminAccountCode', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByAdminAccountCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adminAccountCode', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  sortByDiscoveredViaAdminDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.desc);
    });
  }
}

extension InstitutionEntityQuerySortThenBy
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QSortThenBy> {
  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAccountName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAccountNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountName', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAddedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'addedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAdminAccountCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adminAccountCode', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByAdminAccountCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adminAccountCode', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByCidNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByCidNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cidNumber', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByDiscoveredViaAdminDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discoveredViaAdmin', Sort.desc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }
}

extension InstitutionEntityQueryWhereDistinct
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct> {
  QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct>
  distinctByAccountId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct>
  distinctByAccountName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct>
  distinctByAddedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'addedAtMillis');
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct>
  distinctByAdminAccountCode({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'adminAccountCode',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct>
  distinctByCidNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cidNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<InstitutionEntity, InstitutionEntity, QDistinct>
  distinctByDiscoveredViaAdmin() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'discoveredViaAdmin');
    });
  }
}

extension InstitutionEntityQueryProperty
    on QueryBuilder<InstitutionEntity, InstitutionEntity, QQueryProperty> {
  QueryBuilder<InstitutionEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<InstitutionEntity, String, QQueryOperations>
  accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<InstitutionEntity, String, QQueryOperations>
  accountNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountName');
    });
  }

  QueryBuilder<InstitutionEntity, int, QQueryOperations>
  addedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'addedAtMillis');
    });
  }

  QueryBuilder<InstitutionEntity, String?, QQueryOperations>
  adminAccountCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'adminAccountCode');
    });
  }

  QueryBuilder<InstitutionEntity, String, QQueryOperations>
  cidNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cidNumber');
    });
  }

  QueryBuilder<InstitutionEntity, bool, QQueryOperations>
  discoveredViaAdminProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'discoveredViaAdmin');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalTxEntityCollection on Isar {
  IsarCollection<LocalTxEntity> get localTxEntitys => this.collection();
}

const LocalTxEntitySchema = CollectionSchema(
  name: r'LocalTxEntity',
  id: 3324518130997293643,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'amountDeltaFen': PropertySchema(
      id: 1,
      name: r'amountDeltaFen',
      type: IsarType.string,
    ),
    r'blockHash': PropertySchema(
      id: 2,
      name: r'blockHash',
      type: IsarType.string,
    ),
    r'blockNumber': PropertySchema(
      id: 3,
      name: r'blockNumber',
      type: IsarType.long,
    ),
    r'callDataHash': PropertySchema(
      id: 4,
      name: r'callDataHash',
      type: IsarType.string,
    ),
    r'confirmedAtMillis': PropertySchema(
      id: 5,
      name: r'confirmedAtMillis',
      type: IsarType.long,
    ),
    r'counterpartySs58Address': PropertySchema(
      id: 6,
      name: r'counterpartySs58Address',
      type: IsarType.string,
    ),
    r'createdAtMillis': PropertySchema(
      id: 7,
      name: r'createdAtMillis',
      type: IsarType.long,
    ),
    r'eventIndex': PropertySchema(
      id: 8,
      name: r'eventIndex',
      type: IsarType.long,
    ),
    r'executionId': PropertySchema(
      id: 9,
      name: r'executionId',
      type: IsarType.string,
    ),
    r'extrinsicIndex': PropertySchema(
      id: 10,
      name: r'extrinsicIndex',
      type: IsarType.long,
    ),
    r'failureReason': PropertySchema(
      id: 11,
      name: r'failureReason',
      type: IsarType.string,
    ),
    r'feeFen': PropertySchema(id: 12, name: r'feeFen', type: IsarType.string),
    r'fromSs58Address': PropertySchema(
      id: 13,
      name: r'fromSs58Address',
      type: IsarType.string,
    ),
    r'recordKey': PropertySchema(
      id: 14,
      name: r'recordKey',
      type: IsarType.string,
    ),
    r'remark': PropertySchema(id: 15, name: r'remark', type: IsarType.string),
    r'source': PropertySchema(id: 16, name: r'source', type: IsarType.string),
    r'ss58Address': PropertySchema(
      id: 17,
      name: r'ss58Address',
      type: IsarType.string,
    ),
    r'status': PropertySchema(id: 18, name: r'status', type: IsarType.string),
    r'toSs58Address': PropertySchema(
      id: 19,
      name: r'toSs58Address',
      type: IsarType.string,
    ),
    r'transferAmountFen': PropertySchema(
      id: 20,
      name: r'transferAmountFen',
      type: IsarType.string,
    ),
    r'txHash': PropertySchema(id: 21, name: r'txHash', type: IsarType.string),
    r'type': PropertySchema(id: 22, name: r'type', type: IsarType.string),
    r'usedNonce': PropertySchema(
      id: 23,
      name: r'usedNonce',
      type: IsarType.long,
    ),
  },

  estimateSize: _localTxEntityEstimateSize,
  serialize: _localTxEntitySerialize,
  deserialize: _localTxEntityDeserialize,
  deserializeProp: _localTxEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'recordKey': IndexSchema(
      id: -1694304532238354687,
      name: r'recordKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'recordKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'ss58Address': IndexSchema(
      id: 5333651859904869202,
      name: r'ss58Address',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'ss58Address',
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
    r'createdAtMillis': IndexSchema(
      id: -2739706252225730577,
      name: r'createdAtMillis',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAtMillis',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _localTxEntityGetId,
  getLinks: _localTxEntityGetLinks,
  attach: _localTxEntityAttach,
  version: '3.3.2',
);

int _localTxEntityEstimateSize(
  LocalTxEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  bytesCount += 3 + object.amountDeltaFen.length * 3;
  {
    final value = object.blockHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.callDataHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.counterpartySs58Address;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.executionId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.failureReason;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.feeFen;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.fromSs58Address;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.recordKey.length * 3;
  {
    final value = object.remark;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.source.length * 3;
  bytesCount += 3 + object.ss58Address.length * 3;
  bytesCount += 3 + object.status.length * 3;
  {
    final value = object.toSs58Address;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.transferAmountFen;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.txHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.type.length * 3;
  return bytesCount;
}

void _localTxEntitySerialize(
  LocalTxEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.amountDeltaFen);
  writer.writeString(offsets[2], object.blockHash);
  writer.writeLong(offsets[3], object.blockNumber);
  writer.writeString(offsets[4], object.callDataHash);
  writer.writeLong(offsets[5], object.confirmedAtMillis);
  writer.writeString(offsets[6], object.counterpartySs58Address);
  writer.writeLong(offsets[7], object.createdAtMillis);
  writer.writeLong(offsets[8], object.eventIndex);
  writer.writeString(offsets[9], object.executionId);
  writer.writeLong(offsets[10], object.extrinsicIndex);
  writer.writeString(offsets[11], object.failureReason);
  writer.writeString(offsets[12], object.feeFen);
  writer.writeString(offsets[13], object.fromSs58Address);
  writer.writeString(offsets[14], object.recordKey);
  writer.writeString(offsets[15], object.remark);
  writer.writeString(offsets[16], object.source);
  writer.writeString(offsets[17], object.ss58Address);
  writer.writeString(offsets[18], object.status);
  writer.writeString(offsets[19], object.toSs58Address);
  writer.writeString(offsets[20], object.transferAmountFen);
  writer.writeString(offsets[21], object.txHash);
  writer.writeString(offsets[22], object.type);
  writer.writeLong(offsets[23], object.usedNonce);
}

LocalTxEntity _localTxEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalTxEntity();
  object.accountId = reader.readString(offsets[0]);
  object.amountDeltaFen = reader.readString(offsets[1]);
  object.blockHash = reader.readStringOrNull(offsets[2]);
  object.blockNumber = reader.readLongOrNull(offsets[3]);
  object.callDataHash = reader.readStringOrNull(offsets[4]);
  object.confirmedAtMillis = reader.readLongOrNull(offsets[5]);
  object.counterpartySs58Address = reader.readStringOrNull(offsets[6]);
  object.createdAtMillis = reader.readLong(offsets[7]);
  object.eventIndex = reader.readLongOrNull(offsets[8]);
  object.executionId = reader.readStringOrNull(offsets[9]);
  object.extrinsicIndex = reader.readLongOrNull(offsets[10]);
  object.failureReason = reader.readStringOrNull(offsets[11]);
  object.feeFen = reader.readStringOrNull(offsets[12]);
  object.fromSs58Address = reader.readStringOrNull(offsets[13]);
  object.id = id;
  object.recordKey = reader.readString(offsets[14]);
  object.remark = reader.readStringOrNull(offsets[15]);
  object.source = reader.readString(offsets[16]);
  object.ss58Address = reader.readString(offsets[17]);
  object.status = reader.readString(offsets[18]);
  object.toSs58Address = reader.readStringOrNull(offsets[19]);
  object.transferAmountFen = reader.readStringOrNull(offsets[20]);
  object.txHash = reader.readStringOrNull(offsets[21]);
  object.type = reader.readString(offsets[22]);
  object.usedNonce = reader.readLongOrNull(offsets[23]);
  return object;
}

P _localTxEntityDeserializeProp<P>(
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
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    case 8:
      return (reader.readLongOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readLongOrNull(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readString(offset)) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readString(offset)) as P;
    case 17:
      return (reader.readString(offset)) as P;
    case 18:
      return (reader.readString(offset)) as P;
    case 19:
      return (reader.readStringOrNull(offset)) as P;
    case 20:
      return (reader.readStringOrNull(offset)) as P;
    case 21:
      return (reader.readStringOrNull(offset)) as P;
    case 22:
      return (reader.readString(offset)) as P;
    case 23:
      return (reader.readLongOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localTxEntityGetId(LocalTxEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _localTxEntityGetLinks(LocalTxEntity object) {
  return [];
}

void _localTxEntityAttach(
  IsarCollection<dynamic> col,
  Id id,
  LocalTxEntity object,
) {
  object.id = id;
}

extension LocalTxEntityByIndex on IsarCollection<LocalTxEntity> {
  Future<LocalTxEntity?> getByRecordKey(String recordKey) {
    return getByIndex(r'recordKey', [recordKey]);
  }

  LocalTxEntity? getByRecordKeySync(String recordKey) {
    return getByIndexSync(r'recordKey', [recordKey]);
  }

  Future<bool> deleteByRecordKey(String recordKey) {
    return deleteByIndex(r'recordKey', [recordKey]);
  }

  bool deleteByRecordKeySync(String recordKey) {
    return deleteByIndexSync(r'recordKey', [recordKey]);
  }

  Future<List<LocalTxEntity?>> getAllByRecordKey(List<String> recordKeyValues) {
    final values = recordKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'recordKey', values);
  }

  List<LocalTxEntity?> getAllByRecordKeySync(List<String> recordKeyValues) {
    final values = recordKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'recordKey', values);
  }

  Future<int> deleteAllByRecordKey(List<String> recordKeyValues) {
    final values = recordKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'recordKey', values);
  }

  int deleteAllByRecordKeySync(List<String> recordKeyValues) {
    final values = recordKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'recordKey', values);
  }

  Future<Id> putByRecordKey(LocalTxEntity object) {
    return putByIndex(r'recordKey', object);
  }

  Id putByRecordKeySync(LocalTxEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'recordKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByRecordKey(List<LocalTxEntity> objects) {
    return putAllByIndex(r'recordKey', objects);
  }

  List<Id> putAllByRecordKeySync(
    List<LocalTxEntity> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'recordKey', objects, saveLinks: saveLinks);
  }
}

extension LocalTxEntityQueryWhereSort
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QWhere> {
  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhere> anyCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAtMillis'),
      );
    });
  }
}

extension LocalTxEntityQueryWhere
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QWhereClause> {
  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause> idBetween(
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  recordKeyEqualTo(String recordKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'recordKey', value: [recordKey]),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  recordKeyNotEqualTo(String recordKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'recordKey',
                lower: [],
                upper: [recordKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'recordKey',
                lower: [recordKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'recordKey',
                lower: [recordKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'recordKey',
                lower: [],
                upper: [recordKey],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  ss58AddressEqualTo(String ss58Address) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'ss58Address',
          value: [ss58Address],
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  ss58AddressNotEqualTo(String ss58Address) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ss58Address',
                lower: [],
                upper: [ss58Address],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ss58Address',
                lower: [ss58Address],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ss58Address',
                lower: [ss58Address],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'ss58Address',
                lower: [],
                upper: [ss58Address],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  accountIdEqualTo(String accountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'accountId', value: [accountId]),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  accountIdNotEqualTo(String accountId) {
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  createdAtMillisEqualTo(int createdAtMillis) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'createdAtMillis',
          value: [createdAtMillis],
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  createdAtMillisNotEqualTo(int createdAtMillis) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [],
                upper: [createdAtMillis],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [createdAtMillis],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [createdAtMillis],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAtMillis',
                lower: [],
                upper: [createdAtMillis],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  createdAtMillisGreaterThan(int createdAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAtMillis',
          lower: [createdAtMillis],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  createdAtMillisLessThan(int createdAtMillis, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAtMillis',
          lower: [],
          upper: [createdAtMillis],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterWhereClause>
  createdAtMillisBetween(
    int lowerCreatedAtMillis,
    int upperCreatedAtMillis, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAtMillis',
          lower: [lowerCreatedAtMillis],
          includeLower: includeLower,
          upper: [upperCreatedAtMillis],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension LocalTxEntityQueryFilter
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QFilterCondition> {
  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  accountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'accountId', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  accountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'accountId', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'amountDeltaFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'amountDeltaFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'amountDeltaFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'amountDeltaFen',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'amountDeltaFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'amountDeltaFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'amountDeltaFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'amountDeltaFen',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'amountDeltaFen', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  amountDeltaFenIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'amountDeltaFen', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'blockHash'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'blockHash'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'blockHash', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'blockHash', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockNumberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'blockNumber'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockNumberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'blockNumber'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockNumberEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'blockNumber', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockNumberGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'blockNumber',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockNumberLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'blockNumber',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  blockNumberBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'blockNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'callDataHash'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'callDataHash'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'callDataHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'callDataHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'callDataHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'callDataHash',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'callDataHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'callDataHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'callDataHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'callDataHash',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'callDataHash', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  callDataHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'callDataHash', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  confirmedAtMillisIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'confirmedAtMillis'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  confirmedAtMillisIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'confirmedAtMillis'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  confirmedAtMillisEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'confirmedAtMillis', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  confirmedAtMillisGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'confirmedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  confirmedAtMillisLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'confirmedAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  confirmedAtMillisBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'confirmedAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'counterpartySs58Address'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'counterpartySs58Address'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'counterpartySs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'counterpartySs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'counterpartySs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'counterpartySs58Address',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'counterpartySs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'counterpartySs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'counterpartySs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'counterpartySs58Address',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'counterpartySs58Address',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  counterpartySs58AddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'counterpartySs58Address',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  createdAtMillisEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAtMillis', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  createdAtMillisGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  createdAtMillisLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAtMillis',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  createdAtMillisBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAtMillis',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  eventIndexIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'eventIndex'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  eventIndexIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'eventIndex'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  eventIndexEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'eventIndex', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  eventIndexGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'eventIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  eventIndexLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'eventIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  eventIndexBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'eventIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'executionId'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'executionId'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'executionId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'executionId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'executionId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'executionId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'executionId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'executionId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'executionId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'executionId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'executionId', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  executionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'executionId', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  extrinsicIndexIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'extrinsicIndex'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  extrinsicIndexIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'extrinsicIndex'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  extrinsicIndexEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'extrinsicIndex', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  extrinsicIndexGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'extrinsicIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  extrinsicIndexLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'extrinsicIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  extrinsicIndexBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'extrinsicIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'failureReason'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'failureReason'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'failureReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'failureReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'failureReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'failureReason',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'failureReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'failureReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'failureReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'failureReason',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'failureReason', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  failureReasonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'failureReason', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'feeFen'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'feeFen'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'feeFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'feeFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'feeFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'feeFen',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'feeFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'feeFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'feeFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'feeFen',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'feeFen', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  feeFenIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'feeFen', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'fromSs58Address'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'fromSs58Address'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'fromSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'fromSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'fromSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'fromSs58Address',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'fromSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'fromSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'fromSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'fromSs58Address',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'fromSs58Address', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  fromSs58AddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'fromSs58Address', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition> idBetween(
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

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'recordKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'recordKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'recordKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'recordKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'recordKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'recordKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'recordKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'recordKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'recordKey', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  recordKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'recordKey', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'remark'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'remark'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'remark',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'remark',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'remark',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'remark',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'remark',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'remark',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'remark',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'remark',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'remark', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  remarkIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'remark', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'source',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'source',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'source',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'source',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'source',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'source',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'source',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'source',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'source', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  sourceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'source', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'ss58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'ss58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'ss58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'ss58Address',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'ss58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'ss58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'ss58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'ss58Address',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'ss58Address', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  ss58AddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'ss58Address', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'status',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'status',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'status',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'status', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'status', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'toSs58Address'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'toSs58Address'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'toSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'toSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'toSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'toSs58Address',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'toSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'toSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'toSs58Address',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'toSs58Address',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'toSs58Address', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  toSs58AddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'toSs58Address', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'transferAmountFen'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'transferAmountFen'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'transferAmountFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'transferAmountFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'transferAmountFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'transferAmountFen',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'transferAmountFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'transferAmountFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'transferAmountFen',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'transferAmountFen',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'transferAmountFen', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  transferAmountFenIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'transferAmountFen', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'txHash'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'txHash'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'txHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'txHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'txHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'txHash',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'txHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'txHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'txHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'txHash',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'txHash', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  txHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'txHash', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition> typeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'type',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'type',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'type',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition> typeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'type',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'type',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'type',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'type',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition> typeMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'type',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'type', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  typeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'type', value: ''),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  usedNonceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'usedNonce'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  usedNonceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'usedNonce'),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  usedNonceEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'usedNonce', value: value),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  usedNonceGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'usedNonce',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  usedNonceLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'usedNonce',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterFilterCondition>
  usedNonceBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'usedNonce',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension LocalTxEntityQueryObject
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QFilterCondition> {}

extension LocalTxEntityQueryLinks
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QFilterCondition> {}

extension LocalTxEntityQuerySortBy
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QSortBy> {
  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByAmountDeltaFen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'amountDeltaFen', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByAmountDeltaFenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'amountDeltaFen', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByBlockHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByBlockHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByBlockNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockNumber', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByBlockNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockNumber', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByCallDataHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'callDataHash', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByCallDataHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'callDataHash', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByConfirmedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confirmedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByConfirmedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confirmedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByCounterpartySs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'counterpartySs58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByCounterpartySs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'counterpartySs58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByCreatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByEventIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventIndex', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByEventIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventIndex', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByExecutionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'executionId', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByExecutionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'executionId', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByExtrinsicIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'extrinsicIndex', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByExtrinsicIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'extrinsicIndex', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByFailureReason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'failureReason', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByFailureReasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'failureReason', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByFeeFen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'feeFen', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByFeeFenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'feeFen', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByFromSs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fromSs58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByFromSs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fromSs58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByRecordKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recordKey', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByRecordKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recordKey', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByRemark() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remark', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByRemarkDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remark', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortBySource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortBySourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortBySs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ss58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortBySs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ss58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByToSs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'toSs58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByToSs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'toSs58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByTransferAmountFen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transferAmountFen', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByTransferAmountFenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transferAmountFen', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByTxHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'txHash', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByTxHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'txHash', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> sortByUsedNonce() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usedNonce', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  sortByUsedNonceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usedNonce', Sort.desc);
    });
  }
}

extension LocalTxEntityQuerySortThenBy
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QSortThenBy> {
  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByAmountDeltaFen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'amountDeltaFen', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByAmountDeltaFenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'amountDeltaFen', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByBlockHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByBlockHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockHash', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByBlockNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockNumber', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByBlockNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'blockNumber', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByCallDataHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'callDataHash', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByCallDataHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'callDataHash', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByConfirmedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confirmedAtMillis', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByConfirmedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confirmedAtMillis', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByCounterpartySs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'counterpartySs58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByCounterpartySs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'counterpartySs58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByCreatedAtMillisDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtMillis', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByEventIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventIndex', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByEventIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventIndex', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByExecutionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'executionId', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByExecutionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'executionId', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByExtrinsicIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'extrinsicIndex', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByExtrinsicIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'extrinsicIndex', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByFailureReason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'failureReason', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByFailureReasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'failureReason', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByFeeFen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'feeFen', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByFeeFenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'feeFen', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByFromSs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fromSs58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByFromSs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fromSs58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByRecordKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recordKey', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByRecordKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recordKey', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByRemark() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remark', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByRemarkDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remark', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenBySource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenBySourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'source', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenBySs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ss58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenBySs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ss58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByToSs58Address() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'toSs58Address', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByToSs58AddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'toSs58Address', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByTransferAmountFen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transferAmountFen', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByTransferAmountFenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transferAmountFen', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByTxHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'txHash', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByTxHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'txHash', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy> thenByUsedNonce() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usedNonce', Sort.asc);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QAfterSortBy>
  thenByUsedNonceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'usedNonce', Sort.desc);
    });
  }
}

extension LocalTxEntityQueryWhereDistinct
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> {
  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByAccountId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByAmountDeltaFen({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'amountDeltaFen',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByBlockHash({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'blockHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByBlockNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'blockNumber');
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByCallDataHash({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'callDataHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByConfirmedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'confirmedAtMillis');
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByCounterpartySs58Address({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'counterpartySs58Address',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByCreatedAtMillis() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAtMillis');
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByEventIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'eventIndex');
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByExecutionId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'executionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByExtrinsicIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'extrinsicIndex');
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByFailureReason({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'failureReason',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByFeeFen({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'feeFen', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByFromSs58Address({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'fromSs58Address',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByRecordKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'recordKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByRemark({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'remark', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctBySource({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'source', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctBySs58Address({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ss58Address', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByStatus({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByToSs58Address({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'toSs58Address',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct>
  distinctByTransferAmountFen({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'transferAmountFen',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByTxHash({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'txHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalTxEntity, LocalTxEntity, QDistinct> distinctByUsedNonce() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'usedNonce');
    });
  }
}

extension LocalTxEntityQueryProperty
    on QueryBuilder<LocalTxEntity, LocalTxEntity, QQueryProperty> {
  QueryBuilder<LocalTxEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations> accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations>
  amountDeltaFenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'amountDeltaFen');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations> blockHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'blockHash');
    });
  }

  QueryBuilder<LocalTxEntity, int?, QQueryOperations> blockNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'blockNumber');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations>
  callDataHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'callDataHash');
    });
  }

  QueryBuilder<LocalTxEntity, int?, QQueryOperations>
  confirmedAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'confirmedAtMillis');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations>
  counterpartySs58AddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'counterpartySs58Address');
    });
  }

  QueryBuilder<LocalTxEntity, int, QQueryOperations> createdAtMillisProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAtMillis');
    });
  }

  QueryBuilder<LocalTxEntity, int?, QQueryOperations> eventIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'eventIndex');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations> executionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'executionId');
    });
  }

  QueryBuilder<LocalTxEntity, int?, QQueryOperations> extrinsicIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'extrinsicIndex');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations>
  failureReasonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'failureReason');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations> feeFenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'feeFen');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations>
  fromSs58AddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fromSs58Address');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations> recordKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'recordKey');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations> remarkProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'remark');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations> sourceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'source');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations> ss58AddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ss58Address');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations> statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations>
  toSs58AddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'toSs58Address');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations>
  transferAmountFenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'transferAmountFen');
    });
  }

  QueryBuilder<LocalTxEntity, String?, QQueryOperations> txHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'txHash');
    });
  }

  QueryBuilder<LocalTxEntity, String, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }

  QueryBuilder<LocalTxEntity, int?, QQueryOperations> usedNonceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'usedNonce');
    });
  }
}
