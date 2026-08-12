#!/usr/bin/env bash
set -euo pipefail

# 使用完全占位的隔离 fixture 测试九个客户端产物。
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

printf '[info] modern validator: '
"$SELECTED_SING_BOX_BIN" version 2>/dev/null | head -n 1

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rpn-client-generation.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
chmod 700 "$TEST_ROOT"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

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

COMMON_GENERATOR_ENV=(
  "NODE_HOST=$FIXTURE_NODE_HOST"
  "XRAY_REALITY_PUBLIC_KEY=$FIXTURE_PUBLIC_KEY"
  "CLIENT_FINGERPRINT=chrome"
  "NODE_NAME=$FIXTURE_NODE_NAME"
  "ALLOW_EXTERNAL_OUTPUT=yes"
)

CLIENT_ARTIFACT_MANIFEST_ONLY=yes source "$SCRIPT_DIR/validate_client_artifacts.sh"
for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
  IFS='|' read -r artifact_kind artifact_mode artifact_basename artifact_generator artifact_role artifact_label <<EOF
$manifest_entry
EOF
  artifact_path="$CLIENT_DIR/$artifact_basename"
  if [ "$artifact_kind" = "modern" ] && [ "$artifact_mode" = "tun" ] && [ -z "${SINGBOX_CONFIG:-}" ]; then
    SINGBOX_CONFIG="$artifact_path"
  elif [ "$artifact_kind" = "modern" ] && [ "$artifact_mode" = "mixed" ]; then
    MACOS_SINGBOX_MIXED_CONFIG="$artifact_path"
  elif [ "$artifact_kind" = "legacy" ]; then
    IOS_LEGACY_SINGBOX_CONFIG="$artifact_path"
  elif [ "$artifact_kind" = "link" ]; then
    ANDROID_V2RAYNG_LINK_FILE="$artifact_path"
  fi
  case "$artifact_generator" in
    singbox)
      env "${COMMON_GENERATOR_ENV[@]}" SERVER_CONFIG="$SERVER_FIXTURE" \
        OUTPUT_FILE="$artifact_path" SINGBOX_MODE="$artifact_mode" \
        SINGBOX_DNS_STYLE="$artifact_kind" bash "$SCRIPT_DIR/generate_singbox_config.sh" >/dev/null
      ;;
    link)
      env "${COMMON_GENERATOR_ENV[@]}" CONFIG_FILE="$SERVER_FIXTURE" \
        OUTPUT_FILE="$artifact_path" bash "$SCRIPT_DIR/generate_shadowrocket_link.sh" >/dev/null
      ;;
    shadowrocket)
      env "${COMMON_GENERATOR_ENV[@]}" CONFIG_FILE="$SERVER_FIXTURE" \
        OUTPUT_FILE="$artifact_path" bash "$SCRIPT_DIR/generate_shadowrocket_config.sh" >/dev/null
      ;;
    shadowrocket-macos)
      env "${COMMON_GENERATOR_ENV[@]}" CONFIG_FILE="$SERVER_FIXTURE" \
        OUTPUT_FILE="$artifact_path" bash "$SCRIPT_DIR/generate_shadowrocket_macos_config.sh" >/dev/null
      ;;
    *) echo "[error] fixture 清单生成器无效"; exit 1 ;;
  esac
done

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

RENDERED_LEGACY_TEMPLATE="$TEST_ROOT/rendered-singbox-ios-legacy-template.json"
python3 - \
  "$REPO_ROOT/templates/singbox_client_ios_legacy_1.11.4_template.json" \
  "$RENDERED_LEGACY_TEMPLATE" \
  "$IOS_LEGACY_SINGBOX_CONFIG" <<'PY'
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

if any(server.get("type") for server in data["dns"]["servers"]):
    raise SystemExit("[error] iOS legacy 模板不得使用 typed DNS server")
if any(not server.get("address") for server in data["dns"]["servers"]):
    raise SystemExit("[error] iOS legacy 模板缺少 DNS address")
if data.get("route", {}).get("default_domain_resolver"):
    raise SystemExit("[error] iOS legacy 模板不得包含 default_domain_resolver")
if not any(
    rule.get("outbound") == "any" and rule.get("server")
    for rule in data["dns"].get("rules", [])
):
    raise SystemExit("[error] iOS legacy 模板缺少 outbound DNS 规则")
with Path(sys.argv[3]).open("r", encoding="utf-8") as generated_file:
    if data != json.load(generated_file):
        raise SystemExit("[error] iOS legacy 模板与生成器结构不一致")
Path(sys.argv[2]).write_text(content, encoding="utf-8")
PY
chmod 600 "$RENDERED_LEGACY_TEMPLATE"
echo "[info] 证据声明：未执行 1.11.4 sing-box check（本机无该版本二进制）"

validate_fixture() {
  env \
    SING_BOX_BIN="$SELECTED_SING_BOX_BIN" \
    SERVER_CONFIG="$SERVER_FIXTURE" \
    CLIENT_OUTPUT_DIR="$CLIENT_DIR" \
    CHECK_GIT_STATE=no \
    STRICT_ARTIFACT_SET=yes \
    "$@" bash "$SCRIPT_DIR/validate_client_artifacts.sh"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[error] 失败用例未被拒绝：$label"
    exit 1
  fi
  echo "[ok] 失败用例已拒绝：$label"
}

validate_fixture >/dev/null

ORIGINAL_MANIFEST=("${CLIENT_ARTIFACT_MANIFEST[@]}")
FIRST_MANIFEST_ENTRY=""
for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
  FIRST_MANIFEST_ENTRY="$manifest_entry"
  break
done
CLIENT_ARTIFACT_MANIFEST+=("$FIRST_MANIFEST_ENTRY")
expect_failure "重复清单定义" validate_client_artifact_manifest_definition
CLIENT_ARTIFACT_MANIFEST=("${ORIGINAL_MANIFEST[@]}")

expect_failure "无效 DNS style" env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" OUTPUT_FILE="$TEST_ROOT/invalid-style.json" \
  SINGBOX_DNS_STYLE=invalid bash "$SCRIPT_DIR/generate_singbox_config.sh"
expect_failure "仓库外输出缺少 fixture 授权" env \
  NODE_HOST="$FIXTURE_NODE_HOST" XRAY_REALITY_PUBLIC_KEY="$FIXTURE_PUBLIC_KEY" \
  CLIENT_FINGERPRINT=chrome NODE_NAME="$FIXTURE_NODE_NAME" \
  SERVER_CONFIG="$SERVER_FIXTURE" OUTPUT_FILE="$TEST_ROOT/external-default.json" \
  SINGBOX_DNS_STYLE=modern SINGBOX_MODE=tun bash "$SCRIPT_DIR/generate_singbox_config.sh"
expect_failure "legacy mixed 组合" env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" OUTPUT_FILE="$TEST_ROOT/legacy-mixed.json" \
  SINGBOX_DNS_STYLE=legacy SINGBOX_MODE=mixed bash "$SCRIPT_DIR/generate_singbox_config.sh"

SAFE_SYMLINK_TARGET="$TEST_ROOT/symlink-target.json"
SAFE_SYMLINK_OUTPUT="$TEST_ROOT/symlink-output.json"
: > "$SAFE_SYMLINK_TARGET"
chmod 600 "$SAFE_SYMLINK_TARGET"
ln -s "$SAFE_SYMLINK_TARGET" "$SAFE_SYMLINK_OUTPUT"
expect_failure "符号链接输出目标" env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" OUTPUT_FILE="$SAFE_SYMLINK_OUTPUT" \
  SINGBOX_DNS_STYLE=modern SINGBOX_MODE=tun bash "$SCRIPT_DIR/generate_singbox_config.sh"

mkdir -m 700 "$TEST_ROOT/real-output-parent"
ln -s "$TEST_ROOT/real-output-parent" "$TEST_ROOT/symlink-output-parent"
expect_failure "祖先目录符号链接" env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" OUTPUT_FILE="$TEST_ROOT/symlink-output-parent/config.json" \
  SINGBOX_DNS_STYLE=modern SINGBOX_MODE=tun bash "$SCRIPT_DIR/generate_singbox_config.sh"

ln -s "$TEST_ROOT/does-not-exist" "$TEST_ROOT/dangling-output.json"
expect_failure "悬空符号链接输出" env "${COMMON_GENERATOR_ENV[@]}" \
  SERVER_CONFIG="$SERVER_FIXTURE" OUTPUT_FILE="$TEST_ROOT/dangling-output.json" \
  SINGBOX_DNS_STYLE=modern SINGBOX_MODE=tun bash "$SCRIPT_DIR/generate_singbox_config.sh"

MISINDEXED_DIR="$TEST_ROOT/misindexed-client"
mkdir -m 700 "$MISINDEXED_DIR"
for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
  IFS='|' read -r _ _ artifact_basename _ _ _ <<EOF
$manifest_entry
EOF
  install -m 600 "$CLIENT_DIR/$artifact_basename" "$MISINDEXED_DIR/$artifact_basename"
done
install -m 600 "$MACOS_SINGBOX_MIXED_CONFIG" "$MISINDEXED_DIR/singbox.json"
install -m 600 "$SINGBOX_CONFIG" "$MISINDEXED_DIR/macos_singbox_mixed.json"
expect_failure "产物索引错位" validate_fixture CLIENT_OUTPUT_DIR="$MISINDEXED_DIR"

chmod 644 "$IOS_LEGACY_SINGBOX_CONFIG"
expect_failure "不安全文件权限" validate_fixture
chmod 600 "$IOS_LEGACY_SINGBOX_CONFIG"

mv "$ANDROID_V2RAYNG_LINK_FILE" "$ANDROID_V2RAYNG_LINK_FILE.missing"
expect_failure "缺失产物" validate_fixture
mv "$ANDROID_V2RAYNG_LINK_FILE.missing" "$ANDROID_V2RAYNG_LINK_FILE"

install -m 600 "$SINGBOX_CONFIG" "$CLIENT_DIR/unexpected.json"
expect_failure "额外产物" validate_fixture
unlink "$CLIENT_DIR/unexpected.json"

TRANSACTION_SUFFIX=".previous.12345"
install -m 600 "$SINGBOX_CONFIG" "$CLIENT_DIR/.singbox.json$TRANSACTION_SUFFIX"
validate_fixture TRANSACTION_BACKUP_SUFFIX="$TRANSACTION_SUFFIX" >/dev/null
expect_failure "事务备份默认仍视为额外产物" validate_fixture

echo "[ok] 占位 fixture 的九个客户端产物通过生成与兼容性校验"
echo "[done] client generation fixture test passed"
