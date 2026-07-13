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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=lib/require_tty.sh
source "$SCRIPT_DIR/lib/require_tty.sh"
configure_ssh_auth_opts

echo "== local server config =="
if [ -f "$CONFIG_FILE" ]; then
  bash "$SCRIPT_DIR/validate_xray_config.sh" "$CONFIG_FILE"
  NODE_PORT="$(jq -r '.inbounds[0].port' "$CONFIG_FILE")"
else
  echo "[warn] 本地服务端配置不存在：$CONFIG_FILE"
fi

echo
echo "== local shadowrocket link =="
if [ -f "$LINK_FILE" ]; then
  bash "$SCRIPT_DIR/validate_shadowrocket_link.sh" "$LINK_FILE" "$CONFIG_FILE"
else
  echo "[warn] Shadowrocket 链接不存在：$LINK_FILE"
fi

echo
echo "== tcp port from this Mac =="
if [ -n "$VPS_HOST" ] && [ -n "$NODE_PORT" ]; then
  if nc -z -w 8 "$VPS_HOST" "$NODE_PORT" >/dev/null 2>&1; then
    echo "[ok] 本机可以连接配置中的 VPS TCP 端口"
  else
    echo "[error] 本机无法连接配置中的 VPS TCP 端口"
    exit 1
  fi
elif [ -z "$VPS_HOST" ]; then
  echo "[skip] 未提供 VPS_HOST，跳过本机端口检查"
else
  echo "[skip] 未能从本地配置读取 NODE_PORT，跳过本机端口检查"
fi

echo
echo "== remote xray status =="
if [ -n "$VPS_HOST" ]; then
  REMOTE_NODE_PORT="${NODE_PORT:-443}"
  if ! ssh -p "$SSH_PORT" \
    "${SSH_AUTH_OPTS[@]}" \
    -o BatchMode=no \
    -o ConnectTimeout=15 \
    "$SSH_USER@$VPS_HOST" \
    "NODE_PORT='$REMOTE_NODE_PORT' bash -s" 2>/dev/null <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，只输出字段状态，不输出主机、端口或日志内容。
echo '[remote] service:'
if systemctl is-active --quiet xray; then
  echo '[remote-ok] xray service is active'
else
  echo '[remote-error] xray service is not active'
  exit 1
fi

echo '[remote] listen:'
if ss -lntH | awk -v port="$NODE_PORT" '$4 ~ (":" port "$") {found=1} END {exit !found}'; then
  echo '[remote-ok] configured TCP port is listening'
else
  echo '[remote-error] configured TCP port is not listening'
  exit 1
fi

echo '[remote] ufw:'
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -Eq "^${NODE_PORT}/tcp[[:space:]]+ALLOW"; then
    echo "[remote-ok] ufw allows configured TCP port"
  else
    echo "[remote-warn] ufw may not allow configured TCP port"
  fi
else
  echo '[remote-info] ufw not installed'
fi
REMOTE_SCRIPT
  then
    echo "[error] 远端 Xray 只读健康检查失败"
    exit 1
  fi
else
  echo "[skip] 未提供 VPS_HOST，跳过远程服务检查"
fi

echo
echo "[done] health check finished"
