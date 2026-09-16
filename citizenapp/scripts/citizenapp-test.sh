#!/usr/bin/env bash
# CitizenApp 本机与 CI 唯一 Flutter 测试入口。
#
# CitizenApp 测试只依赖 CitizenSDK 公开 Dart 合同与可控 fake；不构建或
# 加载 App 自有链库。TataChatSDK 的宿主库仍由其产品脚本准备。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CITIZENAPP_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$CITIZENAPP_DIR")"
export GMB_ROOT="$REPO_ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
VIEW_SCRIPT="$SCRIPT_DIR/citizenapp-view.mjs"
FLUTTER_ROOT=''
ANALYSIS_CONFIG=''
TEST_CONFIG=''
TEST_CONFIGS_STAGED=false
CITIZENAPP_TEST_WORK_DIR="${CITIZENAPP_TEST_WORK_DIR:-${TMPDIR:-/tmp}/citizenapp/test}"
BUILD_CACHE="${CITIZENAPP_TEST_BUILD_DIR:-$CITIZENAPP_TEST_WORK_DIR/work}"
DEPENDENCY_CACHE="${CITIZENAPP_TEST_DEPENDENCY_DIR:-$CITIZENAPP_TEST_WORK_DIR/dependencies}"
python3 - "$CITIZENAPP_DIR" "$CITIZENAPP_TEST_WORK_DIR" "$BUILD_CACHE" "$DEPENDENCY_CACHE" <<'CHECK_OUTPUTS'
from pathlib import Path
import sys
source = Path(sys.argv[1]).resolve()
for value in sys.argv[2:]:
    raw = Path(value)
    target = raw.resolve()
    if not raw.is_absolute() or target == source or source in target.parents:
        raise SystemExit(f'CitizenApp测试目录必须是源码外绝对路径：{value}')
CHECK_OUTPUTS
mkdir -p "$CITIZENAPP_TEST_WORK_DIR"
# Flutter分析、测试、.dart_tool与build全部在源码外工程视图运行；源码文件保持
# 唯一真源且只读投影，测试不得再向CitizenApp根生成build或临时配置。
FLUTTER_ROOT="$(node "$VIEW_SCRIPT" create \
  --source-root "$CITIZENAPP_DIR" --work-root "$CITIZENAPP_TEST_WORK_DIR")"
[[ "$FLUTTER_ROOT" == "$CITIZENAPP_TEST_WORK_DIR/source-view/"* \
  && -f "$FLUTTER_ROOT/pubspec.yaml" ]] \
  || { echo '错误: CitizenApp测试工程视图无效' >&2; exit 1; }
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BUILD_CACHE/cargo-tests}"
export PUB_CACHE="${PUB_CACHE:-$DEPENDENCY_CACHE/dart-pub}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$DEPENDENCY_CACHE/flutter-config}"
export TMPDIR="$BUILD_CACHE/tmp"
mkdir -p "$TMPDIR"
export DYLD_LIBRARY_PATH="$CARGO_TARGET_DIR/release:$CARGO_TARGET_DIR/debug"
export LD_LIBRARY_PATH="$CARGO_TARGET_DIR/release:$CARGO_TARGET_DIR/debug"

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "错误: 找不到 Flutter: $FLUTTER_BIN" >&2
  exit 1
fi

# Flutter 版本由产品开发环境或 CI 工作流唯一确定；测试脚本只消费调用方
# 注入的可执行文件，不维护第二份工具版本表。

if [ ! -f "$FLUTTER_ROOT/.dart_tool/package_config.json" ]; then
  if [[ "${CI:-}" == true ]]; then
    echo "错误: 缺少 .dart_tool/package_config.json；CI必须先执行锁定依赖解析" >&2
    exit 1
  fi
  PUB_GET_ARGS=(--enforce-lockfile)
  case "${CITIZENAPP_OFFLINE:-false}" in
    true) PUB_GET_ARGS+=(--offline) ;;
    false) ;;
    *) echo '错误: CITIZENAPP_OFFLINE只接受true或false' >&2; exit 1 ;;
  esac
  (cd "$FLUTTER_ROOT" && "$FLUTTER_BIN" pub get "${PUB_GET_ARGS[@]}")
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
# Flutter只从工程根发现这两类配置；源码真源统一放在scripts，执行期间只在本次
# 源码外工程视图短暂落盘，退出时必定清理。
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
  echo '错误: Flutter 工程根存在不受CitizenApp测试入口管理的分析或测试配置' >&2
  exit 1
fi
# CI Runner 保持原生构建锁；本机测试使用独立工作目录，不使用跨端共享锁。
if [[ "${CI:-}" == true ]]; then
  acquire_native_build_lock
fi
"$SCRIPT_DIR/../../../TATA/tatachatsdk/scripts/build-native.sh" host
"$FLUTTER_BIN" analyze --no-pub
"$FLUTTER_BIN" test --no-pub --concurrency=1 "$@"
