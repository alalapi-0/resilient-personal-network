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
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
SCRIPT_BASENAME="fetch_remote_xray_config.sh"
# shellcheck source=lib/require_tty.sh
source "$SCRIPT_DIR/lib/require_tty.sh"

require_vps_host
configure_ssh_auth_opts

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
LOCAL_TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/xray-config-fetch.XXXXXX")"
LOCAL_BACKUP_FILE="$LOCAL_BACKUP_DIR/local-config-before-fetch-${TIMESTAMP}.json"
LOCAL_INSTALL_TMP=""

cleanup() {
  rm -f "$LOCAL_TMP_FILE"
  if [ -n "$LOCAL_INSTALL_TMP" ]; then
    rm -f "$LOCAL_INSTALL_TMP"
  fi
}
trap cleanup EXIT

echo "即将从远程 VPS 拉取 Xray 配置："
echo "  远程读取：已配置"
echo "  本地敏感镜像：已配置"
echo
echo "注意：拉取到本地的 config.json 包含真实 UUID、REALITY 私钥和 shortId。"
echo "该文件已被 .gitignore 忽略，请不要公开分享或提交到 Git。"
echo
require_confirm_yes

SSH_TARGET="${SSH_USER}@${VPS_HOST}"
SSH_OPTS=(
  -p "$SSH_PORT"
  "${SSH_AUTH_OPTS[@]}"
  -o BatchMode=no
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
)

echo "[info] validating remote config before fetch..."
if ! ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' bash -s" 2>/dev/null <<'REMOTE_SCRIPT'
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

echo "[remote-ok] config json is valid"
if jq -e '
  (.inbounds[0].port | type == "number")
  and (.inbounds[0].protocol == "vless")
  and (.inbounds[0].streamSettings.security == "reality")
' "$REMOTE_CONFIG_PATH" >/dev/null; then
  echo "[remote-ok] required inbound fields are present"
else
  echo "[remote-error] required inbound fields are invalid"
  exit 1
fi
REMOTE_SCRIPT
then
  echo "[error] 远端配置预检失败"
  exit 1
fi

echo "[info] downloading remote config to temporary local file..."
if ! scp -q -P "$SSH_PORT" "${SSH_AUTH_OPTS[@]}" \
  "$SSH_TARGET:$REMOTE_CONFIG_PATH" "$LOCAL_TMP_FILE" 2>/dev/null; then
  echo "[error] 远端配置下载失败"
  exit 1
fi
chmod 600 "$LOCAL_TMP_FILE"

echo "[info] validating downloaded config..."
if [ ! -s "$LOCAL_TMP_FILE" ]; then
  echo "[error] 下载到本地的配置文件为空，停止写入"
  exit 1
fi

if grep -qF '${' "$LOCAL_TMP_FILE"; then
  echo "[error] 下载到本地的配置仍包含未替换占位符，停止写入"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  bash scripts/validate_xray_config.sh "$LOCAL_TMP_FILE"
else
  echo "[warn] 本机缺少 jq，跳过本地严格字段校验"
  echo "[warn] 远端已完成 JSON 和基础字段校验，本次仍会保存配置到本地"
  echo "[hint] 后续生成客户端配置仍需要 jq；请按 jq 官方文档为当前系统安装"
fi

mkdir -p "$(dirname "$LOCAL_CONFIG_FILE")"
mkdir -p "$LOCAL_BACKUP_DIR"

if [ -f "$LOCAL_CONFIG_FILE" ]; then
  cp -a "$LOCAL_CONFIG_FILE" "$LOCAL_BACKUP_FILE"
  chmod 600 "$LOCAL_BACKUP_FILE"
  echo "[ok] existing local config backed up"
fi

LOCAL_CONFIG_DIR="$(dirname "$LOCAL_CONFIG_FILE")"
LOCAL_CONFIG_NAME="$(basename "$LOCAL_CONFIG_FILE")"
LOCAL_INSTALL_TMP="$(mktemp "$LOCAL_CONFIG_DIR/.${LOCAL_CONFIG_NAME}.tmp.XXXXXX")"
install -m 600 "$LOCAL_TMP_FILE" "$LOCAL_INSTALL_TMP"
mv -f "$LOCAL_INSTALL_TMP" "$LOCAL_CONFIG_FILE"
LOCAL_INSTALL_TMP=""
echo "[ok] remote config saved to ignored local mirror"
echo "[hint] 现在可以基于该文件重新生成 sing-box / Shadowrocket / Windows v2rayN 链接"
echo "[done] remote xray config fetched"
