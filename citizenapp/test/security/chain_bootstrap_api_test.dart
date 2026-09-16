import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/security/chain_bootstrap_api.dart';

const _bootnodeA =
    '/dns4/nrcgch.crcfrcn.com/tcp/30333/wss/p2p/12D3KooWHepcMGD3h9VC1XNWmrac3pXo63RimV5jhTU2nC2TLAyS';
const _bootnodeB =
    '/dns4/prczss.crcfrcn.com/tcp/30333/wss/p2p/12D3KooWPjWNXvCzPv6PPuiGnF3J5uToW3ySfaB7rKkwUrN2CALv';
// 启动清单协议夹具使用合成状态根，避免复制真实冻结锚点。
const _stateRoot =
    '0x4444444444444444444444444444444444444444444444444444444444444444';

void main() {
  test('ChainBootstrapApi 拉取并解析安全启动清单', () async {
    final api = ChainBootstrapApi(
      baseUrl: 'http://127.0.0.1:8787',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/chain/bootstrap');
        return http.Response(
          jsonEncode(_manifest()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final manifest = await api.fetchManifest();

    expect(manifest.chain.chainId, 'citizenchain');
    expect(manifest.chain.ss58Format, 2027);
    expect(manifest.lightClient.apiIsTruth, isFalse);
    expect(manifest.lightClient.bundledAssetsRequired, [
      'assets/chainspec.json',
      'assets/light_sync_state.json',
    ]);
    expect(manifest.security.rpcProxy, isFalse);
    expect(manifest.services.signedExtrinsicRelayEnabled, isFalse);
    expect(manifest.p2p.bootnodes, [_bootnodeA, _bootnodeB]);
  });

  test('ChainBootstrapApi 拒绝 API-only 或 RPC proxy 清单', () {
    final apiTruth = _manifest();
    (apiTruth['light_client'] as Map<String, dynamic>)['api_is_truth'] = true;

    expect(
      () => ChainBootstrapManifest.fromJson(apiTruth),
      throwsA(isA<ChainBootstrapApiException>()),
    );

    final rpcProxy = _manifest();
    (rpcProxy['security'] as Map<String, dynamic>)['rpc_proxy'] = true;

    expect(
      () => ChainBootstrapManifest.fromJson(rpcProxy),
      throwsA(isA<ChainBootstrapApiException>()),
    );
  });

  test('ChainBootstrapApi 拒绝任何 RPC URL 字段', () {
    final data = _manifest()
      ..['archive_rpc_url'] = 'https://rpc.example.invalid';

    expect(
      () => ChainBootstrapManifest.fromJson(data),
      throwsA(isA<ChainBootstrapApiException>()),
    );
  });

  test('ChainBootstrapApi 拒绝非法 schema 和任何远端 checkpoint 字段', () {
    final invalidManifest = _manifest()
      ..['schema'] = 'citizenapp.chain.bootstrap.invalid';
    expect(
      () => ChainBootstrapManifest.fromJson(invalidManifest),
      throwsA(isA<ChainBootstrapApiException>()),
    );

    final checkpoint = _manifest();
    (checkpoint['light_client'] as Map<String, dynamic>)['checkpoint'] = {
      'source': 'remote_url',
      'light_sync_state_url': 'https://api.example/light-sync-state.json',
      'light_sync_state_sha256': 'ab' * 32,
    };
    expect(
      () => ChainBootstrapManifest.fromJson(checkpoint),
      throwsA(isA<ChainBootstrapApiException>()),
    );
  });

  test('ChainBootstrapApi 只接受固定 signed extrinsic relay path', () {
    final enabled = _manifest();
    (enabled['services'] as Map<String, dynamic>)['signed_extrinsic_relay'] = {
      'enabled': true,
      'path': '/chain/extrinsics/relay',
    };

    final parsed = ChainBootstrapManifest.fromJson(enabled);
    expect(parsed.services.signedExtrinsicRelayEnabled, isTrue);
    expect(parsed.services.signedExtrinsicRelayPath, '/chain/extrinsics/relay');

    final badPath = _manifest();
    (badPath['services'] as Map<String, dynamic>)['signed_extrinsic_relay'] = {
      'enabled': true,
      'path': '/chain/rpc',
    };

    expect(
      () => ChainBootstrapManifest.fromJson(badPath),
      throwsA(isA<ChainBootstrapApiException>()),
    );
  });

  test('ChainBootstrapApiConfig 只允许 HTTPS 或本地 HTTP', () {
    expect(
      ChainBootstrapApiConfig.normalizeBaseUrl('https://api.onchina.org/'),
      'https://api.onchina.org',
    );
    expect(
      ChainBootstrapApiConfig.normalizeBaseUrl('http://127.0.0.1:8787/'),
      'http://127.0.0.1:8787',
    );
    expect(
      () => ChainBootstrapApiConfig.normalizeBaseUrl('http://api.onchina.org'),
      throwsUnsupportedError,
    );
  });
}

Map<String, dynamic> _manifest() => {
  'ok': true,
  'schema': 'citizenapp.chain.bootstrap',
  'generated_at': 1800000000000,
  'cache_ttl_seconds': 300,
  'chain': {
    'chain_id': 'citizenchain',
    'chain_name': 'CitizenChain',
    'chain_type': 'Live',
    'protocol_id': 'citizenchain',
    // 协议解析夹具使用合成哈希，不复制真实创世锚点。
    'genesis_hash':
        '0x2222222222222222222222222222222222222222222222222222222222222222',
    'state_root': _stateRoot,
    'ss58_format': 2027,
    'token_symbol': 'GMB',
    'token_decimals': 2,
  },
  'light_client': {
    'mode': 'smoldot',
    'truth_source': 'p2p_finalized_storage',
    'api_is_truth': false,
    'bundled_assets_required': [
      'assets/chainspec.json',
      'assets/light_sync_state.json',
    ],
  },
  'p2p': {
    'bootnodes': [_bootnodeA, _bootnodeB],
    'bootnodes_source': 'worker_config',
    'min_peer_count_hint': 1,
  },
  'services': {
    'square_base_url': 'https://api.onchina.org/square',
    'media_base_url': 'https://api.onchina.org/square/media',
    'signed_extrinsic_relay': {'enabled': false, 'path': null},
  },
  'security': {
    'exposes_rpc_url': false,
    'rpc_proxy': false,
    'exposes_private_key_material': false,
    'validator_rpc_public': false,
  },
  'degradation': {
    'p2p_unavailable': 'services_continue_chain_state_degraded',
    'chain_success_source': 'finalized_runtime_storage_or_events',
  },
};
