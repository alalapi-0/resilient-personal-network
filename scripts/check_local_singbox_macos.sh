#!/usr/bin/env bash
set -euo pipefail

# 说明：检查 macOS 本地 sing-box CLI 备用方案是否准备好。
# 本脚本只检查二进制和配置，不启动 sing-box，不修改系统网络。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_SING_BOX_BIN="$REPO_ROOT/tools/sing-box/sing-box"
if [ -n "${SING_BOX_BIN:-}" ]; then
  SING_BOX_SOURCE="SING_BOX_BIN"
elif command -v sing-box >/dev/null 2>&1; then
  SING_BOX_BIN="$(command -v sing-box)"
  SING_BOX_SOURCE="PATH"
else
  SING_BOX_BIN="$PROJECT_SING_BOX_BIN"
  SING_BOX_SOURCE="project fallback"
fi
TUN_CONFIG="${TUN_CONFIG:-$REPO_ROOT/configs/client/macos_singbox.json}"
MIXED_CONFIG="${MIXED_CONFIG:-$REPO_ROOT/configs/client/macos_singbox_mixed.json}"

echo "== local sing-box binary =="
if [ ! -x "$SING_BOX_BIN" ]; then
  echo "[error] 找不到可执行 sing-box：$SING_BOX_BIN"
  echo "[hint] 可设置 SING_BOX_BIN=绝对路径，或将 sing-box 放入 PATH，或准备项目内 tools/sing-box/sing-box"
  exit 1
fi
echo "[info] selected from $SING_BOX_SOURCE: $SING_BOX_BIN"
"$SING_BOX_BIN" version | sed -n '1,5p'

echo
echo "== config files =="
for config_file in "$TUN_CONFIG" "$MIXED_CONFIG"; do
  if [ ! -f "$config_file" ]; then
    echo "[error] 找不到配置：$config_file"
    exit 1
  fi
  jq empty "$config_file" >/dev/null
  "$SING_BOX_BIN" check -c "$config_file" >/dev/null
  echo "[ok] $(basename "$config_file")"
done

echo
echo "== profile structure =="
if jq -e '
  .inbounds[0].type == "tun"
  and ((.route.final | type) == "string")
  and ((.route.default_domain_resolver | type) == "string")
' "$TUN_CONFIG" >/dev/null; then
  echo "[ok] TUN 配置模式、默认路由和域名解析器存在"
else
  echo "[error] TUN 配置结构异常"
  exit 1
fi
if jq -e '
  .inbounds[0].type == "mixed"
  and .inbounds[0].listen == "127.0.0.1"
  and ((.inbounds[0].listen_port | type) == "number")
  and ((.route.final | type) == "string")
  and ((.route.default_domain_resolver | type) == "string")
' "$MIXED_CONFIG" >/dev/null; then
  echo "[ok] mixed 配置监听、默认路由和域名解析器存在"
else
  echo "[error] mixed 配置结构异常"
  exit 1
fi

MIXED_PORT="$(jq -r '.inbounds[0].listen_port' "$MIXED_CONFIG")"
if ! command -v lsof >/dev/null 2>&1; then
  echo "[warn] 缺少 lsof，未检查 mixed 本地监听端口占用"
elif lsof -nP -iTCP:"$MIXED_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[warn] mixed 本地监听端口已被占用"
else
  echo "[ok] mixed 本地监听端口未发现占用"
fi

echo
echo "[done] local sing-box is prepared; this script did not connect or change network settings"
