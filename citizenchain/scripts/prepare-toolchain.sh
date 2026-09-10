#!/usr/bin/env bash
# 公民链产品工具准备：使用调用环境中的标准工具，不依赖或校验 TataConsole。
# 必须由 run.sh source，使产品路径和包管理器设置留在当前进程。
set -euo pipefail

PREPARE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMB_REPOSITORY_ROOT="$(cd "$PREPARE_SCRIPT_DIR/../.." && pwd)"
NODE_FRONTEND_PROJECT="$GMB_REPOSITORY_ROOT/citizenchain/node/frontend"
ONCHINA_FRONTEND_PROJECT="$GMB_REPOSITORY_ROOT/citizenchain/onchina/frontend"

if [[ -n "${TATA_CONSOLE_DEPENDENCY_CACHE_DIR:-}" ]]; then
  export npm_config_cache="$TATA_CONSOLE_DEPENDENCY_CACHE_DIR/npm"
  mkdir -p "$npm_config_cache"
fi
export npm_config_audit=false npm_config_fund=false

for project in \
  "$GMB_REPOSITORY_ROOT/citizenchain/crates/scanner-react" \
  "$NODE_FRONTEND_PROJECT" \
  "$ONCHINA_FRONTEND_PROJECT"; do
  echo "==> 准备产品依赖：${project#"$GMB_REPOSITORY_ROOT/"}"
  (cd "$project" && npm ci --no-audit --no-fund)
done

echo '==> 公民链产品工具和依赖已就绪'
