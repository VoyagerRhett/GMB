#!/usr/bin/env bash
# 公民链产品工具准备：使用调用环境中的标准工具，不依赖或校验 TataConsole。
# 必须由 run.sh source，使产品路径和包管理器设置留在当前进程。
set -euo pipefail

PREPARE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMB_REPOSITORY_ROOT="$(cd "$PREPARE_SCRIPT_DIR/../.." && pwd)"
NODE_FRONTEND_SOURCE="$GMB_REPOSITORY_ROOT/citizenchain/node/frontend"
ONCHINA_FRONTEND_SOURCE="$GMB_REPOSITORY_ROOT/citizenchain/onchina/frontend"

if [[ -n "${TATA_CONSOLE_DEPENDENCY_CACHE_DIR:-}" ]]; then
  export npm_config_cache="$TATA_CONSOLE_DEPENDENCY_CACHE_DIR/npm"
  mkdir -p "$npm_config_cache"
fi
export npm_config_audit=false npm_config_fund=false

declare -F build_prepare_node_project >/dev/null \
  || { echo '公民链Build缺少塔塔中央Node工程视图' >&2; exit 1; }

echo '==> 准备产品依赖：citizenchain/crates/scanner-react'
build_prepare_node_project "$GMB_REPOSITORY_ROOT/citizenchain/crates/scanner-react"
SCANNER_REACT_PROJECT="$BUILD_NODE_PROJECT"
echo '==> 准备产品依赖：citizenchain/node/frontend'
build_prepare_node_project "$NODE_FRONTEND_SOURCE"
NODE_FRONTEND_PROJECT="$BUILD_NODE_PROJECT"
echo '==> 准备产品依赖：citizenchain/onchina/frontend'
build_prepare_node_project "$ONCHINA_FRONTEND_SOURCE"
ONCHINA_FRONTEND_PROJECT="$BUILD_NODE_PROJECT"
export SCANNER_REACT_PROJECT NODE_FRONTEND_PROJECT ONCHINA_FRONTEND_PROJECT

echo '==> 公民链产品工具和依赖已就绪'
