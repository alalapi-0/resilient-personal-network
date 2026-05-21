#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于采集 VPS 上的非敏感诊断信息，保存到本地 logs/。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不打印完整 config.json；
# 2) 只输出端口、协议、监听、防火墙、服务状态等排障信息；
# 3) 日志会做基础脱敏，隐藏 UUID 和较长疑似密钥字符串；
# 4) logs/ 已被 .gitignore 忽略，避免误提交诊断日志。

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_CONFIG_PATH="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
LOCAL_LOG_DIR="${LOCAL_LOG_DIR:-logs}"

if [ -z "$VPS_HOST" ]; then
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
fi

if [ -z "$VPS_HOST" ]; then
  echo "[error] VPS_HOST 不能为空"
  exit 1
fi

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
SAFE_HOST="$(printf '%s' "$VPS_HOST" | tr -c 'A-Za-z0-9._-' '_')"
OUTPUT_FILE="$LOCAL_LOG_DIR/remote-diagnostics-${SAFE_HOST}-${TIMESTAMP}.txt"

SSH_TARGET="${SSH_USER}@${VPS_HOST}"
SSH_OPTS=(
  -p "$SSH_PORT"
  -o BatchMode=no
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
)

mkdir -p "$LOCAL_LOG_DIR"

echo "[info] collecting remote diagnostics..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' bash -s" > "$OUTPUT_FILE" <<'REMOTE_SCRIPT'
set -euo pipefail

# 说明：以下命令运行在 VPS 上，只采集诊断信息，不输出完整敏感配置。
redact_stream() {
  sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}/<uuid-redacted>/g; s/[A-Za-z0-9_-]{30,}/<secret-redacted>/g'
}

section() {
  printf '\n== %s ==\n' "$1"
}

section "basic"
echo "采集时间：$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "主机名：$(hostname)"
echo "当前用户：$(whoami)"
echo "系统内核：$(uname -a)"
uptime || true

section "disk and memory"
df -h / || true
free -h || true

section "cloud init"
cloud-init status 2>/dev/null || true

section "xray version"
if command -v /usr/local/bin/xray >/dev/null 2>&1; then
  /usr/local/bin/xray version 2>&1 | head -n 5 || true
else
  echo "xray binary not found"
fi

section "xray service"
systemctl status xray --no-pager -l 2>&1 | redact_stream || true

section "tcp listen"
ss -lntp 2>&1 | redact_stream || true

section "ufw"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose 2>&1 || true
else
  echo "ufw not installed"
fi

section "iptables summary"
iptables -S 2>/dev/null | sed -n '1,120p' || true

section "xray config summary"
if [ -f "$REMOTE_CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
  jq '{
    loglevel: (.log.loglevel // null),
    inbounds: [
      .inbounds[]? | {
        listen: (.listen // null),
        port: (.port // null),
        protocol: (.protocol // null),
        clients_count: ((.settings.clients // []) | length),
        first_client_flow: (.settings.clients[0].flow // null),
        network: (.streamSettings.network // null),
        security: (.streamSettings.security // null),
        reality_dest: (.streamSettings.realitySettings.dest // null),
        reality_server_names: (.streamSettings.realitySettings.serverNames // []),
        reality_short_ids_count: ((.streamSettings.realitySettings.shortIds // []) | length)
      }
    ],
    outbounds: [
      .outbounds[]? | {
        protocol: (.protocol // null),
        tag: (.tag // null)
      }
    ]
  }' "$REMOTE_CONFIG_PATH" 2>&1 | redact_stream || true
else
  echo "config summary skipped"
fi

section "xray journal tail"
journalctl -u xray -n 120 --no-pager -l 2>&1 | redact_stream || true

section "xray file logs"
if [ -f /var/log/xray/error.log ]; then
  echo "-- error.log --"
  tail -n 80 /var/log/xray/error.log 2>&1 | redact_stream || true
fi
if [ -f /var/log/xray/access.log ]; then
  echo "-- access.log --"
  tail -n 80 /var/log/xray/access.log 2>&1 | redact_stream || true
fi
REMOTE_SCRIPT

chmod 600 "$OUTPUT_FILE"
echo "[done] diagnostics saved to $OUTPUT_FILE"
