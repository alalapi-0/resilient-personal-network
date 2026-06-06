#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于从本地 Xray 服务端配置生成 Shadowrocket macOS 分流配置。
# 安全原则：
# 1) 生成的真实配置写入 configs/client/shadowrocket-macos.conf；
# 2) configs/client/*.conf 已被 .gitignore 忽略，不应提交到 Git；
# 3) 脚本不打印 UUID、公钥、shortId 等真实敏感值。

CONFIG_FILE="${CONFIG_FILE:-configs/server/config.json}"
TEMPLATE_FILE="${TEMPLATE_FILE:-templates/shadowrocket_macos_ai_workflow.conf.template}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/shadowrocket-macos.conf}"
NODE_HOST="${NODE_HOST:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
NODE_NAME="${NODE_NAME:-jp-tokyo-01}"

if [ -z "$NODE_HOST" ]; then
  echo "[error] 缺少 NODE_HOST，请传入 VPS IP 或域名"
  echo "示例：NODE_HOST=\"<你的_VPS_IP>\" XRAY_REALITY_PUBLIC_KEY=\"<公钥>\" bash scripts/generate_shadowrocket_macos_config.sh"
  exit 1
fi

if [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
  echo "[error] 缺少 XRAY_REALITY_PUBLIC_KEY，请传入 xray x25519 输出中的 Public key"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[error] 找不到服务端配置：$CONFIG_FILE"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "[error] 找不到 Shadowrocket macOS 模板：$TEMPLATE_FILE"
  exit 1
fi

echo "[info] validating server config..."
bash scripts/validate_xray_config.sh "$CONFIG_FILE" >/dev/null

NODE_PORT="$(jq -r '.inbounds[0].port' "$CONFIG_FILE")"
XRAY_UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")"
XRAY_FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow' "$CONFIG_FILE")"
XRAY_SERVER_NAME="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")"
XRAY_REALITY_SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")"

mkdir -p "$(dirname "$OUTPUT_FILE")"

export NODE_NAME
export NODE_HOST
export NODE_PORT
export XRAY_UUID
export XRAY_FLOW
export XRAY_SERVER_NAME
export CLIENT_FINGERPRINT
export XRAY_REALITY_PUBLIC_KEY
export XRAY_REALITY_SHORT_ID
export TEMPLATE_FILE
export OUTPUT_FILE

python3 - <<'PY'
from pathlib import Path
import os

template_path = Path(os.environ["TEMPLATE_FILE"])
output_path = Path(os.environ["OUTPUT_FILE"])

content = template_path.read_text(encoding="utf-8")
for name in [
    "NODE_NAME",
    "NODE_HOST",
    "NODE_PORT",
    "XRAY_UUID",
    "XRAY_FLOW",
    "XRAY_SERVER_NAME",
    "CLIENT_FINGERPRINT",
    "XRAY_REALITY_PUBLIC_KEY",
    "XRAY_REALITY_SHORT_ID",
]:
    content = content.replace("${" + name + "}", os.environ[name])

output_path.write_text(content, encoding="utf-8")
PY

chmod 600 "$OUTPUT_FILE"

if grep -nF '${' "$OUTPUT_FILE" >/dev/null; then
  echo "[error] 生成后的 Shadowrocket macOS 配置仍有占位符"
  exit 1
fi

echo "[done] Shadowrocket macOS config saved to $OUTPUT_FILE"
echo "[hint] 该文件包含真实节点信息，不要提交、截图或公开分享"
