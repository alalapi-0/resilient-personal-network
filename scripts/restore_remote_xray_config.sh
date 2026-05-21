#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于把本地备份包中的 Xray config.json 恢复到 VPS。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不打印备份包里的真实配置内容；
# 2) 恢复前会备份 VPS 当前配置；
# 3) 恢复后会设置 root:xray + 640 权限，并重启 Xray；
# 4) 这是有风险操作，必须明确输入 RESTORE 才会执行。

BACKUP_FILE="${1:-${BACKUP_FILE:-}}"
VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/opt/resilient-personal-network}"
REMOTE_CONFIG_PATH="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"

if [ -z "$BACKUP_FILE" ]; then
  echo "[error] 请提供备份包路径"
  echo "用法示例："
  echo "  BACKUP_FILE=\"backups/xray-backup-example-20260505-000000.tar.gz\" VPS_HOST=\"<你的_VPS_IP>\" bash scripts/restore_remote_xray_config.sh"
  echo "或："
  echo "  VPS_HOST=\"<你的_VPS_IP>\" bash scripts/restore_remote_xray_config.sh backups/xray-backup-example-20260505-000000.tar.gz"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "[error] 备份包不存在：$BACKUP_FILE"
  exit 1
fi

if ! tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
  echo "[error] 备份包不是有效的 tar.gz 文件：$BACKUP_FILE"
  exit 1
fi

if ! tar -tzf "$BACKUP_FILE" | sed 's#^\./##' | grep -qx 'config.json'; then
  echo "[error] 备份包中未找到 config.json，不能恢复"
  exit 1
fi

if [ -z "$VPS_HOST" ]; then
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
fi

if [ -z "$VPS_HOST" ]; then
  echo "[error] VPS_HOST 不能为空"
  exit 1
fi

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
REMOTE_TMP_BACKUP="/tmp/xray-restore-${TIMESTAMP}.tar.gz"

echo "即将恢复 Xray 配置到远程 VPS："
echo "  主机：$VPS_HOST"
echo "  SSH 用户：$SSH_USER"
echo "  SSH 端口：$SSH_PORT"
echo "  本地备份包：$BACKUP_FILE"
echo "  远程配置：$REMOTE_CONFIG_PATH"
echo
echo "警告：这会替换 VPS 当前 Xray 配置。脚本会先备份当前配置，但仍请确认你选择的是正确备份包。"
echo
read -r -p "确认恢复？输入 RESTORE 后继续： " CONFIRM

if [ "$CONFIRM" != "RESTORE" ]; then
  echo "[cancelled] user cancelled remote restore"
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

echo "[info] uploading backup package to remote temporary path..."
scp -P "$SSH_PORT" "$BACKUP_FILE" "$SSH_TARGET:$REMOTE_TMP_BACKUP"

echo "[info] restoring config on remote server..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "REMOTE_TMP_BACKUP='$REMOTE_TMP_BACKUP' REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，用于从备份包恢复 Xray 配置。
RESTORE_TIME="$(date -u '+%Y%m%d-%H%M%S')"
STAGING_DIR="$(mktemp -d)"
CURRENT_BACKUP="$REMOTE_PROJECT_DIR/backups/xray-config-before-restore-${RESTORE_TIME}.json"

cleanup() {
  rm -rf "$STAGING_DIR"
  rm -f "$REMOTE_TMP_BACKUP"
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "[remote-error] 请使用 root 用户恢复 Xray"
  exit 1
fi

if [ ! -f "$REMOTE_TMP_BACKUP" ]; then
  echo "[remote-error] 远程临时备份包不存在：$REMOTE_TMP_BACKUP"
  exit 1
fi

mkdir -p "$REMOTE_PROJECT_DIR/backups"
tar -xzf "$REMOTE_TMP_BACKUP" -C "$STAGING_DIR"

CONFIG_CANDIDATE="$STAGING_DIR/config.json"
if [ ! -f "$CONFIG_CANDIDATE" ]; then
  echo "[remote-error] 备份包中未解出 config.json"
  exit 1
fi

if grep -qF '${' "$CONFIG_CANDIDATE"; then
  echo "[remote-error] 备份配置中仍有未替换占位符，停止恢复"
  exit 1
fi

jq empty "$CONFIG_CANDIDATE" >/dev/null
echo "[remote-ok] backup config json is valid"

if ! getent group xray >/dev/null 2>&1; then
  echo "[remote-error] 未找到 xray 用户组，请先安装 Xray"
  exit 1
fi

if [ -f "$REMOTE_CONFIG_PATH" ]; then
  cp -a "$REMOTE_CONFIG_PATH" "$CURRENT_BACKUP"
  chmod 600 "$CURRENT_BACKUP"
  echo "[remote-ok] current config backed up before restore"
fi

mkdir -p "$(dirname "$REMOTE_CONFIG_PATH")"
chmod 755 "$(dirname "$REMOTE_CONFIG_PATH")"
install -o root -g xray -m 640 "$CONFIG_CANDIDATE" "$REMOTE_CONFIG_PATH"
echo "[remote-ok] restored config installed"

CONFIG_PORT="$(jq -r '.inbounds[0].port' "$REMOTE_CONFIG_PATH")"

# 如果 VPS 启用了 UFW，恢复后确保监听端口仍然被放行。
if command -v ufw >/dev/null 2>&1; then
  UFW_FIRST_LINE="$(ufw status 2>/dev/null | head -n 1 || true)"
  if printf '%s\n' "$UFW_FIRST_LINE" | grep -qi 'active'; then
    if ufw status | grep -Eq "^${CONFIG_PORT}/tcp[[:space:]]+ALLOW"; then
      echo "[remote-ok] ufw already allows tcp port $CONFIG_PORT"
    else
      ufw allow proto tcp to any port "$CONFIG_PORT" comment 'resilient-personal-network xray inbound' >/dev/null
      echo "[remote-ok] ufw allowed tcp port $CONFIG_PORT"
    fi
  fi
fi

su -s /bin/sh -c "test -r '$REMOTE_CONFIG_PATH' && echo '[remote-ok] config readable by xray user'" xray

systemctl daemon-reload
systemctl restart xray
systemctl is-active --quiet xray
systemctl status xray --no-pager -l
REMOTE_SCRIPT

echo "[done] remote xray config restored"
