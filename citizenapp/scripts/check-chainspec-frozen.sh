#!/usr/bin/env bash
# CitizenApp 轻节点 chainspec 守卫。
#
# 新创世形态:
#   - 链端 SSOT = citizenchain/node/citizenchain.json
#     (runtime WASM + genesis patch + bootnodes,不含 GB 级 raw state)
#   - CitizenApp = assets/chainspec.json 轻形态,genesis 只允许携带 stateRootHash
#   - stateRootHash 来自 bake-chainspec.sh 临时节点物化块 0 后读取的 state_root
#
# 代码 CI 阶段允许 App 资产尚未 finalize,但正式发包前必须设置
# CITIZENAPP_REQUIRE_STATE_ROOT=1,强制拒绝旧 raw 资产。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CITIZENAPP="${CITIZENAPP_CHAINSPEC:-$REPO_ROOT/citizenapp/assets/chainspec.json}"
LIGHT_SYNC_STATE="${CITIZENAPP_LIGHT_SYNC_STATE:-$REPO_ROOT/citizenapp/assets/light_sync_state.json}"
SSOT="${CITIZENCHAIN_PLAIN_SPEC:-$REPO_ROOT/citizenchain/node/citizenchain.json}"
# 本地 preview manifest 不得自动拿来校验当前冻结资产；只有调用方显式传入时才交叉验证。
GENESIS_MANIFEST="${CITIZENCHAIN_GENESIS_STATE_MANIFEST:-}"
PUBLIC_INSTITUTION_MANIFEST="${CITIZENAPP_PUBLIC_INSTITUTION_MANIFEST:-$REPO_ROOT/citizenapp/assets/public_institutions/manifest.json}"
CLOUDFLARE_WRANGLER="${CITIZENSERVE_CLOUDFLARE_WRANGLER:-$REPO_ROOT/citizenserve/scripts/wrangler.toml}"
CLOUDFLARE_BOOTSTRAP_SOURCE="${CITIZENSERVE_CLOUDFLARE_BOOTSTRAP_SOURCE:-$REPO_ROOT/citizenserve/src/chain/bootstrap.ts}"
REQUIRE_STATE_ROOT="${CITIZENAPP_REQUIRE_STATE_ROOT:-0}"

python3 - "$CITIZENAPP" "$SSOT" "$GENESIS_MANIFEST" "$LIGHT_SYNC_STATE" "$PUBLIC_INSTITUTION_MANIFEST" "$CLOUDFLARE_WRANGLER" "$CLOUDFLARE_BOOTSTRAP_SOURCE" "$REQUIRE_STATE_ROOT" <<'PY'
import hashlib
import json
import os
import re
import sys

(
    app_path,
    ssot_path,
    manifest_path,
    light_sync_state_path,
    public_manifest_path,
    wrangler_path,
    bootstrap_source_path,
    require_state_root,
) = sys.argv[1:]
errors = []
warnings = []

def load_json(path, label):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        errors.append(f"{label} 不存在或为空:{path}")
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as exc:
        errors.append(f"{label} JSON 解析失败:{exc}")
        return {}

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

app = load_json(app_path, "CitizenApp chainspec")
ssot = load_json(ssot_path, "节点 plain SSOT")
public_manifest = load_json(public_manifest_path, "公权机构缓存 manifest")

if ssot:
    if ssot.get("id") != "citizenchain":
        errors.append("节点 plain SSOT id 必须为 citizenchain")
    ssot_genesis = ssot.get("genesis") or {}
    if "runtimeGenesis" not in ssot_genesis:
        errors.append("节点 plain SSOT 必须是 runtimeGenesis plain 形态")
    if "raw" in ssot_genesis:
        errors.append("节点 plain SSOT 不得包含 raw genesis")

if app:
    if app.get("id") != "citizenchain":
        errors.append("CitizenApp chainspec id 必须为 citizenchain")
    if ssot and app.get("protocolId") != ssot.get("protocolId"):
        errors.append("CitizenApp protocolId 必须与节点 plain SSOT 一致")
    if "lightSyncState" in app:
        errors.append("CitizenApp chainspec 不得内嵌 lightSyncState,必须使用 assets/light_sync_state.json")
    app_genesis = app.get("genesis") or {}
    state_root = app_genesis.get("stateRootHash")
    if state_root:
        if not re.fullmatch(r"0x[0-9a-fA-F]{64}", state_root):
            errors.append("CitizenApp genesis.stateRootHash 必须为 0x + 64 位十六进制")
        if "raw" in app_genesis or "runtimeGenesis" in app_genesis:
            errors.append("CitizenApp 轻形态不得同时携带 raw/runtimeGenesis")
        if manifest_path and os.path.isfile(manifest_path):
            manifest = load_json(manifest_path, "创世状态包 manifest")
            manifest_state_root = manifest.get("state_root")
            if manifest_state_root and manifest_state_root.lower() != state_root.lower():
                errors.append(
                    "CitizenApp stateRootHash 与创世状态包 manifest.state_root 不一致:"
                    f" app={state_root} manifest={manifest_state_root}"
                )
            if manifest.get("chain_id") and manifest.get("chain_id") != "citizenchain":
                errors.append("创世状态包 manifest.chain_id 必须为 citizenchain")
            if manifest.get("artifact_stage") not in ("preview", "release"):
                errors.append("创世状态包 manifest.artifact_stage 必须为 preview 或 release")
            if manifest.get("chainspec_hash") and manifest.get("chainspec_hash") != sha256_file(ssot_path):
                errors.append("创世状态包 chainspec_hash 与节点 plain SSOT 不一致")
            manifest_lss_hash = manifest.get("light_sync_state_hash")
            if manifest_lss_hash and os.path.isfile(light_sync_state_path):
                actual_lss_hash = sha256_file(light_sync_state_path)
                if actual_lss_hash != manifest_lss_hash:
                    errors.append(
                        "CitizenApp light_sync_state.json 与创世状态包 manifest.light_sync_state_hash 不一致:"
                        f" app={actual_lss_hash} manifest={manifest_lss_hash}"
                    )
        elif manifest_path:
            warnings.append(f"未找到创世状态包 manifest,跳过 stateRootHash 交叉校验:{manifest_path}")
        lss = load_json(light_sync_state_path, "CitizenApp light_sync_state")
        if not lss:
            errors.append("CitizenApp light_sync_state.json 不得为空,否则 smoldot 无法加入 stateRootHash 轻形态链")
        else:
            for key in ("finalizedBlockHeader", "grandpaAuthoritySet"):
                value = lss.get(key)
                if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]+", value):
                    errors.append(f"CitizenApp light_sync_state.{key} 必须为 0x 十六进制字符串")

            header_hex = lss.get("finalizedBlockHeader", "")
            checkpoint_genesis_hash = ""
            if isinstance(header_hex, str) and re.fullmatch(r"0x[0-9a-fA-F]+", header_hex):
                header_bytes = bytes.fromhex(header_hex[2:])
                checkpoint_genesis_hash = "0x" + hashlib.blake2b(
                    header_bytes,
                    digest_size=32,
                ).hexdigest()
                # bake 流程钉死块 0；Header 编码为 parentHash + Compact(0) + stateRoot + ...。
                if len(header_bytes) < 65 or header_bytes[32] != 0:
                    errors.append("CitizenApp light_sync_state checkpoint 必须钉死块 0")
                elif state_root and header_bytes[33:65].hex().lower() != state_root[2:].lower():
                    errors.append("CitizenApp checkpoint 块 0 stateRoot 与 chainspec 不一致")

            if public_manifest:
                expected_public_manifest_fields = {
                    "chain_id", "snapshot_block_number", "snapshot_block_hash",
                    "genesis_hash", "state_root", "chainspec_hash",
                    "public_institution_root", "version", "shard_hashes", "provinces",
                }
                if public_manifest.get("chain_id") != "citizenchain" or set(public_manifest) != expected_public_manifest_fields:
                    errors.append("公权机构缓存 manifest 身份无效")
                if public_manifest.get("chainspec_hash") != sha256_file(app_path):
                    errors.append("公权机构缓存 chainspec_hash 与 CitizenApp chainspec 不一致")
                public_genesis = str(public_manifest.get("genesis_hash", "")).lower()
                if checkpoint_genesis_hash and public_genesis != checkpoint_genesis_hash.lower():
                    errors.append("公权机构缓存 genesis_hash 与 light_sync_state 块 0 不一致")

                provinces = public_manifest.get("provinces")
                if not isinstance(provinces, list) or len(provinces) != 43:
                    errors.append("公权机构缓存必须精确包含 43 个省级分片")
                else:
                    public_dir = os.path.dirname(public_manifest_path)
                    for item in provinces:
                        province_name = item.get("province_name")
                        shard_path = os.path.join(public_dir, f"{province_name}.json")
                        if not os.path.isfile(shard_path):
                            errors.append(f"公权机构缓存分片缺失:{province_name}")
                        elif item.get("shard_hash") != sha256_file(shard_path):
                            errors.append(f"公权机构缓存分片哈希不一致:{province_name}")
                    root_json = json.dumps(provinces, ensure_ascii=False, separators=(",", ":"))
                    computed_root = hashlib.sha256(root_json.encode()).hexdigest()
                    if public_manifest.get("public_institution_root") != computed_root:
                        errors.append("公权机构缓存 public_institution_root 校验失败")

                if manifest_path and os.path.isfile(manifest_path):
                    manifest_public_root = manifest.get("public_institution_root")
                    if manifest_public_root and manifest_public_root != public_manifest.get("public_institution_root"):
                        errors.append("创世状态包与公权机构缓存 public_institution_root 不一致")

            if not os.path.isfile(wrangler_path):
                errors.append(f"Cloudflare wrangler.toml 不存在:{wrangler_path}")
            else:
                with open(wrangler_path, encoding="utf-8") as f:
                    wrangler_text = f.read()
                genesis_values = set(re.findall(
                    r'^\s*CHAIN_GENESIS_HASH\s*=\s*"(0x[0-9a-fA-F]{64})"\s*$',
                    wrangler_text,
                    flags=re.MULTILINE,
                ))
                state_root_values = set(re.findall(
                    r'^\s*CHAIN_STATE_ROOT\s*=\s*"(0x[0-9a-fA-F]{64})"\s*$',
                    wrangler_text,
                    flags=re.MULTILINE,
                ))
                if len(genesis_values) != 1 or len(state_root_values) != 1:
                    errors.append("Cloudflare 各环境必须配置同一个合法 genesis_hash/state_root")
                else:
                    wrangler_genesis = next(iter(genesis_values)).lower()
                    wrangler_state_root = next(iter(state_root_values)).lower()
                    if checkpoint_genesis_hash and wrangler_genesis != checkpoint_genesis_hash.lower():
                        errors.append("Cloudflare genesis_hash 与 light_sync_state 块 0 不一致")
                    if state_root and wrangler_state_root != state_root.lower():
                        errors.append("Cloudflare state_root 与 CitizenApp chainspec 不一致")

            if not os.path.isfile(bootstrap_source_path):
                errors.append(f"Cloudflare bootstrap 源码不存在:{bootstrap_source_path}")
            else:
                with open(bootstrap_source_path, encoding="utf-8") as f:
                    bootstrap_source = f.read()
                forbidden_fallbacks = (
                    "DEFAULT_GENESIS_HASH",
                    "DEFAULT_STATE_ROOT",
                    "normalizeHex32(",
                )
                found = [item for item in forbidden_fallbacks if item in bootstrap_source]
                if found or "requireHex32(" not in bootstrap_source:
                    errors.append("Cloudflare 链身份必须失败关闭,不得保留历史锚点回落")
    elif "raw" in app_genesis:
        msg = (
            "CitizenApp chainspec 仍为旧 raw 形态。代码 CI 可暂时通过,"
            "但正式创世后必须由 bake-chainspec.sh 生成 stateRootHash 轻形态。"
        )
        if require_state_root == "1":
            errors.append(msg)
        else:
            warnings.append(msg)
    else:
        errors.append("CitizenApp chainspec 必须携带 genesis.stateRootHash")

if errors:
    print("[chainspec-ssot] 拒绝:", file=sys.stderr)
    for item in errors:
        print(f"  - {item}", file=sys.stderr)
    print("修复:先运行 preview 校验；正式冻结阶段再使用同提交 CI WASM 执行 --finalize。", file=sys.stderr)
    sys.exit(1)

for item in warnings:
    print(f"[chainspec-ssot][warn] {item}")
print("[chainspec-ssot] 节点/App/checkpoint/公权缓存/Cloudflare 阶段校验通过")
PY
