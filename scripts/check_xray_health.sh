#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于做 Xray + Shadowrocket 的基础健康检查。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不打印 UUID、私钥、公钥、shortId 等敏感内容；
# 2) 本地检查配置格式、链接字段、端口连通性；
# 3) 如果提供 VPS_HOST，则尝试通过 SSH 检查远程服务状态；
# 4) 若 SSH 需要私钥密码，由终端安全提示输入，脚本不保存。

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
NODE_PORT="${NODE_PORT:-}"
CONFIG_FILE="${CONFIG_FILE:-configs/server/config.json}"
LINK_FILE="${LINK_FILE:-configs/client/shadowrocket_link.txt}"

echo "== local server config =="
if [ -f "$CONFIG_FILE" ]; then
  bash scripts/validate_xray_config.sh "$CONFIG_FILE"
  NODE_PORT="$(jq -r '.inbounds[0].port' "$CONFIG_FILE")"
else
  echo "[warn] 本地服务端配置不存在：$CONFIG_FILE"
fi

echo
echo "== local shadowrocket link =="
if [ -f "$LINK_FILE" ]; then
  bash scripts/validate_shadowrocket_link.sh "$LINK_FILE" "$CONFIG_FILE"
else
  echo "[warn] Shadowrocket 链接不存在：$LINK_FILE"
fi

echo
echo "== tcp port from this Mac =="
if [ -n "$VPS_HOST" ] && [ -n "$NODE_PORT" ]; then
  if nc -vz -w 8 "$VPS_HOST" "$NODE_PORT"; then
    echo "[ok] 本机可以连接 VPS TCP 端口：$VPS_HOST:$NODE_PORT"
  else
    echo "[error] 本机无法连接 VPS TCP 端口：$VPS_HOST:$NODE_PORT"
  fi
else
  echo "[skip] 未提供 VPS_HOST，跳过本机端口检查"
fi

echo
echo "== remote xray status =="
if [ -n "$VPS_HOST" ]; then
  REMOTE_NODE_PORT="${NODE_PORT:-443}"
  ssh -p "$SSH_PORT" \
    -o BatchMode=no \
    -o ConnectTimeout=15 \
    "$SSH_USER@$VPS_HOST" \
    "NODE_PORT='$REMOTE_NODE_PORT' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，只输出服务、监听、防火墙状态，不输出密钥。
echo '[remote] service:'
systemctl is-active xray || true

echo '[remote] listen:'
ss -lntp | grep ":$NODE_PORT" || true

echo '[remote] ufw:'
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
  if ufw status | grep -Eq "^${NODE_PORT}/tcp[[:space:]]+ALLOW"; then
    echo "[remote-ok] ufw allows tcp port $NODE_PORT"
  else
    echo "[remote-warn] ufw may not allow tcp port $NODE_PORT"
  fi
else
  echo '[remote-info] ufw not installed'
fi

echo '[remote] recent journal:'
journalctl -u xray -n 20 --no-pager -l \
  | sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}/<uuid-redacted>/g; s/[A-Za-z0-9_-]{30,}/<secret-redacted>/g'
REMOTE_SCRIPT
else
  echo "[skip] 未提供 VPS_HOST，跳过远程服务检查"
fi

echo
echo "[done] health check finished"
