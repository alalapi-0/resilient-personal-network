#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于初始化一台新的 VPS 节点。
# 运行位置：在你的本机仓库根目录运行，不是在 VPS 上直接运行。
# 安全原则：
# 1) 不在脚本中保存 SSH 密码；
# 2) 不把真实 IP、域名、私钥写入仓库文件；
# 3) 所有真实信息通过环境变量或交互输入提供；
# 4) 远程执行前会展示目标主机并等待确认。

# 定义默认值，用户也可以通过环境变量覆盖。
VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/opt/resilient-personal-network}"

# 若未提供 VPS_HOST，则暂停并要求用户输入。
if [ -z "$VPS_HOST" ]; then
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
fi

# 若用户直接回车，说明缺少必要信息，脚本停止。
if [ -z "$VPS_HOST" ]; then
  echo "[error] VPS_HOST 不能为空"
  exit 1
fi

# 展示即将操作的目标，避免误连到其他服务器。
echo "即将初始化以下 VPS："
echo "  主机：$VPS_HOST"
echo "  SSH 用户：$SSH_USER"
echo "  SSH 端口：$SSH_PORT"
echo "  远程项目目录：$REMOTE_PROJECT_DIR"
echo
echo "如果 SSH 私钥设置了密码，系统可能会要求你输入一次本机私钥密码或钥匙串密码。"
echo "该密码不会被脚本读取、保存或写入日志。"
echo
read -r -p "确认继续？输入 yes 后继续： " CONFIRM

# 只有明确输入 yes 才继续，避免误操作。
if [ "$CONFIRM" != "yes" ]; then
  echo "[cancelled] user cancelled vps initialization"
  exit 0
fi

# 组装 SSH 目标。
SSH_TARGET="${SSH_USER}@${VPS_HOST}"

# 定义 SSH 通用参数：
# - ConnectTimeout：连接超时；
# - ServerAliveInterval/CountMax：远程长时间无输出时保活；
# - BatchMode=no：允许终端提示输入私钥密码。
SSH_OPTS=(
  -p "$SSH_PORT"
  -o BatchMode=no
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
)

# 通过 SSH 在远程 VPS 上执行初始化命令。
# 注意：这里使用 bash -s 传入脚本，避免在仓库中写入真实服务器信息。
echo "[info] initializing remote server..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，用于安装基础依赖并创建目录。
echo "[remote] ssh connection ok"

# 记录当前时间，便于写入初始化日志。
INIT_TIME="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# 检查当前用户是否具备 root 权限。
if [ "$(id -u)" -ne 0 ]; then
  echo "[error] 请使用 root 用户运行，或先切换到具备 sudo 权限的用户"
  exit 1
fi

# 根据不同 Linux 发行版选择包管理器。
if command -v apt-get >/dev/null 2>&1; then
  echo "[remote] detected apt-get"
  echo "[remote] updating apt package index, this may take a few minutes"
  timeout 300 apt-get \
    -o Acquire::ForceIPv4=true \
    -o Acquire::Retries=3 \
    -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 \
    update
  echo "[remote] installing base packages"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Acquire::ForceIPv4=true \
    -o Acquire::Retries=3 \
    -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 \
    ca-certificates \
    curl \
    wget \
    unzip \
    jq \
    cron \
    tar \
    gzip \
    lsof \
    net-tools \
    iproute2 \
    openssl
elif command -v dnf >/dev/null 2>&1; then
  echo "[remote] detected dnf"
  dnf install -y \
    ca-certificates \
    curl \
    wget \
    unzip \
    jq \
    cronie \
    tar \
    gzip \
    lsof \
    net-tools \
    iproute \
    openssl
elif command -v yum >/dev/null 2>&1; then
  echo "[remote] detected yum"
  yum install -y \
    ca-certificates \
    curl \
    wget \
    unzip \
    jq \
    cronie \
    tar \
    gzip \
    lsof \
    net-tools \
    iproute \
    openssl
elif command -v apk >/dev/null 2>&1; then
  echo "[remote] detected apk"
  apk add --no-cache \
    ca-certificates \
    curl \
    wget \
    unzip \
    jq \
    dcron \
    tar \
    gzip \
    lsof \
    net-tools \
    iproute2 \
    openssl
else
  echo "[error] 未识别的包管理器，请手动安装 curl wget unzip jq cron tar gzip lsof openssl"
  exit 1
fi

# 创建远程项目目录结构。
mkdir -p "$REMOTE_PROJECT_DIR"
mkdir -p "$REMOTE_PROJECT_DIR/configs/server"
mkdir -p "$REMOTE_PROJECT_DIR/configs/client"
mkdir -p "$REMOTE_PROJECT_DIR/templates"
mkdir -p "$REMOTE_PROJECT_DIR/nodes"
mkdir -p "$REMOTE_PROJECT_DIR/logs"
mkdir -p "$REMOTE_PROJECT_DIR/backups"
mkdir -p "$REMOTE_PROJECT_DIR/scripts"

# 写入远程初始化日志，只记录动作，不记录密钥或密码。
{
  echo "初始化时间：$INIT_TIME"
  echo "远程目录：$REMOTE_PROJECT_DIR"
  echo "当前用户：$(whoami)"
  echo "系统内核：$(uname -a)"
  echo "已安装基础依赖：curl wget unzip jq cron tar gzip lsof openssl"
} > "$REMOTE_PROJECT_DIR/logs/vps_init.log"

# 确保 cron 服务尽量处于可用状态，不同发行版服务名可能不同。
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable cron >/dev/null 2>&1 || true
  systemctl start cron >/dev/null 2>&1 || true
  systemctl enable crond >/dev/null 2>&1 || true
  systemctl start crond >/dev/null 2>&1 || true
fi

echo "[remote] vps base directories ready"
echo "[remote] log saved to $REMOTE_PROJECT_DIR/logs/vps_init.log"
REMOTE_SCRIPT

echo "[done] vps initialized"
