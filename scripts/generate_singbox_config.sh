#!/usr/bin/env bash
set -euo pipefail

# 从本地 Xray 服务端镜像和受版本控制模板生成 sing-box 配置。
# 生成过程使用同目录临时文件，校验通过后再原子替换目标文件。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
umask 077

SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"
TEMPLATE_FILE="${TEMPLATE_FILE:-templates/singbox_client_template.json}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/singbox.json}"
NODE_HOST="${NODE_HOST:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
SINGBOX_LOG_LEVEL="${SINGBOX_LOG_LEVEL:-info}"
SINGBOX_MIXED_PORT="${SINGBOX_MIXED_PORT:-2080}"
SINGBOX_MODE="${SINGBOX_MODE:-tun}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"

if [ -z "$NODE_HOST" ]; then
  echo "[error] 缺少 NODE_HOST"
  exit 1
fi

if [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
  echo "[error] 缺少 XRAY_REALITY_PUBLIC_KEY"
  exit 1
fi

if [ ! -f "$SERVER_CONFIG" ]; then
  echo "[error] 找不到服务端配置文件"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "[error] 找不到 sing-box 占位模板"
  exit 1
fi

for command_name in jq python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[error] 缺少生成所需命令：$command_name"
    exit 1
  fi
done

if [ "$SINGBOX_MODE" != "tun" ] && [ "$SINGBOX_MODE" != "mixed" ]; then
  echo "[error] SINGBOX_MODE 只能是 tun 或 mixed"
  exit 1
fi

if ! printf '%s' "$SINGBOX_MIXED_PORT" | grep -Eq '^[0-9]+$' \
  || [ "$SINGBOX_MIXED_PORT" -lt 1 ] \
  || [ "$SINGBOX_MIXED_PORT" -gt 65535 ]; then
  echo "[error] SINGBOX_MIXED_PORT 必须是 1 到 65535 的数字"
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

case "$SINGBOX_LOG_LEVEL" in
  trace|debug|info|warn|error|fatal|panic) ;;
  *)
    echo "[error] SINGBOX_LOG_LEVEL 不在允许列表"
    exit 1
    ;;
esac

case "$CLIENT_FINGERPRINT" in
  chrome|firefox|safari|ios|android|edge|random|randomized) ;;
  *)
    echo "[error] CLIENT_FINGERPRINT 不在允许列表"
    exit 1
    ;;
esac

echo "[info] validating server config..."
bash "$SCRIPT_DIR/validate_xray_config.sh" "$SERVER_CONFIG" >/dev/null

NODE_PORT="$(jq -r '.inbounds[0].port' "$SERVER_CONFIG")"
XRAY_UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$SERVER_CONFIG")"
XRAY_FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow' "$SERVER_CONFIG")"
XRAY_SERVER_NAME="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$SERVER_CONFIG")"
XRAY_REALITY_SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$SERVER_CONFIG")"

for field_name in \
  NODE_HOST \
  NODE_PORT \
  XRAY_UUID \
  XRAY_FLOW \
  XRAY_SERVER_NAME \
  CLIENT_FINGERPRINT \
  XRAY_REALITY_PUBLIC_KEY \
  XRAY_REALITY_SHORT_ID \
  SINGBOX_LOG_LEVEL; do
  field_value="${!field_name}"
  if [ -z "$field_value" ]; then
    echo "[error] $field_name 不能为空"
    exit 1
  fi
  if [[ "$field_value" == *$'\n'* || "$field_value" == *$'\r'* ]]; then
    echo "[error] $field_name 必须是单行值"
    exit 1
  fi
done

mkdir -p "$(dirname "$OUTPUT_FILE")"
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
OUTPUT_BASENAME="$(basename "$OUTPUT_FILE")"
OUTPUT_TMP_FILE="$(mktemp "$OUTPUT_DIR/.${OUTPUT_BASENAME}.tmp.XXXXXX")"

cleanup() {
  rm -f "$OUTPUT_TMP_FILE"
}
trap cleanup EXIT

export NODE_HOST
export NODE_PORT
export XRAY_UUID
export XRAY_FLOW
export XRAY_SERVER_NAME
export CLIENT_FINGERPRINT
export XRAY_REALITY_PUBLIC_KEY
export XRAY_REALITY_SHORT_ID
export SINGBOX_LOG_LEVEL
export SINGBOX_MIXED_PORT
export SINGBOX_MODE

python3 - "$TEMPLATE_FILE" "$OUTPUT_TMP_FILE" 2>/dev/null <<'PY'
from pathlib import Path
import json
import os
import re
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
string_names = [
    "SINGBOX_LOG_LEVEL",
    "NODE_HOST",
    "XRAY_UUID",
    "XRAY_FLOW",
    "XRAY_SERVER_NAME",
    "CLIENT_FINGERPRINT",
    "XRAY_REALITY_PUBLIC_KEY",
    "XRAY_REALITY_SHORT_ID",
]
number_names = ["NODE_PORT"]
expected_names = set(string_names + number_names)

content = template_path.read_text(encoding="utf-8")
present_names = set(re.findall(r"\$\{([A-Z0-9_]+)\}", content))
if present_names != expected_names:
    print("[error] sing-box 模板占位符集合不符合要求")
    raise SystemExit(1)

for name in string_names:
    escaped = json.dumps(os.environ[name], ensure_ascii=False)[1:-1]
    content = content.replace("${" + name + "}", escaped)
for name in number_names:
    content = content.replace("${" + name + "}", str(int(os.environ[name])))

if "${" in content:
    print("[error] sing-box 配置仍有未替换占位符")
    raise SystemExit(1)

data = json.loads(content)
vless_nodes = [
    item for item in data.get("outbounds", []) if item.get("type") == "vless"
]
if len(vless_nodes) != 1:
    print("[error] sing-box 模板必须包含一个 VLESS 节点")
    raise SystemExit(1)

dns = data.get("dns", {})
dns_servers = dns.get("servers", [])
if any("address" in server for server in dns_servers):
    print("[error] sing-box 模板仍使用旧 DNS address 字段")
    raise SystemExit(1)
if any("outbound" in rule for rule in dns.get("rules", [])):
    print("[error] sing-box 模板仍使用旧 DNS outbound 规则")
    raise SystemExit(1)
if any(not server.get("type") for server in dns_servers):
    print("[error] sing-box DNS server 缺少类型")
    raise SystemExit(1)

resolver = data.get("route", {}).get("default_domain_resolver")
server_tags = {server.get("tag") for server in dns_servers}
if not resolver or resolver not in server_tags:
    print("[error] sing-box 模板缺少有效域名解析器")
    raise SystemExit(1)

if os.environ["SINGBOX_MODE"] == "mixed":
    data["inbounds"] = [
        {
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "127.0.0.1",
            "listen_port": int(os.environ["SINGBOX_MIXED_PORT"]),
        }
    ]
    for rule in data.get("route", {}).get("rules", []):
        if rule.get("inbound") == "tun-in":
            rule["inbound"] = "mixed-in"

output_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

chmod 600 "$OUTPUT_TMP_FILE"
jq empty "$OUTPUT_TMP_FILE" >/dev/null

if grep -qF '${' "$OUTPUT_TMP_FILE"; then
  echo "[error] 生成后的 sing-box 配置仍有占位符"
  exit 1
fi

mv -f "$OUTPUT_TMP_FILE" "$OUTPUT_FILE"
trap - EXIT

echo "[done] sing-box config saved to $OUTPUT_FILE"
echo "[info] sing-box mode prepared: $SINGBOX_MODE"
echo "[hint] 输出文件包含真实节点信息，不要提交、截图或公开分享"
