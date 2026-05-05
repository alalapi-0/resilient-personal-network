#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于在 VPS 上安装 Xray-core 并配置 systemd 服务。
# 运行位置：在你的本机仓库根目录运行，不是在 VPS 上直接运行。
# 安全原则：
# 1) 不写入真实 UUID、REALITY 私钥、域名或客户端链接；
# 2) 默认只安装程序和服务文件，不启动代理服务；
# 3) 真实服务端配置需要后续由模板替换占位符后再上传；
# 4) 如远程已有 Xray 配置，本脚本不会覆盖。

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
XRAY_VERSION="${XRAY_VERSION:-latest}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/opt/resilient-personal-network}"

# 如果未传入 VPS_HOST，则暂停要求用户输入。
if [ -z "$VPS_HOST" ]; then
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
fi

# VPS_HOST 是必要信息，缺失时直接停止。
if [ -z "$VPS_HOST" ]; then
  echo "[error] VPS_HOST 不能为空"
  exit 1
fi

echo "即将在 VPS 上安装 Xray-core："
echo "  主机：$VPS_HOST"
echo "  SSH 用户：$SSH_USER"
echo "  SSH 端口：$SSH_PORT"
echo "  Xray 版本：$XRAY_VERSION"
echo "  远程项目目录：$REMOTE_PROJECT_DIR"
echo
echo "本脚本只安装 Xray 程序和 systemd 服务，不写入真实代理配置，也不会默认启动服务。"
echo
read -r -p "确认继续？输入 yes 后继续： " CONFIRM

# 只有明确输入 yes 才继续，避免误操作。
if [ "$CONFIRM" != "yes" ]; then
  echo "[cancelled] user cancelled xray installation"
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

echo "[info] installing xray on remote server..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "XRAY_VERSION='$XRAY_VERSION' REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，用于安装 Xray-core。

INSTALL_TIME="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
XRAY_DIR="/usr/local/bin"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_LOG_DIR="/var/log/xray"
TMP_DIR="$(mktemp -d)"

# 无论脚本是否成功，退出时都清理临时目录。
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 检查 root 权限。
if [ "$(id -u)" -ne 0 ]; then
  echo "[error] 请使用 root 用户运行，或先切换到具备 sudo 权限的用户"
  exit 1
fi

# 检查必要命令。
for command_name in curl unzip jq systemctl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[error] 缺少命令：$command_name，请先执行 scripts/vps_init.sh"
    exit 1
  fi
done

# 识别 CPU 架构并映射到 Xray 发布包命名。
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    XRAY_ASSET="Xray-linux-64.zip"
    ;;
  aarch64|arm64)
    XRAY_ASSET="Xray-linux-arm64-v8a.zip"
    ;;
  armv7l)
    XRAY_ASSET="Xray-linux-arm32-v7a.zip"
    ;;
  *)
    echo "[error] 暂不支持的系统架构：$ARCH"
    exit 1
    ;;
esac

# 获取下载 URL。latest 会调用 GitHub API 获取最新版本；也可指定 vX.Y.Z。
if [ "$XRAY_VERSION" = "latest" ]; then
  echo "[remote] resolving latest xray release"
  DOWNLOAD_URL="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest \
    | jq -r ".assets[] | select(.name == \"$XRAY_ASSET\") | .browser_download_url" \
    | head -n 1)"
else
  DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_ASSET}"
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "[error] 未找到 Xray 下载地址，请检查版本或系统架构"
  exit 1
fi

echo "[remote] downloading $XRAY_ASSET"
curl -fL --retry 3 --connect-timeout 20 --max-time 300 \
  -o "$TMP_DIR/xray.zip" \
  "$DOWNLOAD_URL"

echo "[remote] extracting xray"
unzip -q "$TMP_DIR/xray.zip" -d "$TMP_DIR/xray"

# 安装二进制文件与资源文件。
install -m 755 "$TMP_DIR/xray/xray" "$XRAY_DIR/xray"
mkdir -p "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR" "$REMOTE_PROJECT_DIR/logs" "$REMOTE_PROJECT_DIR/backups" "$REMOTE_PROJECT_DIR/templates"
chmod 755 "$XRAY_CONFIG_DIR"

if [ -f "$TMP_DIR/xray/geoip.dat" ]; then
  install -m 644 "$TMP_DIR/xray/geoip.dat" "$XRAY_CONFIG_DIR/geoip.dat"
fi

if [ -f "$TMP_DIR/xray/geosite.dat" ]; then
  install -m 644 "$TMP_DIR/xray/geosite.dat" "$XRAY_CONFIG_DIR/geosite.dat"
fi

# 创建 xray 用户；若已存在则忽略。
if ! id xray >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin xray
fi

chown -R xray:xray "$XRAY_LOG_DIR"
chmod 755 "$XRAY_LOG_DIR"

# 若没有真实配置，则写入一个不会启动服务的占位说明文件。
if [ ! -f "$XRAY_CONFIG_DIR/config.json" ]; then
  cat > "$XRAY_CONFIG_DIR/config.json.placeholder" <<'PLACEHOLDER'
{
  "说明": "这里不是可运行配置。请先使用 templates/xray_server_vless_reality.json.template 生成真实 config.json，再上传到 /usr/local/etc/xray/config.json。"
}
PLACEHOLDER
fi

# 写入 systemd 服务文件。服务会读取 /usr/local/etc/xray/config.json。
cat > /etc/systemd/system/xray.service <<'SERVICE'
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload

# 记录安装日志，避免写入任何真实密钥。
{
  echo "安装时间：$INSTALL_TIME"
  echo "Xray 路径：$XRAY_DIR/xray"
  echo "配置目录：$XRAY_CONFIG_DIR"
  echo "日志目录：$XRAY_LOG_DIR"
  echo "服务文件：/etc/systemd/system/xray.service"
  echo "安装版本：$($XRAY_DIR/xray version | head -n 1)"
  echo "服务状态：已安装，未默认启动"
} > "$REMOTE_PROJECT_DIR/logs/xray_install.log"

echo "[remote] xray installed"
echo "[remote] service file installed but service is not started yet"
echo "[remote] install log saved to $REMOTE_PROJECT_DIR/logs/xray_install.log"
REMOTE_SCRIPT

echo "[done] xray installed"
