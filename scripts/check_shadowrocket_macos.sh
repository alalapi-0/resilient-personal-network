#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于检查 Mac 端 Shadowrocket 分流配置是否包含 AI 工作流必需域名。
# 运行位置：在你的本机仓库根目录运行。

CONFIG_FILE="${CONFIG_FILE:-configs/client/shadowrocket-macos.conf}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=lib/check_ai_workflow_domains.sh
source "$SCRIPT_DIR/lib/check_ai_workflow_domains.sh"

echo "== shadowrocket macos config =="
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[error] 找不到配置文件：$CONFIG_FILE"
  echo "请先运行 scripts/generate_shadowrocket_macos_config.sh 生成配置"
  exit 1
fi

if grep -qF '${' "$CONFIG_FILE"; then
  echo "[error] 配置文件仍有未替换占位符"
  exit 1
else
  echo "[ok] 未发现未替换占位符"
fi

echo
check_shadowrocket_ai_workflow_domains "$CONFIG_FILE"

echo
echo "[done] shadowrocket macos check finished"
