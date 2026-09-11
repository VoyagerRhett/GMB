#!/usr/bin/env bash
# CitizenSDK 唯一本地测试入口；源码只读，所有测试生成物写入塔塔缓存库。
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
  link_target="$(readlink "$script_path")"
  [[ "$link_target" == /* ]] || link_target="$(cd "$(dirname "$script_path")" && pwd -P)/$link_target"
  script_path="$link_target"
done
script_dir="$(cd "$(dirname "$script_path")" && pwd -P)"
sdk_dir="$(dirname "$script_dir")"
cache_root="${TATA_CONSOLE_CACHE_DIR:-/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk}"
test_root="$cache_root/test"
test_smoldot_library="${CITIZENSDK_TEST_SMOLDOT_LIBRARY:-}"

case "$cache_root/" in
  "$sdk_dir/"*) echo 'CitizenSDK 测试缓存禁止位于产品源码树' >&2; exit 1 ;;
esac
[[ "$cache_root" == /* && "$cache_root" != / ]] \
  || { echo 'CitizenSDK 测试缓存必须是绝对目录' >&2; exit 1; }

mkdir -p "$test_root/cargo" "$test_root/flutter" "$test_root/flutter-config" "$test_root/release-tmp"
export CARGO_TARGET_DIR="$test_root/cargo"
export XDG_CONFIG_HOME="$test_root/flutter-config"

flutter_bin="${FLUTTER:-$(command -v flutter || true)}"
cargo_bin="${CARGO:-$(command -v cargo || true)}"
node_bin="${NODE:-$(command -v node || true)}"
central_flow_root="${TATA_CONSOLE_FLOW_ROOT:-/Users/rhett/TATA/tataconsole/flows}"
central_workspace_root="${TATA_WORKSPACE_ROOT:-${TATA_ROOT:-/Users/rhett/TATA}}"

configure_flutter_output() {
  [[ -n "$flutter_bin" && -x "$flutter_bin" ]] \
    || { echo 'CitizenSDK 测试缺少 Flutter' >&2; exit 1; }
  "$flutter_bin" config \
    --build-dir=build \
    --no-enable-native-assets \
    --no-enable-dart-data-assets >/dev/null
}

refresh_flutter_packages() {
  local flutter_sdk_root dart_bin
  flutter_sdk_root="$(cd "$(dirname "$flutter_bin")/.." && pwd -P)"
  dart_bin="$flutter_sdk_root/bin/dart"
  [[ -x "$dart_bin" ]] \
    || { echo 'CitizenSDK 测试缺少 Flutter 同版 Dart' >&2; return 1; }
  (cd "$sdk_dir" && FLUTTER_ROOT="$flutter_sdk_root" \
    "$dart_bin" pub get --offline --enforce-lockfile)
}

prepare_flutter_project() {
  local project_root="$1"
  [[ -d "$project_root" && ! -L "$project_root" ]] \
    || { echo 'CitizenSDK Flutter 隔离测试根无效' >&2; return 1; }
  local source name
  while IFS= read -r -d '' source; do
    name="${source##*/}"
    case "$name" in
      .dart_tool|build|target) continue ;;
    esac
    ln -s "$source" "$project_root/$name"
  done < <(find "$sdk_dir" -mindepth 1 -maxdepth 1 -print0)
  if [[ -n "$test_smoldot_library" ]]; then
    [[ "$test_smoldot_library" == /* && -f "$test_smoldot_library" && ! -L "$test_smoldot_library" ]] \
      || { echo 'CitizenSDK Flutter 测试 smoldot 宿主库必须是绝对普通文件' >&2; return 1; }
    case "$test_smoldot_library" in
      "$sdk_dir"/*) echo 'CitizenSDK Flutter 测试 smoldot 宿主库禁止位于源码树' >&2; return 1 ;;
    esac
    case "$(uname -s)" in
      Darwin) ln -s "$test_smoldot_library" "$project_root/libsmoldot.dylib" ;;
      Linux) ln -s "$test_smoldot_library" "$project_root/libsmoldot.so" ;;
      *) echo 'CitizenSDK Flutter 测试 smoldot 宿主库仅支持 macOS/Linux' >&2; return 1 ;;
    esac
  fi
  command -v node >/dev/null 2>&1 \
    || { echo 'CitizenSDK Flutter 隔离测试缺少 Node' >&2; return 1; }
  mkdir "$project_root/.dart_tool"
  while IFS= read -r -d '' source; do
    name="${source##*/}"
    [[ "$name" == package_config.json ]] && continue
    ln -s "$source" "$project_root/.dart_tool/$name"
  done < <(find "$sdk_dir/.dart_tool" -mindepth 1 -maxdepth 1 -print0)
  node - "$sdk_dir/.dart_tool/package_config.json" \
    "$project_root/.dart_tool/package_config.json" "$project_root" <<'NODE'
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');
const [input, output, projectRoot] = process.argv.slice(2);
const inputUri = pathToFileURL(input);
const config = JSON.parse(fs.readFileSync(input, 'utf8'));
for (const entry of config.packages) {
  const sourceRoot = new URL(entry.rootUri, inputUri).href;
  entry.rootUri = entry.name === 'citizen_sdk'
    ? pathToFileURL(`${projectRoot}/`).href
    : sourceRoot;
}
fs.writeFileSync(output, `${JSON.stringify(config)}\n`, { flag: 'wx' });
NODE
}

cleanup_flutter_project() {
  local project_root="$1"
  case "$project_root/" in
    "$test_root/"flutter-project.*'/') ;;
    *) echo 'CitizenSDK Flutter 隔离测试根越界，拒绝清理' >&2; return 1 ;;
  esac
  [[ -d "$project_root" && ! -L "$project_root" ]] \
    || { echo 'CitizenSDK Flutter 隔离测试根不是普通目录' >&2; return 1; }
  rm -rf -- "$project_root"
}

run_flutter() {
  for argument in "$@"; do
    case "$argument" in
      --test-assets|--test-assets=*)
        echo 'CitizenSDK Flutter 测试禁止启用会写入源码 build 的 test assets' >&2
        return 2
        ;;
    esac
  done
  [[ ! -e "$sdk_dir/build" && ! -L "$sdk_dir/build" ]] \
    || { echo 'CitizenSDK 源码树已存在禁止的 build 条目' >&2; return 1; }
  refresh_flutter_packages || return 1
  local project_root
  project_root="$(mktemp -d "$test_root/flutter-project.XXXXXX")"
  prepare_flutter_project "$project_root" \
    || { cleanup_flutter_project "$project_root"; return 1; }
  configure_flutter_output
  local status=0
  (cd "$project_root" && "$flutter_bin" test --no-pub --no-test-assets \
    --packages="$project_root/.dart_tool/package_config.json" "$@") || status=$?
  [[ ! -e "$sdk_dir/build" && ! -L "$sdk_dir/build" ]] \
    || { echo 'Flutter 测试向 CitizenSDK 源码树写入了禁止的 build 条目' >&2; status=1; }
  cleanup_flutter_project "$project_root" || return 1
  return "$status"
}

run_cargo() {
  [[ -n "$cargo_bin" && -x "$cargo_bin" ]] \
    || { echo 'CitizenSDK 测试缺少 Cargo' >&2; exit 1; }
  (cd "$sdk_dir" && "$cargo_bin" test "$@")
}

run_release() {
  [[ -n "$node_bin" && -x "$node_bin" ]] \
    || { echo 'CitizenSDK 测试缺少 Node' >&2; exit 1; }
  [[ "$central_flow_root" == /* && -d "$central_flow_root" ]] \
    || { echo 'CitizenSDK 发布测试缺少 TataConsole 中央流程目录' >&2; exit 1; }
  [[ "$central_workspace_root" == /* && -d "$central_workspace_root/tataconsole" ]] \
    || { echo 'CitizenSDK 发布测试缺少 TataConsole 中央工作区' >&2; exit 1; }
  (cd "$sdk_dir" && TMPDIR="$test_root/release-tmp" \
    TATA_CONSOLE_CACHE_DIR="$test_root/release-work" \
    TATA_CONSOLE_FLOW_ROOT="$central_flow_root" \
    TATA_WORKSPACE_ROOT="$central_workspace_root" \
    "$node_bin" --test scripts/release.test.mjs "$@")
}

case "${1:-all}" in
  cargo)
    shift
    run_cargo "$@"
    ;;
  flutter)
    shift
    run_flutter "$@"
    ;;
  release)
    shift
    run_release "$@"
    ;;
  all)
    [[ "$#" -le 1 ]] || { echo 'all 模式不接受额外参数' >&2; exit 2; }
    run_cargo --workspace --all-targets --locked
    run_flutter --timeout=2m
    run_release
    ;;
  *)
    echo '用法：scripts/test.sh [all|cargo <cargo-test参数...>|flutter <flutter-test参数...>|release <node-test参数...>]' >&2
    exit 2
    ;;
esac
