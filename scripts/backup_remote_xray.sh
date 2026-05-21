#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于备份 VPS 上的 Xray 配置、服务文件和排障状态。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不把 UUID、私钥、shortId 等敏感内容打印到终端；
# 2) 备份包会包含真实服务端 config.json，因此 backups/ 已被 .gitignore 忽略；
# 3) 备份前会要求确认，避免误操作；
# 4) SSH 私钥密码由系统终端提示输入，脚本不读取也不保存。

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/opt/resilient-personal-network}"
REMOTE_CONFIG_PATH="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-backups}"
DOWNLOAD_BACKUP="${DOWNLOAD_BACKUP:-yes}"

# 如果未传入 VPS_HOST，则暂停要求用户输入。
if [ -z "$VPS_HOST" ]; then
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
fi

if [ -z "$VPS_HOST" ]; then
  echo "[error] VPS_HOST 不能为空"
  exit 1
fi

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
SAFE_HOST="$(printf '%s' "$VPS_HOST" | tr -c 'A-Za-z0-9._-' '_')"
BACKUP_NAME="xray-backup-${SAFE_HOST}-${TIMESTAMP}.tar.gz"
REMOTE_BACKUP_PATH="$REMOTE_PROJECT_DIR/backups/$BACKUP_NAME"
LOCAL_BACKUP_PATH="$LOCAL_BACKUP_DIR/$BACKUP_NAME"

echo "即将备份远程 Xray 节点："
echo "  主机：$VPS_HOST"
echo "  SSH 用户：$SSH_USER"
echo "  SSH 端口：$SSH_PORT"
echo "  远程配置：$REMOTE_CONFIG_PATH"
echo "  远程备份：$REMOTE_BACKUP_PATH"
echo "  本地备份：$LOCAL_BACKUP_PATH"
echo
echo "注意：备份包包含真实服务端配置，请不要公开分享或提交到 Git。"
echo
read -r -p "确认继续？输入 yes 后继续： " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "[cancelled] user cancelled remote backup"
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

mkdir -p "$LOCAL_BACKUP_DIR"

echo "[info] creating remote backup..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' REMOTE_BACKUP_PATH='$REMOTE_BACKUP_PATH' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，用于生成远程备份包。
BACKUP_TIME="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
STAGING_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "[remote-error] 请使用 root 用户备份 Xray"
  exit 1
fi

if [ ! -f "$REMOTE_CONFIG_PATH" ]; then
  echo "[remote-error] 未找到 Xray 配置：$REMOTE_CONFIG_PATH"
  exit 1
fi

mkdir -p "$REMOTE_PROJECT_DIR/backups"

# 复制真实配置到临时目录。该文件含敏感信息，只进入备份包，不打印内容。
cp -a "$REMOTE_CONFIG_PATH" "$STAGING_DIR/config.json"
chmod 600 "$STAGING_DIR/config.json"

# 复制 systemd 服务文件，方便以后恢复运行方式。
if [ -f /etc/systemd/system/xray.service ]; then
  cp -a /etc/systemd/system/xray.service "$STAGING_DIR/xray.service"
fi

# 采集非敏感排障信息，帮助以后判断备份时的服务状态。
{
  echo "备份时间：$BACKUP_TIME"
  echo "远程目录：$REMOTE_PROJECT_DIR"
  echo "配置路径：$REMOTE_CONFIG_PATH"
  echo "主机名：$(hostname)"
  echo "系统内核：$(uname -a)"
  echo "注意：config.json 包含真实服务端敏感配置，请妥善保管。"
} > "$STAGING_DIR/manifest.txt"

if command -v /usr/local/bin/xray >/dev/null 2>&1; then
  /usr/local/bin/xray version > "$STAGING_DIR/xray_version.txt" 2>&1 || true
fi

systemctl status xray --no-pager -l > "$STAGING_DIR/xray_status.txt" 2>&1 || true
ss -lntp > "$STAGING_DIR/listen_tcp.txt" 2>&1 || true

if command -v ufw >/dev/null 2>&1; then
  ufw status verbose > "$STAGING_DIR/ufw_status.txt" 2>&1 || true
fi

journalctl -u xray -n 120 --no-pager -l 2>/dev/null \
  | sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}/<uuid-redacted>/g; s/[A-Za-z0-9_-]{30,}/<secret-redacted>/g' \
  > "$STAGING_DIR/xray_journal_tail_redacted.txt" || true

tar -czf "$REMOTE_BACKUP_PATH" -C "$STAGING_DIR" .
chmod 600 "$REMOTE_BACKUP_PATH"

echo "[remote-ok] backup saved to $REMOTE_BACKUP_PATH"
REMOTE_SCRIPT

if [ "$DOWNLOAD_BACKUP" = "yes" ]; then
  echo "[info] downloading backup to local backups directory..."
  scp -P "$SSH_PORT" "$SSH_TARGET:$REMOTE_BACKUP_PATH" "$LOCAL_BACKUP_PATH"
  chmod 600 "$LOCAL_BACKUP_PATH"
  echo "[ok] local backup saved to $LOCAL_BACKUP_PATH"
else
  echo "[skip] DOWNLOAD_BACKUP is not yes, remote backup kept on VPS only"
fi

echo "[done] remote xray backup finished"
