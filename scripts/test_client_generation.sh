#!/usr/bin/env bash
set -euo pipefail

# 使用完全占位的隔离 fixture 测试八个客户端产物。
# 不读取或覆盖 configs/ 下的真实运行时文件。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
umask 077

for command_name in jq python3 mktemp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[error] fixture 测试缺少必需命令：$command_name"
    exit 1
  fi
done

if [ -n "${SING_BOX_BIN:-}" ]; then
  SELECTED_SING_BOX_BIN="$SING_BOX_BIN"
elif command -v sing-box >/dev/null 2>&1; then
  SELECTED_SING_BOX_BIN="$(command -v sing-box)"
else
  SELECTED_SING_BOX_BIN="$REPO_ROOT/tools/sing-box/sing-box"
fi

if [ ! -x "$SELECTED_SING_BOX_BIN" ]; then
  echo "[error] fixture 测试找不到可执行的 sing-box"
  exit 1
fi

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rpn-client-generation.XXXXXX")"
chmod 700 "$TEST_ROOT"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

SERVER_FIXTURE="$TEST_ROOT/server.json"
CLIENT_DIR="$TEST_ROOT/client"
mkdir -p "$CLIENT_DIR"
chmod 700 "$CLIENT_DIR"

FIXTURE_UUID="00000000-0000-4000-8000-$(printf '%012d' 1)"
printf -v FIXTURE_PRIVATE_KEY '%*s' 43 ''
FIXTURE_PRIVATE_KEY="${FIXTURE_PRIVATE_KEY// /B}"
printf -v FIXTURE_PUBLIC_KEY '%*s' 43 ''
FIXTURE_PUBLIC_KEY="${FIXTURE_PUBLIC_KEY// /A}"
printf -v FIXTURE_SHORT_ID '%*s' 16 ''
FIXTURE_SHORT_ID="${FIXTURE_SHORT_ID// /0}"
FIXTURE_NODE_HOST="fixture.example"
FIXTURE_SERVER_NAME="www.example.com"
FIXTURE_NODE_NAME="fixture-node"

jq -n \
  --arg uuid "$FIXTURE_UUID" \
  --arg private_key "$FIXTURE_PRIVATE_KEY" \
  --arg short_id "$FIXTURE_SHORT_ID" \
  --arg server_name "$FIXTURE_SERVER_NAME" \
  '{
    log: {loglevel: "warning"},
    inbounds: [
      {
        port: 443,
        protocol: "vless",
        settings: {
          clients: [
            {
              id: $uuid,
              flow: "xtls-rprx-vision",
              email: "fixture-client"
            }
          ],
          decryption: "none"
        },
        streamSettings: {
          network: "tcp",
          security: "reality",
          realitySettings: {
            dest: ($server_name + ":443"),
            serverNames: [$server_name],
            privateKey: $private_key,
            shortIds: [$short_id]
          }
        }
      }
    ]
  }' > "$SERVER_FIXTURE"
chmod 600 "$SERVER_FIXTURE"

SINGBOX_CONFIG="$CLIENT_DIR/singbox.json"
MACOS_SINGBOX_CONFIG="$CLIENT_DIR/macos_singbox.json"
MACOS_SINGBOX_MIXED_CONFIG="$CLIENT_DIR/macos_singbox_mixed.json"
SHADOWROCKET_LINK_FILE="$CLIENT_DIR/shadowrocket_link.txt"
IOS_SHADOWROCKET_LINK_FILE="$CLIENT_DIR/ios_shadowrocket_vless_link.txt"
ANDROID_V2RAYNG_LINK_FILE="$CLIENT_DIR/android_v2rayng_vless_link.txt"
SHADOWROCKET_CONFIG_FILE="$CLIENT_DIR/shadowrocket.conf"
SHADOWROCKET_MACOS_CONFIG_FILE="$CLIENT_DIR/shadowrocket-macos.conf"

COMMON_GENERATOR_ENV=(
  "NODE_HOST=$FIXTURE_NODE_HOST"
  "XRAY_REALITY_PUBLIC_KEY=$FIXTURE_PUBLIC_KEY"
  "CLIENT_FINGERPRINT=chrome"
  "NODE_NAME=$FIXTURE_NODE_NAME"
)

env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" \
  OUTPUT_FILE="$SINGBOX_CONFIG" \
  SINGBOX_MODE=tun \
  bash "$SCRIPT_DIR/generate_singbox_config.sh" >/dev/null

env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" \
  OUTPUT_FILE="$MACOS_SINGBOX_CONFIG" \
  SINGBOX_MODE=tun \
  bash "$SCRIPT_DIR/generate_singbox_config.sh" >/dev/null

env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" \
  OUTPUT_FILE="$MACOS_SINGBOX_MIXED_CONFIG" \
  SINGBOX_MODE=mixed \
  bash "$SCRIPT_DIR/generate_singbox_config.sh" >/dev/null

env "${COMMON_GENERATOR_ENV[@]}" \
  CONFIG_FILE="$SERVER_FIXTURE" \
  OUTPUT_FILE="$SHADOWROCKET_LINK_FILE" \
  bash "$SCRIPT_DIR/generate_shadowrocket_link.sh" >/dev/null

install -m 600 "$SHADOWROCKET_LINK_FILE" "$IOS_SHADOWROCKET_LINK_FILE"
install -m 600 "$SHADOWROCKET_LINK_FILE" "$ANDROID_V2RAYNG_LINK_FILE"

env "${COMMON_GENERATOR_ENV[@]}" \
  CONFIG_FILE="$SERVER_FIXTURE" \
  OUTPUT_FILE="$SHADOWROCKET_CONFIG_FILE" \
  bash "$SCRIPT_DIR/generate_shadowrocket_config.sh" >/dev/null

env "${COMMON_GENERATOR_ENV[@]}" \
  CONFIG_FILE="$SERVER_FIXTURE" \
  OUTPUT_FILE="$SHADOWROCKET_MACOS_CONFIG_FILE" \
  bash "$SCRIPT_DIR/generate_shadowrocket_macos_config.sh" >/dev/null

export FIXTURE_NODE_HOST
export FIXTURE_PUBLIC_KEY
export FIXTURE_UUID
export FIXTURE_SHORT_ID
export FIXTURE_SERVER_NAME
RENDERED_TEMPLATE="$TEST_ROOT/rendered-singbox-template.json"
python3 - \
  "$REPO_ROOT/templates/singbox_client_template.json" \
  "$RENDERED_TEMPLATE" \
  "$SINGBOX_CONFIG" <<'PY'
import json
import os
import sys
from pathlib import Path

content = Path(sys.argv[1]).read_text(encoding="utf-8")
replacements = {
    "SINGBOX_LOG_LEVEL": "info",
    "NODE_HOST": os.environ["FIXTURE_NODE_HOST"],
    "NODE_PORT": "443",
    "XRAY_UUID": os.environ["FIXTURE_UUID"],
    "XRAY_FLOW": "xtls-rprx-vision",
    "XRAY_SERVER_NAME": os.environ["FIXTURE_SERVER_NAME"],
    "CLIENT_FINGERPRINT": "chrome",
    "XRAY_REALITY_PUBLIC_KEY": os.environ["FIXTURE_PUBLIC_KEY"],
    "XRAY_REALITY_SHORT_ID": os.environ["FIXTURE_SHORT_ID"],
}
for name, value in replacements.items():
    content = content.replace("${" + name + "}", value)
data = json.loads(content)

if any("address" in server for server in data["dns"]["servers"]):
    raise SystemExit("[error] sing-box 模板仍使用旧 DNS address 字段")
if any("outbound" in rule for rule in data["dns"].get("rules", [])):
    raise SystemExit("[error] sing-box 模板仍使用旧 DNS outbound 规则")
resolver = data.get("route", {}).get("default_domain_resolver")
server_tags = {server.get("tag") for server in data["dns"]["servers"]}
if not resolver or resolver not in server_tags:
    raise SystemExit("[error] sing-box 模板缺少有效域名解析器")
with Path(sys.argv[3]).open("r", encoding="utf-8") as generated_file:
    if data != json.load(generated_file):
        raise SystemExit("[error] sing-box 模板与 TUN 生成器结构不一致")
Path(sys.argv[2]).write_text(content, encoding="utf-8")
PY
chmod 600 "$RENDERED_TEMPLATE"
"$SELECTED_SING_BOX_BIN" check -c "$RENDERED_TEMPLATE" >/dev/null 2>&1

SING_BOX_BIN="$SELECTED_SING_BOX_BIN" \
SERVER_CONFIG="$SERVER_FIXTURE" \
SINGBOX_CONFIG="$SINGBOX_CONFIG" \
MACOS_SINGBOX_CONFIG="$MACOS_SINGBOX_CONFIG" \
MACOS_SINGBOX_MIXED_CONFIG="$MACOS_SINGBOX_MIXED_CONFIG" \
SHADOWROCKET_LINK_FILE="$SHADOWROCKET_LINK_FILE" \
IOS_SHADOWROCKET_LINK_FILE="$IOS_SHADOWROCKET_LINK_FILE" \
ANDROID_V2RAYNG_LINK_FILE="$ANDROID_V2RAYNG_LINK_FILE" \
SHADOWROCKET_CONFIG_FILE="$SHADOWROCKET_CONFIG_FILE" \
SHADOWROCKET_MACOS_CONFIG_FILE="$SHADOWROCKET_MACOS_CONFIG_FILE" \
CHECK_GIT_STATE=no \
bash "$SCRIPT_DIR/validate_client_artifacts.sh" >/dev/null

echo "[ok] 占位 fixture 的八个客户端产物通过生成与兼容性校验"
echo "[done] client generation fixture test passed"
