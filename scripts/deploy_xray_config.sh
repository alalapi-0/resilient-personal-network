#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于把本地 Xray 服务端配置安全部署到 VPS。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 部署前先校验本地配置，不通过就停止；
# 2) 上传到远程临时路径后，再在 VPS 上校验 JSON 与占位符；
# 3) 覆盖远程配置前自动备份旧配置；
# 4) 不打印 UUID、REALITY 私钥、shortId 等敏感内容；
# 5) 设置 root:xray + 640 权限，确保 xray 服务进程可读。

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
CONFIG_FILE="${CONFIG_FILE:-configs/server/config.json}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/opt/resilient-personal-network}"
REMOTE_CONFIG_PATH="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
REMOTE_TMP_PATH="/tmp/xray-config-upload-$(date -u '+%Y%m%d-%H%M%S').json"

# 如果未传入 VPS_HOST，则暂停要求用户输入。
if [ -z "$VPS_HOST" ]; then
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
fi

# 检查必要信息。
if [ -z "$VPS_HOST" ]; then
  echo "[error] VPS_HOST 不能为空"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[error] 本地配置文件不存在：$CONFIG_FILE"
  exit 1
fi

# 先校验本地配置，避免把坏配置上传到 VPS。
echo "[info] validating local config..."
bash scripts/validate_xray_config.sh "$CONFIG_FILE"

echo
echo "即将部署 Xray 配置到 VPS："
echo "  主机：$VPS_HOST"
echo "  SSH 用户：$SSH_USER"
echo "  SSH 端口：$SSH_PORT"
echo "  本地配置：$CONFIG_FILE"
echo "  远程配置：$REMOTE_CONFIG_PATH"
echo "  远程项目目录：$REMOTE_PROJECT_DIR"
echo
read -r -p "确认继续？输入 yes 后继续： " CONFIRM

# 只有明确输入 yes 才继续，避免误覆盖。
if [ "$CONFIRM" != "yes" ]; then
  echo "[cancelled] user cancelled xray config deployment"
  exit 0
fi

SSH_TARGET="${SSH_USER}@${VPS_HOST}"
SSH_OPTS=(
  -p "$SSH_PORT"
  -o BatchMode=no
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
)

# 上传到远程临时路径，先不覆盖正式配置。
echo "[info] uploading config to temporary path..."
scp -P "$SSH_PORT" "$CONFIG_FILE" "$SSH_TARGET:$REMOTE_TMP_PATH"

# 在远程 VPS 上校验、备份、替换、重启。
echo "[info] applying config on remote server..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "REMOTE_TMP_PATH='$REMOTE_TMP_PATH' REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上。
BACKUP_DIR="$REMOTE_PROJECT_DIR/backups"
BACKUP_FILE="$BACKUP_DIR/xray-config-before-deploy-$(date -u '+%Y%m%d-%H%M%S').json"

# 检查 root 权限。
if [ "$(id -u)" -ne 0 ]; then
  echo "[remote-error] 请使用 root 用户部署 Xray 配置"
  exit 1
fi

# 检查远程临时配置是否存在。
if [ ! -f "$REMOTE_TMP_PATH" ]; then
  echo "[remote-error] 远程临时配置不存在：$REMOTE_TMP_PATH"
  exit 1
fi

# 远程再次检查占位符，避免坏配置覆盖正式配置。
if grep -qF '${' "$REMOTE_TMP_PATH"; then
  echo "[remote-error] 远程临时配置仍有未替换占位符，停止部署"
  rm -f "$REMOTE_TMP_PATH"
  exit 1
fi

# 远程再次检查 JSON 格式。
jq empty "$REMOTE_TMP_PATH" >/dev/null
echo "[remote-ok] uploaded config json is valid"

# 确保目录存在。
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$REMOTE_CONFIG_PATH")"
chmod 755 "$(dirname "$REMOTE_CONFIG_PATH")"

# 覆盖前备份旧配置。
if [ -f "$REMOTE_CONFIG_PATH" ]; then
  cp -a "$REMOTE_CONFIG_PATH" "$BACKUP_FILE"
  echo "[remote-ok] previous config backed up"
fi

# 安装新配置并设置权限。
install -o root -g xray -m 640 "$REMOTE_TMP_PATH" "$REMOTE_CONFIG_PATH"
rm -f "$REMOTE_TMP_PATH"
echo "[remote-ok] new config installed"

# 从新配置中读取监听端口，只读取端口数字，不打印任何密钥。
CONFIG_PORT="$(jq -r '.inbounds[0].port' "$REMOTE_CONFIG_PATH")"

# 如果 VPS 启用了 UFW 防火墙，则放行当前 Xray TCP 入站端口。
# 说明：VLESS + REALITY 这里的入站连接是 TCP；客户端里的 UDP 转发是隧道内流量，不需要额外开放 UDP 443。
if command -v ufw >/dev/null 2>&1; then
  UFW_FIRST_LINE="$(ufw status 2>/dev/null | head -n 1 || true)"
  if printf '%s\n' "$UFW_FIRST_LINE" | grep -qi 'active'; then
    if ufw status | grep -Eq "^${CONFIG_PORT}/tcp[[:space:]]+ALLOW"; then
      echo "[remote-ok] ufw already allows tcp port $CONFIG_PORT"
    else
      ufw allow proto tcp to any port "$CONFIG_PORT" comment 'resilient-personal-network xray inbound' >/dev/null
      echo "[remote-ok] ufw allowed tcp port $CONFIG_PORT"
    fi
  else
    echo "[remote-info] ufw is not active, skip firewall update"
  fi
else
  echo "[remote-info] ufw not installed, skip firewall update"
fi

# 确认 xray 用户可读取配置。
su -s /bin/sh -c "test -r '$REMOTE_CONFIG_PATH' && echo '[remote-ok] config readable by xray user'" xray

# 重启服务并输出状态。
systemctl daemon-reload
systemctl restart xray
systemctl is-active --quiet xray
systemctl status xray --no-pager -l
REMOTE_SCRIPT

echo "[done] xray config deployed"
