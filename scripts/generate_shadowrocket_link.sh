#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于从本地服务端配置生成 Shadowrocket 导入链接。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 生成的真实链接写入 configs/client/shadowrocket_link.txt；
# 2) 该文件已被 .gitignore 忽略，不应提交到 Git；
# 3) 脚本默认不把完整链接打印到终端，避免录屏或截图泄露；
# 4) 客户端只需要 REALITY 公钥，不需要私钥。

CONFIG_FILE="${CONFIG_FILE:-configs/server/config.json}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/shadowrocket_link.txt}"
NODE_HOST="${NODE_HOST:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
NODE_NAME="${NODE_NAME:-jp-tokyo-01}"

# 必要参数检查。
if [ -z "$NODE_HOST" ]; then
  echo "[error] 缺少 NODE_HOST，请传入 VPS IP 或域名"
  echo "示例：NODE_HOST=\"<你的_VPS_IP>\" XRAY_REALITY_PUBLIC_KEY=\"<公钥>\" bash scripts/generate_shadowrocket_link.sh"
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

# 先校验服务端配置，避免从坏配置中生成客户端链接。
echo "[info] validating server config..."
bash scripts/validate_xray_config.sh "$CONFIG_FILE" >/dev/null

# 从服务端配置中读取客户端必需字段。
NODE_PORT="$(jq -r '.inbounds[0].port' "$CONFIG_FILE")"
XRAY_UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")"
XRAY_FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow' "$CONFIG_FILE")"
XRAY_SERVER_NAME="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")"
XRAY_REALITY_SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")"

# 使用 jq 做 URL 编码，避免节点名或参数里出现特殊字符导致导入失败。
url_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

ENC_FLOW="$(url_encode "$XRAY_FLOW")"
ENC_SERVER_NAME="$(url_encode "$XRAY_SERVER_NAME")"
ENC_FINGERPRINT="$(url_encode "$CLIENT_FINGERPRINT")"
ENC_PUBLIC_KEY="$(url_encode "$XRAY_REALITY_PUBLIC_KEY")"
ENC_NODE_NAME="$(url_encode "$NODE_NAME")"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# 写入 Shadowrocket / 通用 VLESS 导入链接。
{
  echo "vless://${XRAY_UUID}@${NODE_HOST}:${NODE_PORT}?encryption=none&flow=${ENC_FLOW}&security=reality&sni=${ENC_SERVER_NAME}&fp=${ENC_FINGERPRINT}&pbk=${ENC_PUBLIC_KEY}&sid=${XRAY_REALITY_SHORT_ID}&type=tcp&headerType=none#${ENC_NODE_NAME}"
} > "$OUTPUT_FILE"

chmod 600 "$OUTPUT_FILE"

echo "[done] shadowrocket link saved to $OUTPUT_FILE"
echo "[hint] 该文件包含真实节点信息，不要提交、截图或公开分享"
