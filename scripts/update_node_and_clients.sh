#!/usr/bin/env bash
set -euo pipefail

# 说明：按显式开关维护远程 Xray 节点，并统一生成客户端产物。
# 运行位置：在本机仓库根目录运行。
# 适用场景：
# 1) 手动维护：可选备份/升级、拉取远端配置、生成九个客户端产物；
# 2) Codex 自动化：传入 VPS_HOST 和 CONFIRM=yes 后无人值守运行；
# 3) 定期刷新：不频繁轮换 UUID/REALITY 参数，只刷新客户端产物和做健康检查。
# 安全原则：
# 1) 不在终端打印 UUID、私钥、公钥、shortId 或 vless:// 链接；
# 2) 真实配置、链接和备份仍写入 .gitignore 覆盖的本地目录；
# 3) 远端备份和 Xray 升级默认关闭，必须分别显式设置为 yes。

umask 077

VPS_HOST="${VPS_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_AUTH_MODE="${SSH_AUTH_MODE:-auto}"
SSH_ASKPASS_MODE="${SSH_ASKPASS_MODE:-none}"
SSH_KEYCHAIN_MODE="${SSH_KEYCHAIN_MODE:-none}"
SSH_CONTROL_PERSIST="${SSH_CONTROL_PERSIST:-10m}"
SSH_CONTROL_PATH="${SSH_CONTROL_PATH:-}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/opt/resilient-personal-network}"
REMOTE_CONFIG_PATH="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
LOCAL_CONFIG_FILE="${LOCAL_CONFIG_FILE:-configs/server/config.json}"

NODE_HOST="${NODE_HOST:-}"
NODE_NAME="${NODE_NAME:-jp-tokyo-01}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
XRAY_VERSION="${XRAY_VERSION:-latest}"

RUN_BACKUP="${RUN_BACKUP:-no}"
UPDATE_XRAY="${UPDATE_XRAY:-no}"
FETCH_REMOTE_CONFIG="${FETCH_REMOTE_CONFIG:-no}"
GENERATE_CLIENTS="${GENERATE_CLIENTS:-no}"
RUN_HEALTH_CHECK="${RUN_HEALTH_CHECK:-no}"
COPY_LINK_TO_CLIPBOARD="${COPY_LINK_TO_CLIPBOARD:-no}"
ALLOW_REMOTE_OPERATIONS="${ALLOW_REMOTE_OPERATIONS:-no}"

CLIENT_OUTPUT_DIR="${CLIENT_OUTPUT_DIR:-configs/client}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_BASENAME="update_node_and_clients.sh"
# shellcheck source=lib/require_tty.sh
source "$SCRIPT_DIR/lib/require_tty.sh"

cd "$REPO_ROOT"

if [ "$CLIENT_OUTPUT_DIR" != "configs/client" ]; then
  echo "[error] CLIENT_OUTPUT_DIR 仅允许固定为 configs/client"
  exit 1
fi
if [ "$LOCAL_CONFIG_FILE" != "configs/server/config.json" ]; then
  echo "[error] LOCAL_CONFIG_FILE 仅允许固定为 configs/server/config.json"
  exit 1
fi

CLIENT_ARTIFACT_MANIFEST_ONLY=yes source "$SCRIPT_DIR/validate_client_artifacts.sh"
for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
  IFS='|' read -r _ _ artifact_basename _ _ _ <<EOF
$manifest_entry
EOF
  if [ "$artifact_basename" = "shadowrocket_link.txt" ]; then
    SHADOWROCKET_LINK_FILE="$CLIENT_OUTPUT_DIR/$artifact_basename"
  fi
done

check_yes_no() {
  local name="$1"
  local value="$2"

  if [ "$value" != "yes" ] && [ "$value" != "no" ]; then
    echo "[error] $name 只能是 yes 或 no"
    exit 1
  fi
}

for flag_name in RUN_BACKUP UPDATE_XRAY FETCH_REMOTE_CONFIG GENERATE_CLIENTS RUN_HEALTH_CHECK COPY_LINK_TO_CLIPBOARD ALLOW_REMOTE_OPERATIONS; do
  check_yes_no "$flag_name" "${!flag_name}"
done

REMOTE_REQUESTED=no
for flag_name in RUN_BACKUP UPDATE_XRAY FETCH_REMOTE_CONFIG RUN_HEALTH_CHECK; do
  if [ "${!flag_name}" = "yes" ]; then
    REMOTE_REQUESTED=yes
  fi
done
if [ "$GENERATE_CLIENTS" = "yes" ] && [ -z "${XRAY_REALITY_PUBLIC_KEY:-}" ]; then
  REMOTE_REQUESTED=yes
fi
if [ "$REMOTE_REQUESTED" = "yes" ] && [ "$ALLOW_REMOTE_OPERATIONS" != "yes" ]; then
  echo "[error] 远端读取或操作未授权；需另行显式设置 ALLOW_REMOTE_OPERATIONS=yes"
  exit 1
fi
if [ "$REMOTE_REQUESTED" = "yes" ]; then
  require_vps_host
fi

if [ "$REMOTE_REQUESTED" = "yes" ] && [ -z "$SSH_CONTROL_PATH" ]; then
  SSH_CONTROL_DIR="${SSH_CONTROL_DIR:-/tmp/rpn-ssh-${USER:-user}}"
  mkdir -p "$SSH_CONTROL_DIR"
  chmod 700 "$SSH_CONTROL_DIR"
  SSH_CONTROL_PATH="$SSH_CONTROL_DIR/%C"
fi
export SSH_CONTROL_PATH
export SSH_CONTROL_PERSIST

if [ "$REMOTE_REQUESTED" = "yes" ]; then
  configure_ssh_auth_opts
else
  SSH_AUTH_OPTS=()
fi

if [ -z "$NODE_HOST" ] && [ -n "$VPS_HOST" ]; then
  NODE_HOST="$VPS_HOST"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[error] 本机缺少 jq，无法生成和校验客户端配置"
  echo "[hint] 请按 jq 官方文档为当前系统安装 jq"
  exit 1
fi

echo "即将维护远程节点并刷新客户端产物："
echo "  SSH 认证模式：$SSH_AUTH_MODE"
echo "  SSH 弹窗模式：$SSH_ASKPASS_MODE"
echo "  SSH Keychain 模式：$SSH_KEYCHAIN_MODE"
echo "  SSH 连接复用：$SSH_CONTROL_PERSIST"
echo "  备份远端配置：$RUN_BACKUP"
echo "  升级 Xray：$UPDATE_XRAY"
echo "  拉取远端配置：$FETCH_REMOTE_CONFIG"
echo "  生成九个客户端产物：$GENERATE_CLIENTS"
echo "  健康检查：$RUN_HEALTH_CHECK"
echo
echo "提示：默认不执行任何远端读取、写入、健康检查或客户端生成。"
echo "提示：不会启动客户端、修改系统代理/VPN 或复制链接到剪贴板。"
echo
require_confirm_yes

SSH_TARGET="${SSH_USER}@${VPS_HOST}"
SSH_OPTS=(
  -p "$SSH_PORT"
  -o BatchMode=no
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
)
if [ "$REMOTE_REQUESTED" = "yes" ]; then
  SSH_OPTS=(
    -p "$SSH_PORT"
    "${SSH_AUTH_OPTS[@]}"
    -o BatchMode=no
    -o ConnectTimeout=15
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=6
  )
fi

derive_reality_public_key_from_vps() {
  local remote_output
  local public_key

  echo "[info] deriving REALITY public key on remote VPS..." >&2
  if ! remote_output="$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' bash -s" 2>/dev/null <<'REMOTE_SCRIPT'
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[remote-error] 请使用 root 用户读取 Xray 配置" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[remote-error] 远端缺少 jq" >&2
  exit 1
fi

if [ ! -x /usr/local/bin/xray ]; then
  echo "[remote-error] 未找到可执行的 /usr/local/bin/xray" >&2
  exit 1
fi

if [ ! -r "$REMOTE_CONFIG_PATH" ]; then
  echo "[remote-error] 当前 SSH 用户无法读取远端配置：$REMOTE_CONFIG_PATH" >&2
  exit 1
fi

PRIVATE_KEY="$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$REMOTE_CONFIG_PATH")"
if [ -z "$PRIVATE_KEY" ]; then
  echo "[remote-error] REALITY privateKey 为空" >&2
  exit 1
fi

PUBLIC_KEY="$(/usr/local/bin/xray x25519 -i "$PRIVATE_KEY" \
  | sed -nE 's/^(Public key|PublicKey|Password \(PublicKey\)):[[:space:]]*//p' \
  | head -n 1 \
  | tr -d '\r\n ')"
if [ -z "$PUBLIC_KEY" ]; then
  echo "[remote-error] 无法从 privateKey 派生 public key" >&2
  exit 1
fi

printf 'PUBLIC_KEY:%s\n' "$PUBLIC_KEY"
REMOTE_SCRIPT
  )"; then
    echo "[error] 远端派生 REALITY 公钥失败" >&2
    return 1
  fi

  public_key="$(printf '%s\n' "$remote_output" | sed -n 's/^PUBLIC_KEY://p' | tail -n 1)"
  if ! printf '%s' "$public_key" | grep -Eq '^[A-Za-z0-9_-]{20,}$'; then
    echo "[error] 派生出的 REALITY 公钥格式异常" >&2
    return 1
  fi

  printf '%s' "$public_key"
}

restart_remote_xray() {
  echo "[info] restarting remote xray service..."
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "REMOTE_CONFIG_PATH='$REMOTE_CONFIG_PATH' REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[remote-error] 请使用 root 用户重启 Xray"
  exit 1
fi

if [ ! -f "$REMOTE_CONFIG_PATH" ]; then
  echo "[remote-error] 未找到 Xray 配置：$REMOTE_CONFIG_PATH"
  exit 1
fi

if ! getent group xray >/dev/null 2>&1; then
  echo "[remote-error] 未找到 xray 用户组，请先安装 Xray"
  exit 1
fi

chown root:xray "$REMOTE_CONFIG_PATH"
chmod 640 "$REMOTE_CONFIG_PATH"
chmod 755 "$(dirname "$REMOTE_CONFIG_PATH")"
su -s /bin/sh -c "test -r '$REMOTE_CONFIG_PATH' && echo '[remote-ok] config readable by xray user'" xray

CONFIG_PORT="$(jq -r '.inbounds[0].port' "$REMOTE_CONFIG_PATH")"
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

systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
systemctl is-active --quiet xray

if command -v /usr/local/bin/xray >/dev/null 2>&1; then
  /usr/local/bin/xray version | head -n 1
fi
echo "[remote-ok] xray service is active"
REMOTE_SCRIPT
}

if [ "$RUN_BACKUP" = "yes" ]; then
  echo
  echo "== remote backup =="
  CONFIRM=yes \
  VPS_HOST="$VPS_HOST" \
  SSH_USER="$SSH_USER" \
  SSH_PORT="$SSH_PORT" \
  SSH_AUTH_MODE="$SSH_AUTH_MODE" \
  SSH_ASKPASS_MODE="$SSH_ASKPASS_MODE" \
  SSH_KEYCHAIN_MODE="$SSH_KEYCHAIN_MODE" \
  SSH_CONTROL_PATH="$SSH_CONTROL_PATH" \
  SSH_CONTROL_PERSIST="$SSH_CONTROL_PERSIST" \
  REMOTE_PROJECT_DIR="$REMOTE_PROJECT_DIR" \
  REMOTE_CONFIG_PATH="$REMOTE_CONFIG_PATH" \
  bash scripts/backup_remote_xray.sh
fi

if [ "$UPDATE_XRAY" = "yes" ]; then
  echo
  echo "== xray update =="
  CONFIRM=yes \
  VPS_HOST="$VPS_HOST" \
  SSH_USER="$SSH_USER" \
  SSH_PORT="$SSH_PORT" \
  SSH_AUTH_MODE="$SSH_AUTH_MODE" \
  SSH_ASKPASS_MODE="$SSH_ASKPASS_MODE" \
  SSH_KEYCHAIN_MODE="$SSH_KEYCHAIN_MODE" \
  SSH_CONTROL_PATH="$SSH_CONTROL_PATH" \
  SSH_CONTROL_PERSIST="$SSH_CONTROL_PERSIST" \
  XRAY_VERSION="$XRAY_VERSION" \
  REMOTE_PROJECT_DIR="$REMOTE_PROJECT_DIR" \
  bash scripts/install_xray.sh
  if ! restart_remote_xray; then
    echo "[warn] xray restart command returned non-zero, verifying service state..."
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "systemctl is-active --quiet xray"
    echo "[ok] xray service is active after restart"
  fi
fi

if [ "$FETCH_REMOTE_CONFIG" = "yes" ]; then
  echo
  echo "== fetch remote config =="
  CONFIRM=yes \
  VPS_HOST="$VPS_HOST" \
  SSH_USER="$SSH_USER" \
  SSH_PORT="$SSH_PORT" \
  SSH_AUTH_MODE="$SSH_AUTH_MODE" \
  SSH_ASKPASS_MODE="$SSH_ASKPASS_MODE" \
  SSH_KEYCHAIN_MODE="$SSH_KEYCHAIN_MODE" \
  SSH_CONTROL_PATH="$SSH_CONTROL_PATH" \
  SSH_CONTROL_PERSIST="$SSH_CONTROL_PERSIST" \
  REMOTE_CONFIG_PATH="$REMOTE_CONFIG_PATH" \
  LOCAL_CONFIG_FILE="$LOCAL_CONFIG_FILE" \
  bash scripts/fetch_remote_xray_config.sh
fi

if [ "$GENERATE_CLIENTS" = "yes" ]; then
  echo
  echo "== unified client artifacts =="
  if [ ! -f "$LOCAL_CONFIG_FILE" ]; then
    echo "[error] 找不到本地服务端配置：$LOCAL_CONFIG_FILE"
    echo "[hint] 请保持 FETCH_REMOTE_CONFIG=yes，或先手动拉取远端配置"
    exit 1
  fi

  if [ -z "${XRAY_REALITY_PUBLIC_KEY:-}" ]; then
    XRAY_REALITY_PUBLIC_KEY="$(derive_reality_public_key_from_vps)"
  fi

  CLIENT_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rpn-client-refresh.XXXXXX")"
  chmod 700 "$CLIENT_STAGE_DIR"

  cleanup_client_stage() {
    rm -rf "$CLIENT_STAGE_DIR"
  }
  trap cleanup_client_stage EXIT
  trap 'exit 130' INT TERM HUP

  for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
    IFS='|' read -r artifact_kind artifact_mode artifact_basename artifact_generator artifact_role artifact_label <<EOF
$manifest_entry
EOF
    stage_path="$CLIENT_STAGE_DIR/$artifact_basename"
    case "$artifact_generator" in
      singbox)
        NODE_HOST="$NODE_HOST" XRAY_REALITY_PUBLIC_KEY="$XRAY_REALITY_PUBLIC_KEY" \
        SINGBOX_MODE="$artifact_mode" SINGBOX_DNS_STYLE="$artifact_kind" \
        ALLOW_EXTERNAL_OUTPUT=yes \
        CLIENT_FINGERPRINT="$CLIENT_FINGERPRINT" SERVER_CONFIG="$LOCAL_CONFIG_FILE" \
        OUTPUT_FILE="$stage_path" bash scripts/generate_singbox_config.sh
        ;;
      link)
        NODE_HOST="$NODE_HOST" XRAY_REALITY_PUBLIC_KEY="$XRAY_REALITY_PUBLIC_KEY" \
        CLIENT_FINGERPRINT="$CLIENT_FINGERPRINT" NODE_NAME="$NODE_NAME" \
        CONFIG_FILE="$LOCAL_CONFIG_FILE" OUTPUT_FILE="$stage_path" \
        bash scripts/generate_shadowrocket_link.sh
        ;;
      shadowrocket)
        NODE_HOST="$NODE_HOST" XRAY_REALITY_PUBLIC_KEY="$XRAY_REALITY_PUBLIC_KEY" \
        CLIENT_FINGERPRINT="$CLIENT_FINGERPRINT" NODE_NAME="$NODE_NAME" \
        CONFIG_FILE="$LOCAL_CONFIG_FILE" OUTPUT_FILE="$stage_path" \
        bash scripts/generate_shadowrocket_config.sh
        ;;
      shadowrocket-macos)
        NODE_HOST="$NODE_HOST" XRAY_REALITY_PUBLIC_KEY="$XRAY_REALITY_PUBLIC_KEY" \
        CLIENT_FINGERPRINT="$CLIENT_FINGERPRINT" NODE_NAME="$NODE_NAME" \
        CONFIG_FILE="$LOCAL_CONFIG_FILE" OUTPUT_FILE="$stage_path" \
        bash scripts/generate_shadowrocket_macos_config.sh
        ;;
      *) echo "[error] 客户端产物清单生成器无效"; exit 1 ;;
    esac
  done

  SERVER_CONFIG="$LOCAL_CONFIG_FILE" \
  CLIENT_OUTPUT_DIR="$CLIENT_STAGE_DIR" \
  CHECK_GIT_STATE=no \
  bash scripts/validate_client_artifacts.sh >/dev/null

  MANIFEST_BASENAMES=()
  for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
    IFS='|' read -r _ _ artifact_basename _ _ _ <<EOF
$manifest_entry
EOF
    MANIFEST_BASENAMES+=("$artifact_basename")
  done
  python3 - "$REPO_ROOT" "$CLIENT_OUTPUT_DIR" "${MANIFEST_BASENAMES[@]}" <<'PY'
from pathlib import Path
import os
import stat
import sys

root = Path(sys.argv[1]).absolute()
output = Path(sys.argv[2])
expected_names = set(sys.argv[3:])
expected = root / "configs" / "client"
if not output.is_absolute():
    output = root / output
current = Path(output.anchor)
for part in output.parts[1:]:
    current = current / part
    if os.path.lexists(current) and stat.S_ISLNK(os.lstat(current).st_mode):
        raise SystemExit("[error] 客户端发布路径不得包含符号链接")
if output.absolute() != expected or output.resolve() != expected:
    raise SystemExit("[error] 客户端发布仅允许仓库 configs/client")
if not output.is_dir():
    raise SystemExit("[error] 客户端发布目录必须预先存在")
actual_names = {item.name for item in output.iterdir()}
if not actual_names.issubset(expected_names):
    raise SystemExit("[error] 客户端发布目录包含清单外条目")
PY

  PUBLISH_TEMPS=()
  PUBLISH_BACKUPS=()
  PUBLISH_DESTINATIONS=()
  PUBLISH_HAD_ORIGINAL=()
  rollback_publish() {
    local index
    for index in "${!PUBLISH_DESTINATIONS[@]}"; do
      if [ -e "${PUBLISH_BACKUPS[$index]}" ]; then
        mv -f "${PUBLISH_BACKUPS[$index]}" "${PUBLISH_DESTINATIONS[$index]}"
      elif [ "${PUBLISH_HAD_ORIGINAL[$index]}" = "no" ] && [ -e "${PUBLISH_DESTINATIONS[$index]}" ]; then
        rm -f "${PUBLISH_DESTINATIONS[$index]}"
      fi
      if [ -e "${PUBLISH_TEMPS[$index]}" ]; then
        rm -f "${PUBLISH_TEMPS[$index]}"
      fi
    done
  }
  trap 'rollback_publish; cleanup_client_stage' EXIT
  trap 'rollback_publish; cleanup_client_stage; exit 130' INT TERM HUP

  for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
    IFS='|' read -r _ _ artifact_basename _ _ _ <<EOF
$manifest_entry
EOF
    destination="$CLIENT_OUTPUT_DIR/$artifact_basename"
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
      echo "[error] 客户端发布目标必须是普通文件且不得是符号链接"
      exit 1
    fi
    prepared="$(mktemp "$CLIENT_OUTPUT_DIR/.${artifact_basename}.next.XXXXXX")"
    backup="$CLIENT_OUTPUT_DIR/.${artifact_basename}.previous.$$"
    PUBLISH_TEMPS+=("$prepared")
    PUBLISH_BACKUPS+=("$backup")
    PUBLISH_DESTINATIONS+=("$destination")
    if [ -e "$destination" ]; then
      PUBLISH_HAD_ORIGINAL+=("yes")
    else
      PUBLISH_HAD_ORIGINAL+=("no")
    fi
    install -m 600 "$CLIENT_STAGE_DIR/$artifact_basename" "$prepared"
  done
  for index in "${!PUBLISH_DESTINATIONS[@]}"; do
    destination="${PUBLISH_DESTINATIONS[$index]}"
    if [ -e "$destination" ]; then
      mv "$destination" "${PUBLISH_BACKUPS[$index]}"
    fi
    mv "${PUBLISH_TEMPS[$index]}" "$destination"
  done

  SERVER_CONFIG="$LOCAL_CONFIG_FILE" \
  CLIENT_OUTPUT_DIR="$CLIENT_OUTPUT_DIR" \
  CHECK_GIT_STATE=yes \
  STRICT_ARTIFACT_SET=yes \
  TRANSACTION_BACKUP_SUFFIX=".previous.$$" \
  bash scripts/validate_client_artifacts.sh >/dev/null

  cleanup_committed_publish() {
    local cleanup_path
    for cleanup_path in "${PUBLISH_BACKUPS[@]}" "${PUBLISH_TEMPS[@]}"; do
      if [ -e "$cleanup_path" ]; then
        rm -f "$cleanup_path"
      fi
    done
    cleanup_client_stage
  }
  trap cleanup_committed_publish EXIT
  trap 'cleanup_committed_publish; exit 130' INT TERM HUP

  for backup in "${PUBLISH_BACKUPS[@]}"; do
    if [ -e "$backup" ]; then
      rm -f "$backup"
    fi
  done

  SERVER_CONFIG="$LOCAL_CONFIG_FILE" \
  CLIENT_OUTPUT_DIR="$CLIENT_OUTPUT_DIR" \
  CHECK_GIT_STATE=yes \
  STRICT_ARTIFACT_SET=yes \
  bash scripts/validate_client_artifacts.sh >/dev/null

  if [ "$COPY_LINK_TO_CLIPBOARD" = "yes" ]; then
    if command -v pbcopy >/dev/null 2>&1; then
      pbcopy < "$SHADOWROCKET_LINK_FILE"
      echo "[ok] vless link copied to macOS clipboard"
    else
      echo "[warn] pbcopy 不可用，跳过剪贴板复制"
    fi
  fi

  cleanup_client_stage
  trap - EXIT INT TERM HUP
  unset XRAY_REALITY_PUBLIC_KEY

  echo "[ok] 九个客户端产物已统一生成并校验"
fi

if [ "$RUN_HEALTH_CHECK" = "yes" ]; then
  echo
  echo "== health check =="
  VPS_HOST="$VPS_HOST" \
  SSH_USER="$SSH_USER" \
  SSH_PORT="$SSH_PORT" \
  SSH_AUTH_MODE="$SSH_AUTH_MODE" \
  SSH_ASKPASS_MODE="$SSH_ASKPASS_MODE" \
  SSH_KEYCHAIN_MODE="$SSH_KEYCHAIN_MODE" \
  SSH_CONTROL_PATH="$SSH_CONTROL_PATH" \
  SSH_CONTROL_PERSIST="$SSH_CONTROL_PERSIST" \
  CONFIG_FILE="$LOCAL_CONFIG_FILE" \
  LINK_FILE="$SHADOWROCKET_LINK_FILE" \
  bash scripts/check_xray_health.sh
fi

echo
echo "[done] node maintenance and client refresh finished"
