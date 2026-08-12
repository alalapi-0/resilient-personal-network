#!/usr/bin/env bash
set -euo pipefail

# 从本地 Xray 服务端镜像和受版本控制模板生成 sing-box 配置。
# 生成过程使用同目录临时文件，校验通过后再原子替换目标文件。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
umask 077

SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"
SINGBOX_DNS_STYLE="${SINGBOX_DNS_STYLE:-modern}"
NODE_HOST="${NODE_HOST:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
SINGBOX_LOG_LEVEL="${SINGBOX_LOG_LEVEL:-info}"
SINGBOX_MIXED_PORT="${SINGBOX_MIXED_PORT:-2080}"
SINGBOX_MODE="${SINGBOX_MODE:-tun}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
ALLOW_EXTERNAL_OUTPUT="${ALLOW_EXTERNAL_OUTPUT:-no}"

if [ "$ALLOW_EXTERNAL_OUTPUT" != "yes" ] && [ "$ALLOW_EXTERNAL_OUTPUT" != "no" ]; then
  echo "[error] ALLOW_EXTERNAL_OUTPUT 只能是 yes 或 no"
  exit 1
fi

if [ "$SINGBOX_DNS_STYLE" != "modern" ] && [ "$SINGBOX_DNS_STYLE" != "legacy" ]; then
  echo "[error] SINGBOX_DNS_STYLE 只能是 modern 或 legacy"
  exit 1
fi

if [ "$SINGBOX_DNS_STYLE" = "legacy" ]; then
  TEMPLATE_FILE="${TEMPLATE_FILE:-templates/singbox_client_ios_legacy_1.11.4_template.json}"
  OUTPUT_FILE="${OUTPUT_FILE:-configs/client/singbox-ios-legacy-1.11.4.json}"
else
  TEMPLATE_FILE="${TEMPLATE_FILE:-templates/singbox_client_template.json}"
  OUTPUT_FILE="${OUTPUT_FILE:-configs/client/singbox.json}"
fi

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

python3 - "$REPO_ROOT" "$SERVER_CONFIG" "$TEMPLATE_FILE" "$OUTPUT_FILE" "$ALLOW_EXTERNAL_OUTPUT" <<'PY'
from pathlib import Path
import os
import stat
import sys

root = Path(sys.argv[1]).resolve()
server = Path(sys.argv[2])
template = Path(sys.argv[3])
output = Path(sys.argv[4])
allow_external = sys.argv[5] == "yes"

def absolute_path(path):
    return path if path.is_absolute() else Path.cwd() / path

def has_symlink_component(path):
    path = absolute_path(path).absolute()
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current = current / part
        if os.path.lexists(current) and stat.S_ISLNK(os.lstat(current).st_mode):
            return True
    return False

if not str(output).strip() or output.name in {"", ".", ".."}:
    raise SystemExit("[error] 输出路径为空或含糊")
if has_symlink_component(server) or has_symlink_component(template) or has_symlink_component(output):
    raise SystemExit("[error] 输入或输出路径不得包含符号链接")
if not server.is_file() or not template.is_file():
    raise SystemExit("[error] 输入文件必须是普通文件")
if template.resolve().parent != (root / "templates").resolve():
    raise SystemExit("[error] 模板必须位于仓库 templates 目录")

parent = output.parent
if not parent.is_dir():
    raise SystemExit("[error] 输出目录必须预先存在且不得是符号链接")
output_real = parent.resolve() / output.name
if output.exists() and (output.is_symlink() or not output.is_file()):
    raise SystemExit("[error] 输出目标必须是普通文件且不得是符号链接")
try:
    relative = output_real.relative_to(root)
except ValueError:
    relative = None
if relative is None and not allow_external:
    raise SystemExit("[error] 仓库外输出默认禁止")
if relative is not None and relative.parts[:2] != ("configs", "client"):
    raise SystemExit("[error] 仓库内输出仅允许写入 configs/client")
PY

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

if [ "$SINGBOX_DNS_STYLE" = "legacy" ] && [ "$SINGBOX_MODE" != "tun" ]; then
  echo "[error] iOS legacy 1.11.4 产物仅支持 SINGBOX_MODE=tun"
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

OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
OUTPUT_BASENAME="$(basename "$OUTPUT_FILE")"
OUTPUT_TMP_FILE="$(mktemp "$OUTPUT_DIR/.${OUTPUT_BASENAME}.tmp.XXXXXX")"

cleanup() {
  rm -f "$OUTPUT_TMP_FILE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

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
export SINGBOX_DNS_STYLE

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
dns_style = os.environ["SINGBOX_DNS_STYLE"]

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
dns_rules = dns.get("rules", [])
route = data.get("route", {})
server_tags = {server.get("tag") for server in dns_servers}

if dns_style == "legacy":
    if any(server.get("type") for server in dns_servers):
        print("[error] legacy sing-box 模板不得使用 typed DNS server")
        raise SystemExit(1)
    if any(not server.get("address") for server in dns_servers):
        print("[error] legacy sing-box DNS server 缺少 address")
        raise SystemExit(1)
    if not any(
        rule.get("outbound") == "any" and rule.get("server") in server_tags
        for rule in dns_rules
    ):
        print("[error] legacy sing-box 模板缺少 outbound DNS 规则")
        raise SystemExit(1)
    if route.get("default_domain_resolver"):
        print("[error] legacy sing-box 模板不得包含 default_domain_resolver")
        raise SystemExit(1)
else:
    if any("address" in server for server in dns_servers):
        print("[error] sing-box 模板仍使用旧 DNS address 字段")
        raise SystemExit(1)
    if any("outbound" in rule for rule in dns_rules):
        print("[error] sing-box 模板仍使用旧 DNS outbound 规则")
        raise SystemExit(1)
    if any(not server.get("type") for server in dns_servers):
        print("[error] sing-box DNS server 缺少类型")
        raise SystemExit(1)

    resolver = route.get("default_domain_resolver")
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
trap - EXIT INT TERM HUP

echo "[done] sing-box config saved to $OUTPUT_FILE"
echo "[info] sing-box mode prepared: $SINGBOX_MODE"
echo "[info] sing-box DNS style: $SINGBOX_DNS_STYLE"
echo "[hint] 输出文件包含真实节点信息，不要提交、截图或公开分享"
