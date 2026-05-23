#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于把 VPS 上当前正在使用的 Xray 服务端配置拉取到本地。
# 运行位置：在你的本机仓库根目录运行。
# 适用场景：
# 1) VPS 已经配置好并能连接；
# 2) 新电脑或新仓库缺少本地 configs/server/config.json；
# 3) 需要基于远端真实配置重新生成客户端配置或做本地校验。
# 安全原则：
# 1) 不在终端打印完整 config.json；
# 2) 本地输出文件位于 configs/server/config.json，该路径已被 .gitignore 忽略；
# 3) 如果本地已有配置，会先备份到 backups/；
# 4) SSH 私钥密码由系统终端提示输入，脚本不读取也不保存。

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_CONFIG_PATH="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
LOCAL_CONFIG_FILE="${LOCAL_CONFIG_FILE:-configs/server/config.json}"
LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-backups}"

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
LOCAL_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/xray-config-fetch.XXXXXX.json")"
LOCAL_BACKUP_FILE="$LOCAL_BACKUP_DIR/local-config-before-fetch-${SAFE_HOST}-${TIMESTAMP}.json"

cleanup() {
  rm -f "$LOCAL_TMP_FILE"
}
trap cleanup EXIT

echo "即将从远程 VPS 拉取 Xray 配置："
echo "  主机：$VPS_HOST"
echo "  SSH 用户：$SSH_USER"
echo "  SSH 端口：$SSH_PORT"
echo "  远程配置：$REMOTE_CONFIG_PATH"
echo "  本地输出：$LOCAL_CONFIG_FILE"
echo
echo "注意：拉取到本地的 config.json 包含真实 UUID、REALITY 私钥和 shortId。"
echo "该文件已被 .gitignore 忽略，请不要公开分享或提交到 Git。"
echo
read -r -p "确认继续？输入 yes 后继续： " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "[cancelled] user cancelled remote config fetch"
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

echo "[info] validating remote config before fetch..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，只检查配置文件，不打印真实内容。
if [ ! -f "$REMOTE_CONFIG_PATH" ]; then
  echo "[remote-error] 未找到远程配置：$REMOTE_CONFIG_PATH"
  exit 1
fi

if [ ! -r "$REMOTE_CONFIG_PATH" ]; then
  echo "[remote-error] 当前 SSH 用户无法读取远程配置：$REMOTE_CONFIG_PATH"
  echo "[remote-hint] 请使用 root，或使用有权限读取该文件的用户"
  exit 1
fi

if grep -qF '${' "$REMOTE_CONFIG_PATH"; then
  echo "[remote-error] 远程配置仍包含未替换占位符，停止拉取"
  exit 1
fi

jq empty "$REMOTE_CONFIG_PATH" >/dev/null

CONFIG_PORT="$(jq -r '.inbounds[0].port // empty' "$REMOTE_CONFIG_PATH")"
CONFIG_PROTOCOL="$(jq -r '.inbounds[0].protocol // empty' "$REMOTE_CONFIG_PATH")"
CONFIG_SECURITY="$(jq -r '.inbounds[0].streamSettings.security // empty' "$REMOTE_CONFIG_PATH")"

echo "[remote-ok] config json is valid"
echo "[remote-info] inbound protocol: ${CONFIG_PROTOCOL:-unknown}"
echo "[remote-info] inbound security: ${CONFIG_SECURITY:-unknown}"
echo "[remote-info] inbound port: ${CONFIG_PORT:-unknown}"
REMOTE_SCRIPT

echo "[info] downloading remote config to temporary local file..."
scp -P "$SSH_PORT" "$SSH_TARGET:$REMOTE_CONFIG_PATH" "$LOCAL_TMP_FILE"
chmod 600 "$LOCAL_TMP_FILE"

echo "[info] validating downloaded config..."
bash scripts/validate_xray_config.sh "$LOCAL_TMP_FILE"

mkdir -p "$(dirname "$LOCAL_CONFIG_FILE")"
mkdir -p "$LOCAL_BACKUP_DIR"

if [ -f "$LOCAL_CONFIG_FILE" ]; then
  cp -a "$LOCAL_CONFIG_FILE" "$LOCAL_BACKUP_FILE"
  chmod 600 "$LOCAL_BACKUP_FILE"
  echo "[ok] existing local config backed up to $LOCAL_BACKUP_FILE"
fi

install -m 600 "$LOCAL_TMP_FILE" "$LOCAL_CONFIG_FILE"
echo "[ok] remote config saved to $LOCAL_CONFIG_FILE"
echo "[hint] 现在可以基于该文件重新生成 sing-box / Shadowrocket / Windows v2rayN 链接"
echo "[done] remote xray config fetched"
