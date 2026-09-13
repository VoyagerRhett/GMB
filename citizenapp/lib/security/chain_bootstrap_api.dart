import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:citizenapp/citizen/shared/account_derivation.dart';

class ChainBootstrapApiException implements Exception {
  const ChainBootstrapApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChainBootstrapApiConfig {
  const ChainBootstrapApiConfig._();

  /// 链启动清单与广场/聊天共用同一个 Cloudflare Worker 入口。
  ///
  /// 这里复用广场 API define，避免 App 出现两个 Worker 根地址配置。
  static const edgeBaseUrlDefineName = 'SQUARE_API_URL';

  static const prodBaseUrl = 'https://www.crcfrcn.com/api';

  static const _configuredBaseUrl =
      String.fromEnvironment(edgeBaseUrlDefineName);

  static String get defaultBaseUrl {
    if (_configuredBaseUrl.trim().isNotEmpty) {
      return normalizeBaseUrl(_configuredBaseUrl);
    }
    return prodBaseUrl;
  }

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (trimmed.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw UnsupportedError('$edgeBaseUrlDefineName 必须是完整的 Worker API URL');
    }
    final isLocalHttp = uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '::1');
    if (uri.scheme != 'https' && !isLocalHttp) {
      throw UnsupportedError(
        '$edgeBaseUrlDefineName 只允许 HTTPS，或本地调试 http://127.0.0.1',
      );
    }
    return trimmed;
  }
}

class ChainBootstrapApi {
  ChainBootstrapApi({
    String? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 6),
  })  : baseUrl = ChainBootstrapApiConfig.normalizeBaseUrl(
          baseUrl ?? ChainBootstrapApiConfig.defaultBaseUrl,
        ),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;

  Future<ChainBootstrapManifest> fetchManifest() async {
    final uri = Uri.parse('$baseUrl/chain/bootstrap');
    final response = await _http.get(uri, headers: const {
      'accept': 'application/json',
    }).timeout(timeout);

    if (response.statusCode != 200) {
      throw ChainBootstrapApiException(
        '链启动清单读取失败:HTTP ${response.statusCode}',
      );
    }

    final raw = jsonDecode(response.body);
    if (raw is! Map<String, dynamic>) {
      throw const ChainBootstrapApiException('链启动清单不是 JSON 对象');
    }
    return ChainBootstrapManifest.fromJson(raw);
  }

  void close() => _http.close();
}

class ChainBootstrapManifest {
  const ChainBootstrapManifest({
    required this.generatedAt,
    required this.cacheTtlSeconds,
    required this.chain,
    required this.lightClient,
    required this.p2p,
    required this.services,
    required this.security,
  });

  final int generatedAt;
  final int cacheTtlSeconds;
  final ChainBootstrapChain chain;
  final ChainBootstrapLightClient lightClient;
  final ChainBootstrapP2p p2p;
  final ChainBootstrapServices services;
  final ChainBootstrapSecurity security;

  factory ChainBootstrapManifest.fromJson(Map<String, dynamic> json) {
    if (_string(json, 'schema') != 'citizenapp.chain.bootstrap') {
      throw const ChainBootstrapApiException('链启动清单 schema 不匹配');
    }
    if (json['ok'] != true) {
      throw const ChainBootstrapApiException('链启动清单状态不是 ok');
    }
    if (_containsForbiddenRpcUrlKey(json)) {
      throw const ChainBootstrapApiException('链启动清单不得下发 RPC URL');
    }
    if (_containsForbiddenCheckpointKey(json)) {
      throw const ChainBootstrapApiException('链启动清单不得下发远端 checkpoint');
    }

    final manifest = ChainBootstrapManifest(
      generatedAt: _int(json, 'generated_at'),
      cacheTtlSeconds: _int(json, 'cache_ttl_seconds'),
      chain: ChainBootstrapChain.fromJson(_map(json, 'chain')),
      lightClient: ChainBootstrapLightClient.fromJson(
        _map(json, 'light_client'),
      ),
      p2p: ChainBootstrapP2p.fromJson(_map(json, 'p2p')),
      services: ChainBootstrapServices.fromJson(_map(json, 'services')),
      security: ChainBootstrapSecurity.fromJson(_map(json, 'security')),
    );
    if (!manifest.isSafeForLightClient) {
      throw const ChainBootstrapApiException('链启动清单违反轻节点安全边界');
    }
    return manifest;
  }

  bool get isSafeForLightClient =>
      chain.chainId == 'citizenchain' &&
      chain.ss58Format == kGmbSs58Prefix &&
      lightClient.mode == 'smoldot' &&
      lightClient.truthSource == 'p2p_finalized_storage' &&
      !lightClient.apiIsTruth &&
      !security.exposesRpcUrl &&
      !security.rpcProxy &&
      !security.exposesPrivateKeyMaterial &&
      !security.validatorRpcPublic &&
      services.signedExtrinsicRelayIsSafe;
}

class ChainBootstrapChain {
  const ChainBootstrapChain({
    required this.chainId,
    required this.chainName,
    required this.chainType,
    required this.protocolId,
    required this.genesisHash,
    required this.stateRoot,
    required this.ss58Format,
    required this.tokenSymbol,
    required this.tokenDecimals,
  });

  final String chainId;
  final String chainName;
  final String chainType;
  final String protocolId;
  final String genesisHash;
  final String stateRoot;
  final int ss58Format;
  final String tokenSymbol;
  final int tokenDecimals;

  factory ChainBootstrapChain.fromJson(Map<String, dynamic> json) {
    return ChainBootstrapChain(
      chainId: _string(json, 'chain_id'),
      chainName: _string(json, 'chain_name'),
      chainType: _string(json, 'chain_type'),
      protocolId: _string(json, 'protocol_id'),
      genesisHash: _hex32(json, 'genesis_hash'),
      stateRoot: _hex32(json, 'state_root'),
      ss58Format: _int(json, 'ss58_format'),
      tokenSymbol: _string(json, 'token_symbol'),
      tokenDecimals: _int(json, 'token_decimals'),
    );
  }
}

class ChainBootstrapLightClient {
  const ChainBootstrapLightClient({
    required this.mode,
    required this.truthSource,
    required this.apiIsTruth,
    required this.bundledAssetsRequired,
  });

  final String mode;
  final String truthSource;
  final bool apiIsTruth;
  final List<String> bundledAssetsRequired;

  factory ChainBootstrapLightClient.fromJson(Map<String, dynamic> json) {
    const requiredKeys = {
      'mode',
      'truth_source',
      'api_is_truth',
      'bundled_assets_required',
    };
    if (json.length != requiredKeys.length ||
        !requiredKeys.every(json.containsKey)) {
      throw const ChainBootstrapApiException(
        '链启动清单 light_client 字段不完整或包含未知字段',
      );
    }
    final bundledAssets = json['bundled_assets_required'];
    if (bundledAssets is! List ||
        bundledAssets.length != 2 ||
        bundledAssets[0] != 'assets/chainspec.json' ||
        bundledAssets[1] != 'assets/light_sync_state.json') {
      throw const ChainBootstrapApiException(
        '链启动清单 bundled_assets_required 无效',
      );
    }
    return ChainBootstrapLightClient(
      mode: _string(json, 'mode'),
      truthSource: _string(json, 'truth_source'),
      apiIsTruth: _bool(json, 'api_is_truth'),
      bundledAssetsRequired: List<String>.unmodifiable(
        bundledAssets.cast<String>(),
      ),
    );
  }
}

class ChainBootstrapP2p {
  const ChainBootstrapP2p({
    required this.bootnodes,
    required this.bootnodesSource,
    required this.minPeerCountHint,
  });

  final List<String> bootnodes;
  final String bootnodesSource;
  final int minPeerCountHint;

  factory ChainBootstrapP2p.fromJson(Map<String, dynamic> json) {
    final rawBootnodes = json['bootnodes'];
    if (rawBootnodes is! List) {
      throw const ChainBootstrapApiException('链启动清单 bootnodes 缺失');
    }
    final bootnodes = <String>[];
    for (final item in rawBootnodes) {
      if (item is String && _isBootnode(item)) {
        bootnodes.add(item);
      }
    }
    return ChainBootstrapP2p(
      bootnodes: List.unmodifiable(bootnodes),
      bootnodesSource: _string(json, 'bootnodes_source'),
      minPeerCountHint: _int(json, 'min_peer_count_hint'),
    );
  }
}

class ChainBootstrapServices {
  const ChainBootstrapServices({
    required this.squareBaseUrl,
    required this.chatBaseUrl,
    required this.mediaBaseUrl,
    required this.signedExtrinsicRelayEnabled,
    required this.signedExtrinsicRelayPath,
  });

  final String squareBaseUrl;
  final String chatBaseUrl;
  final String mediaBaseUrl;
  final bool signedExtrinsicRelayEnabled;
  final String? signedExtrinsicRelayPath;

  bool get signedExtrinsicRelayIsSafe =>
      !signedExtrinsicRelayEnabled ||
      signedExtrinsicRelayPath == '/chain/extrinsics/relay';

  factory ChainBootstrapServices.fromJson(Map<String, dynamic> json) {
    final relay = _map(json, 'signed_extrinsic_relay');
    return ChainBootstrapServices(
      squareBaseUrl: _httpsOrLocalUrl(json, 'square_base_url'),
      chatBaseUrl: _httpsOrLocalUrl(json, 'chat_base_url'),
      mediaBaseUrl: _httpsOrLocalUrl(json, 'media_base_url'),
      signedExtrinsicRelayEnabled: _bool(relay, 'enabled'),
      signedExtrinsicRelayPath: _relayPath(relay),
    );
  }
}

class ChainBootstrapSecurity {
  const ChainBootstrapSecurity({
    required this.exposesRpcUrl,
    required this.rpcProxy,
    required this.exposesPrivateKeyMaterial,
    required this.validatorRpcPublic,
  });

  final bool exposesRpcUrl;
  final bool rpcProxy;
  final bool exposesPrivateKeyMaterial;
  final bool validatorRpcPublic;

  factory ChainBootstrapSecurity.fromJson(Map<String, dynamic> json) {
    return ChainBootstrapSecurity(
      exposesRpcUrl: _bool(json, 'exposes_rpc_url'),
      rpcProxy: _bool(json, 'rpc_proxy'),
      exposesPrivateKeyMaterial: _bool(json, 'exposes_private_key_material'),
      validatorRpcPublic: _bool(json, 'validator_rpc_public'),
    );
  }
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw ChainBootstrapApiException('链启动清单缺少 $key');
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw ChainBootstrapApiException('链启动清单字段 $key 无效');
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) {
    return value;
  }
  throw ChainBootstrapApiException('链启动清单字段 $key 无效');
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw ChainBootstrapApiException('链启动清单字段 $key 无效');
}

String _hex32(Map<String, dynamic> json, String key) {
  final value = _string(json, key).toLowerCase();
  if (RegExp(r'^0x[0-9a-f]{64}$').hasMatch(value)) {
    return value;
  }
  throw ChainBootstrapApiException('链启动清单字段 $key 不是 32 字节 hex');
}

String _httpsOrLocalUrl(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  final uri = Uri.tryParse(value);
  final isLocalHttp = uri?.scheme == 'http' &&
      (uri?.host == '127.0.0.1' ||
          uri?.host == 'localhost' ||
          uri?.host == '::1');
  if (uri != null &&
      uri.hasScheme &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'https' || isLocalHttp)) {
    return value;
  }
  throw ChainBootstrapApiException('链启动清单字段 $key 不是允许的 URL');
}

String? _relayPath(Map<String, dynamic> json) {
  final enabled = _bool(json, 'enabled');
  final value = json['path'];
  if (!enabled) {
    return null;
  }
  if (value == '/chain/extrinsics/relay') {
    return value as String;
  }
  throw const ChainBootstrapApiException(
      '链启动清单 signed_extrinsic_relay path 无效');
}

bool _isBootnode(String value) {
  return value.startsWith('/') &&
      value.contains('/p2p/') &&
      value.length <= 256;
}

bool _containsForbiddenRpcUrlKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'rpc_url' ||
          key == 'validator_rpc_url' ||
          key == 'archive_rpc_url' ||
          key == 'chain_rpc_url' ||
          key == 'square_chain_rpc_url') {
        return true;
      }
      if (_containsForbiddenRpcUrlKey(entry.value)) {
        return true;
      }
    }
  }
  if (value is List) {
    return value.any(_containsForbiddenRpcUrlKey);
  }
  return false;
}

bool _containsForbiddenCheckpointKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'checkpoint' ||
          key == 'light_sync_state_url' ||
          key == 'light_sync_state_sha256') {
        return true;
      }
      if (_containsForbiddenCheckpointKey(entry.value)) {
        return true;
      }
    }
  }
  if (value is List) {
    return value.any(_containsForbiddenCheckpointKey);
  }
  return false;
}
