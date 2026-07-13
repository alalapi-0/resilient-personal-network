#!/usr/bin/env bash
set -euo pipefail

# 使用 macOS 专用占位模板，复用统一 Shadowrocket 原子生成器。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TEMPLATE_FILE="${TEMPLATE_FILE:-templates/shadowrocket_macos_ai_workflow.conf.template}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/shadowrocket-macos.conf}"

export TEMPLATE_FILE
export OUTPUT_FILE

exec bash "$SCRIPT_DIR/generate_shadowrocket_config.sh"
