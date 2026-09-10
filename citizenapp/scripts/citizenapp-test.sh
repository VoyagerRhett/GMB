#!/usr/bin/env bash
# CitizenApp 本机与 CI 唯一 Flutter 测试入口。
#
# flutter_tester 是宿主进程，不会链接 iOS Runner 的 libsmoldot.a，也不会使用
# Android APK 内的 libsmoldot.so。任何 Dart FFI 测试开始前，必须先构建并验收
# 当前宿主的 libsmoldot.dylib/so；随后才允许 analyze 和顺序执行测试。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CITIZENAPP_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$CITIZENAPP_DIR")"
export GMB_ROOT="$REPO_ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
FLUTTER_ROOT="$CITIZENAPP_DIR"
ANALYSIS_CONFIG=''
TEST_CONFIG=''
TEST_CONFIGS_STAGED=false

if [[ "${CI:-}" != true ]]; then
  : "${TATA_CONSOLE_TARGET_ROOT:?本机检查必须由控制台提供中央产物根}"
  : "${TATA_CONSOLE_CACHE_DIR:?本机检查必须由控制台提供当前任务目录}"
  : "${TATA_CONSOLE_FLUTTER_ROOT:?本机检查必须使用当前任务Flutter配置}"
  case "$TATA_CONSOLE_CACHE_DIR" in
    "${TATA_CONSOLE_TARGET_ROOT%/target}/cache/gmb/citizenapp/ios"|"${TATA_CONSOLE_TARGET_ROOT%/target}/cache/gmb/citizenapp/android") ;;
    *) echo 'CitizenApp 本机检查只能在所属移动端任务内执行' >&2; exit 1 ;;
  esac
  # 检查沿用调用方持有的本端身份；不抢占目录、不复制源码、不删除别的运行记录。
  python3 - "$TATA_CONSOLE_CACHE_DIR" "gmb.citizenapp.${TATA_CONSOLE_CACHE_DIR##*/}.build" <<'PY'
import json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
lock = root / '.owner'
if str(root.resolve()) != str(root) or lock.is_symlink() or not lock.is_file():
    raise SystemExit('CitizenApp 检查缺少本端任务所有权')
owner = json.loads(lock.read_text())
if owner.get('canonicalId') != sys.argv[2] or not owner.get('runId') or not isinstance(owner.get('pid'), int) or owner['pid'] <= 0:
    raise SystemExit('CitizenApp 检查任务身份不匹配')
if os.environ.get('TATA_CONSOLE_RUN_ID') != owner['runId']:
    raise SystemExit('CitizenApp 检查运行任务不匹配')
os.kill(owner['pid'], 0)
PY
  [[ "$TATA_CONSOLE_FLUTTER_ROOT" == "$TATA_CONSOLE_CACHE_DIR" \
    && -f "$TATA_CONSOLE_FLUTTER_ROOT/pubspec.yaml" \
    && ! -L "$TATA_CONSOLE_FLUTTER_ROOT/pubspec.yaml" \
    && -f "$TATA_CONSOLE_FLUTTER_ROOT/pubspec_overrides.yaml" \
    && ! -L "$TATA_CONSOLE_FLUTTER_ROOT/pubspec_overrides.yaml" ]] || {
    echo 'CitizenApp 检查缺少本端独立依赖配置' >&2; exit 1
  }
  FLUTTER_ROOT="$TATA_CONSOLE_FLUTTER_ROOT"
  : "${TATA_CONSOLE_BUILD_CACHE_DIR:?CitizenApp检查缺少本轮编译目录}"
  : "${TATA_CONSOLE_DEPENDENCY_CACHE_DIR:?CitizenApp检查缺少本轮依赖目录}"
  [[ "$TATA_CONSOLE_BUILD_CACHE_DIR" == "$TATA_CONSOLE_CACHE_DIR/build" \
    && "$TATA_CONSOLE_DEPENDENCY_CACHE_DIR" == "$TATA_CONSOLE_CACHE_DIR/dependencies" ]] || {
    echo 'CitizenApp检查目录职责不一致' >&2; exit 1
  }
  export CARGO_TARGET_DIR="$TATA_CONSOLE_BUILD_CACHE_DIR/cargo-tests"
  export PUB_CACHE="$TATA_CONSOLE_DEPENDENCY_CACHE_DIR/dart-pub"
  export XDG_CONFIG_HOME="$TATA_CONSOLE_DEPENDENCY_CACHE_DIR/flutter-config"
  export TMPDIR="$TATA_CONSOLE_BUILD_CACHE_DIR/tmp"
  mkdir -p "$TMPDIR"
  export DYLD_LIBRARY_PATH="$CARGO_TARGET_DIR/release:$CARGO_TARGET_DIR/debug"
  export LD_LIBRARY_PATH="$CARGO_TARGET_DIR/release:$CARGO_TARGET_DIR/debug"
fi

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "错误: 找不到 Flutter: $FLUTTER_BIN" >&2
  exit 1
fi

EXPECTED_FLUTTER_VERSION="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["toolchains"]["flutter"])' \
    "$REPO_ROOT/.github/dependencies.json"
)"
ACTUAL_FLUTTER_VERSION="$(
  "$FLUTTER_BIN" --version --machine \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])'
)"
if [ "$ACTUAL_FLUTTER_VERSION" != "$EXPECTED_FLUTTER_VERSION" ]; then
  echo "错误: Flutter 版本为 $ACTUAL_FLUTTER_VERSION，仓库要求 $EXPECTED_FLUTTER_VERSION" >&2
  exit 1
fi

if [ ! -f "$FLUTTER_ROOT/.dart_tool/package_config.json" ]; then
  if [[ "${CI:-}" == true ]]; then
    echo "错误: 缺少 .dart_tool/package_config.json；CI必须先执行锁定依赖解析" >&2
    exit 1
  fi
  (cd "$FLUTTER_ROOT" && "$FLUTTER_BIN" pub get --enforce-lockfile)
fi

# 设备 Release 构建会先 cargo clean；测试必须从宿主库构建开始一直持锁到最后一个
# flutter_tester 退出，禁止其它进程在测试中途删除 dylib/so。macOS 用系统 shlock
# 自动识别死亡 PID，Linux CI 用 util-linux flock，二者都不依赖仓库内状态文件。
NATIVE_BUILD_LOCK_PATH="${TMPDIR:-/tmp}/gmb-citizenapp-native-build.lock"
NATIVE_BUILD_LOCK_KIND=""
acquire_native_build_lock() {
  case "$(uname -s)" in
    Darwin)
      while ! shlock -f "$NATIVE_BUILD_LOCK_PATH" -p $$; do
        echo "等待 CitizenApp 设备原生构建结束..."
        sleep 1
      done
      NATIVE_BUILD_LOCK_KIND=shlock
      ;;
    Linux)
      exec 9>"$NATIVE_BUILD_LOCK_PATH"
      flock 9
      NATIVE_BUILD_LOCK_KIND=flock
      ;;
    *)
      echo "错误: 不支持的原生测试锁平台：$(uname -s)" >&2
      return 1
      ;;
  esac
}
release_native_build_lock() {
  case "$NATIVE_BUILD_LOCK_KIND" in
    shlock)
      if [[ "$(cat "$NATIVE_BUILD_LOCK_PATH" 2>/dev/null || true)" == "$$" ]]; then
        rm -f -- "$NATIVE_BUILD_LOCK_PATH"
      fi
      ;;
    flock)
      flock -u 9
      exec 9>&-
      ;;
  esac
  NATIVE_BUILD_LOCK_KIND=""
}

cleanup_test_configs() {
  if [[ "$TEST_CONFIGS_STAGED" == true ]]; then
    rm -f -- "$ANALYSIS_CONFIG" "$TEST_CONFIG"
  fi
  release_native_build_lock
}

cd "$FLUTTER_ROOT"
# Flutter 只从工程根发现这两类配置；源码真源统一放在 scripts，执行期间只在本次
# CI 检出或塔塔工作目录短暂落盘，退出时必定清理。
ANALYSIS_CONFIG="$FLUTTER_ROOT/analysis_options.yaml"
TEST_CONFIG="$FLUTTER_ROOT/dart_test.yaml"
trap cleanup_test_configs EXIT
if [[ ! -e "$ANALYSIS_CONFIG" && ! -L "$ANALYSIS_CONFIG"
  && ! -e "$TEST_CONFIG" && ! -L "$TEST_CONFIG" ]]; then
  TEST_CONFIGS_STAGED=true
  cp "$SCRIPT_DIR/analysis_options.yaml" "$ANALYSIS_CONFIG"
  cp "$SCRIPT_DIR/dart_test.yaml" "$TEST_CONFIG"
elif [[ "$FLUTTER_ROOT" == "$CITIZENAPP_DIR" || ! -f "$ANALYSIS_CONFIG" || -L "$ANALYSIS_CONFIG"
  || ! -f "$TEST_CONFIG" || -L "$TEST_CONFIG" ]]; then
  echo '错误: Flutter 工程根存在不受塔塔任务管理的分析或测试配置' >&2
  exit 1
fi
# GitHub Runner 保持既有原生锁；本机由控制台的准确任务所有权隔离，不使用跨端共享锁。
if [[ "${CI:-}" == true ]]; then
  acquire_native_build_lock
fi
if rg -n --hidden --glob '!target/**' 'tatachat_sdk' "$CITIZENAPP_DIR/smoldot"; then
  echo '错误: CitizenApp Smoldot 目录仍包含 TataChatSDK 编译或链接依赖' >&2
  exit 1
fi
"$SCRIPT_DIR/build-smoldot-native.sh" host
"$SCRIPT_DIR/../../../TATA/tatachatsdk/scripts/build-native.sh" host
"$FLUTTER_BIN" analyze --no-pub
"$FLUTTER_BIN" test --no-pub --concurrency=1 "$@"
