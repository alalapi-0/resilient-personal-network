#!/usr/bin/env bash
set -euo pipefail

# 从本地服务端镜像和占位模板生成 Shadowrocket 完整配置。
# 只写入调用方指定的本地文件，不连接客户端、不修改系统代理。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
umask 077

CONFIG_FILE="${CONFIG_FILE:-configs/server/config.json}"
TEMPLATE_FILE="${TEMPLATE_FILE:-templates/shadowrocket_client.conf.template}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/shadowrocket.conf}"
NODE_HOST="${NODE_HOST:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
NODE_NAME="${NODE_NAME:-jp-tokyo-01}"

if [ -z "$NODE_HOST" ]; then
  echo "[error] 缺少 NODE_HOST"
  exit 1
fi

if [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
  echo "[error] 缺少 XRAY_REALITY_PUBLIC_KEY"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[error] 找不到服务端配置文件"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "[error] 找不到 Shadowrocket 占位模板"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[error] 缺少 python3，无法安全渲染配置"
  exit 1
fi

if ! printf '%s' "$XRAY_REALITY_PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9_-]{20,}$'; then
  echo "[error] XRAY_REALITY_PUBLIC_KEY 格式异常"
  exit 1
fi

if [[ "$NODE_HOST" =~ [[:space:]] ]] \
  || [[ "$NODE_HOST" == *"@"* || "$NODE_HOST" == *"/"* || "$NODE_HOST" == *"?"* || "$NODE_HOST" == *"#"* ]]; then
  echo "[error] NODE_HOST 格式异常"
  exit 1
fi

case "$CLIENT_FINGERPRINT" in
  chrome|firefox|safari|ios|android|edge|random|randomized) ;;
  *)
    echo "[error] CLIENT_FINGERPRINT 不在允许列表"
    exit 1
    ;;
esac

echo "[info] validating server config..."
bash "$SCRIPT_DIR/validate_xray_config.sh" "$CONFIG_FILE" >/dev/null

NODE_PORT="$(jq -r '.inbounds[0].port' "$CONFIG_FILE")"
XRAY_UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")"
XRAY_FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow' "$CONFIG_FILE")"
XRAY_SERVER_NAME="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")"
XRAY_REALITY_SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")"

for field_name in \
  NODE_NAME \
  NODE_HOST \
  NODE_PORT \
  XRAY_UUID \
  XRAY_FLOW \
  XRAY_SERVER_NAME \
  CLIENT_FINGERPRINT \
  XRAY_REALITY_PUBLIC_KEY \
  XRAY_REALITY_SHORT_ID; do
  field_value="${!field_name}"
  if [ -z "$field_value" ]; then
    echo "[error] $field_name 不能为空"
    exit 1
  fi
  if [[ "$field_value" == *$'\n'* || "$field_value" == *$'\r'* || "$field_value" == *","* ]]; then
    echo "[error] $field_name 包含不允许的配置分隔符"
    exit 1
  fi
done

if [[ "$NODE_NAME" == *"#"* || "$NODE_NAME" == *";"* || "$NODE_NAME" == *"="* ]]; then
  echo "[error] NODE_NAME 包含不允许的配置语法字符"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
OUTPUT_BASENAME="$(basename "$OUTPUT_FILE")"
OUTPUT_TMP_FILE="$(mktemp "$OUTPUT_DIR/.${OUTPUT_BASENAME}.tmp.XXXXXX")"

cleanup() {
  rm -f "$OUTPUT_TMP_FILE"
}
trap cleanup EXIT

export NODE_NAME
export NODE_HOST
export NODE_PORT
export XRAY_UUID
export XRAY_FLOW
export XRAY_SERVER_NAME
export CLIENT_FINGERPRINT
export XRAY_REALITY_PUBLIC_KEY
export XRAY_REALITY_SHORT_ID

python3 - "$TEMPLATE_FILE" "$OUTPUT_TMP_FILE" <<'PY'
from pathlib import Path
import os
import re
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
names = [
    "NODE_NAME",
    "NODE_HOST",
    "NODE_PORT",
    "XRAY_UUID",
    "XRAY_FLOW",
    "XRAY_SERVER_NAME",
    "CLIENT_FINGERPRINT",
    "XRAY_REALITY_PUBLIC_KEY",
    "XRAY_REALITY_SHORT_ID",
]

content = template_path.read_text(encoding="utf-8")
present = set(re.findall(r"\$\{([A-Z0-9_]+)\}", content))
missing = [name for name in names if name not in present]
unknown = sorted(present.difference(names))
if missing or unknown:
    if missing:
        print("[error] Shadowrocket 模板缺少必需占位符")
    if unknown:
        print("[error] Shadowrocket 模板包含未知占位符")
    raise SystemExit(1)

for name in names:
    content = content.replace("${" + name + "}", os.environ[name])

if "${" in content:
    print("[error] Shadowrocket 配置仍有未替换占位符")
    raise SystemExit(1)

output_path.write_text(content, encoding="utf-8")
PY

chmod 600 "$OUTPUT_TMP_FILE"

if grep -qF '${' "$OUTPUT_TMP_FILE"; then
  echo "[error] 生成后的 Shadowrocket 配置仍有占位符"
  exit 1
fi

if ! grep -Eq '^[^#;].* = vless, ' "$OUTPUT_TMP_FILE"; then
  echo "[error] 生成后的 Shadowrocket 配置缺少 VLESS 节点"
  exit 1
fi

mv -f "$OUTPUT_TMP_FILE" "$OUTPUT_FILE"
trap - EXIT

echo "[done] Shadowrocket config saved to $OUTPUT_FILE"
echo "[hint] 输出文件包含真实节点信息，不要提交、截图或公开分享"
