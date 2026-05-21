#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于检查 Mac 端 sing-box 配置和当前连接状态。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不打印 UUID、公钥、shortId 等敏感字段；
# 2) 不打印完整客户端配置；
# 3) 默认只做本地配置检查和 TCP 连通性检查；
# 4) 如果设置 CHECK_PUBLIC_IP=yes，会查询当前公网出口 IP，用于确认 Mac 是否已经走 VPS。

CONFIG_FILE="${CONFIG_FILE:-configs/client/singbox.json}"
EXPECTED_EXIT_IP="${EXPECTED_EXIT_IP:-}"
CHECK_PUBLIC_IP="${CHECK_PUBLIC_IP:-yes}"

echo "== macOS environment =="
if [ "$(uname -s)" = "Darwin" ]; then
  echo "[ok] 当前系统是 macOS"
else
  echo "[warn] 当前系统不是 macOS，本脚本仍会继续做配置检查"
fi

for command_name in jq nc curl; do
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "[ok] 命令可用：$command_name"
  else
    echo "[error] 缺少命令：$command_name"
    exit 1
  fi
done

echo
echo "== sing-box config =="
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[error] 找不到配置文件：$CONFIG_FILE"
  echo "请先运行 scripts/generate_singbox_config.sh 生成配置"
  exit 1
fi

if grep -qF '${' "$CONFIG_FILE"; then
  echo "[error] 配置文件仍有未替换占位符"
  exit 1
else
  echo "[ok] 未发现未替换占位符"
fi

jq empty "$CONFIG_FILE" >/dev/null
echo "[ok] JSON 格式有效"

INBOUND_TYPE="$(jq -r '.inbounds[0].type // empty' "$CONFIG_FILE")"
NODE_HOST="$(jq -r '.outbounds[] | select(.tag == "node-primary") | .server // empty' "$CONFIG_FILE" | head -n 1)"
NODE_PORT="$(jq -r '.outbounds[] | select(.tag == "node-primary") | .server_port // empty' "$CONFIG_FILE" | head -n 1)"
NODE_TYPE="$(jq -r '.outbounds[] | select(.tag == "node-primary") | .type // empty' "$CONFIG_FILE" | head -n 1)"
TLS_ENABLED="$(jq -r '.outbounds[] | select(.tag == "node-primary") | .tls.enabled // false' "$CONFIG_FILE" | head -n 1)"
REALITY_ENABLED="$(jq -r '.outbounds[] | select(.tag == "node-primary") | .tls.reality.enabled // false' "$CONFIG_FILE" | head -n 1)"
LEGACY_BLOCK_COUNT="$(jq '[.. | objects | select(.type? == "block")] | length' "$CONFIG_FILE")"

if [ "$INBOUND_TYPE" = "tun" ]; then
  echo "[ok] 入站模式为 tun，适合 sing-box VT 作为 Mac VPN Profile 使用"
elif [ "$INBOUND_TYPE" = "mixed" ]; then
  echo "[warn] 入站模式为 mixed，需要手动设置系统或浏览器代理"
else
  echo "[warn] 未识别的入站模式：${INBOUND_TYPE:-empty}"
fi

if [ "$NODE_TYPE" = "vless" ]; then
  echo "[ok] 节点出站类型为 vless"
else
  echo "[error] 未找到 node-primary vless 出站"
  exit 1
fi

if [ -n "$NODE_HOST" ] && [ -n "$NODE_PORT" ]; then
  echo "[ok] 节点地址和端口字段存在"
else
  echo "[error] 节点地址或端口为空"
  exit 1
fi

if [ "$TLS_ENABLED" = "true" ] && [ "$REALITY_ENABLED" = "true" ]; then
  echo "[ok] TLS REALITY 已启用"
else
  echo "[error] TLS REALITY 未正确启用"
  exit 1
fi

if [ "$LEGACY_BLOCK_COUNT" = "0" ]; then
  echo "[ok] 未发现旧版 block 特殊出站"
else
  echo "[warn] 发现旧版 block 特殊出站，建议重新生成 sing-box 配置"
fi

echo
echo "== tcp port =="
if nc -z -w 8 "$NODE_HOST" "$NODE_PORT" >/dev/null 2>&1; then
  echo "[ok] Mac 可以连通节点 TCP 端口"
else
  echo "[error] Mac 无法连通节点 TCP 端口"
  echo "请先检查 VPS UFW、云厂商防火墙和节点端口"
  exit 1
fi

echo
echo "== public ip =="
if [ "$CHECK_PUBLIC_IP" = "yes" ]; then
  CURRENT_IP="$(curl -fsSL --max-time 10 https://api.ipify.org || true)"
  if [ -z "$CURRENT_IP" ]; then
    echo "[warn] 未能获取当前公网出口 IP"
  else
    echo "[info] 当前公网出口 IP：$CURRENT_IP"
    if [ -n "$EXPECTED_EXIT_IP" ]; then
      if [ "$CURRENT_IP" = "$EXPECTED_EXIT_IP" ]; then
        echo "[ok] 当前出口 IP 与预期 VPS IP 一致"
      else
        echo "[warn] 当前出口 IP 与预期 VPS IP 不一致"
        echo "[hint] 如果你还没有在 Mac 上启用 sing-box，这是正常的；启用后再运行本脚本"
      fi
    else
      echo "[hint] 如需自动比对，运行时传入 EXPECTED_EXIT_IP=\"<你的_VPS_IP>\""
    fi
  fi
else
  echo "[skip] CHECK_PUBLIC_IP 不是 yes，跳过公网出口检查"
fi

echo
echo "[done] macOS sing-box check finished"
