#!/usr/bin/env bash
# 说明：供需要 VPS_HOST 或交互确认的脚本 source，非 TTY 时快速失败并给出示例命令。
# 用法：在脚本开头设置 SCRIPT_BASENAME 后 source 本文件。

require_vps_host() {
  if [ -n "${VPS_HOST:-}" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "[error] 非交互模式下缺少 VPS_HOST"
    echo "示例：VPS_HOST=\"<你的_VPS_IP>\" bash scripts/${SCRIPT_BASENAME}"
    exit 1
  fi
  read -r -p "请输入 VPS 公网 IP 或域名（不会写入仓库）： " VPS_HOST
  if [ -z "$VPS_HOST" ]; then
    echo "[error] VPS_HOST 不能为空"
    exit 1
  fi
}

require_confirm_yes() {
  if [ "${CONFIRM:-}" = "yes" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "[error] 非交互模式下需要 CONFIRM=yes 才能继续"
    echo "示例：VPS_HOST=\"<你的_VPS_IP>\" CONFIRM=yes bash scripts/${SCRIPT_BASENAME}"
    exit 1
  fi
  read -r -p "确认继续？输入 yes 后继续： " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "[cancelled] user cancelled ${SCRIPT_BASENAME%.sh}"
    exit 0
  fi
}

require_confirm_value() {
  local expected_value="$1"
  local prompt_message="$2"

  if [ "${CONFIRM:-}" = "$expected_value" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "[error] 非交互模式下需要 CONFIRM=$expected_value 才能继续"
    echo "示例：VPS_HOST=\"<你的_VPS_IP>\" CONFIRM=\"$expected_value\" bash scripts/${SCRIPT_BASENAME}"
    exit 1
  fi
  read -r -p "$prompt_message" CONFIRM
  if [ "$CONFIRM" != "$expected_value" ]; then
    echo "[cancelled] user cancelled ${SCRIPT_BASENAME%.sh}"
    exit 0
  fi
}

configure_ssh_auth_opts() {
  SSH_AUTH_MODE="${SSH_AUTH_MODE:-auto}"
  SSH_ASKPASS_MODE="${SSH_ASKPASS_MODE:-none}"
  SSH_KEYCHAIN_MODE="${SSH_KEYCHAIN_MODE:-none}"
  SSH_AUTH_OPTS=()

  case "$SSH_AUTH_MODE" in
    auto)
      ;;
    password)
      SSH_AUTH_OPTS=(
        -o PreferredAuthentications=password
        -o PubkeyAuthentication=no
      )
      ;;
    publickey)
      SSH_AUTH_OPTS=(
        -o PreferredAuthentications=publickey
        -o PasswordAuthentication=no
      )
      ;;
    *)
      echo "[error] SSH_AUTH_MODE 只能是 auto、password 或 publickey，当前值：$SSH_AUTH_MODE"
      exit 1
      ;;
  esac

  case "$SSH_KEYCHAIN_MODE" in
    none)
      ;;
    macos)
      if [ "$(uname -s)" != "Darwin" ]; then
        echo "[error] SSH_KEYCHAIN_MODE=macos 只能在 macOS 上使用"
        exit 1
      fi
      SSH_AUTH_OPTS+=(
        -o IgnoreUnknown=UseKeychain
        -o AddKeysToAgent=yes
        -o UseKeychain=yes
      )
      ;;
    *)
      echo "[error] SSH_KEYCHAIN_MODE 只能是 none 或 macos，当前值：$SSH_KEYCHAIN_MODE"
      exit 1
      ;;
  esac

  if [ -n "${SSH_CONTROL_PATH:-}" ]; then
    SSH_AUTH_OPTS+=(
      -o ControlMaster=auto
      -o ControlPersist="${SSH_CONTROL_PERSIST:-10m}"
      -o ControlPath="$SSH_CONTROL_PATH"
    )
  fi

  case "$SSH_ASKPASS_MODE" in
    none)
      ;;
    macos)
      if [ "$(uname -s)" != "Darwin" ]; then
        echo "[error] SSH_ASKPASS_MODE=macos 只能在 macOS 上使用"
        exit 1
      fi
      if [ -z "${SCRIPT_DIR:-}" ] || [ ! -x "$SCRIPT_DIR/lib/macos_ssh_askpass.sh" ]; then
        echo "[error] 找不到可执行的 macOS SSH askpass helper"
        exit 1
      fi
      export SSH_ASKPASS="$SCRIPT_DIR/lib/macos_ssh_askpass.sh"
      export SSH_ASKPASS_REQUIRE=force
      export DISPLAY="${DISPLAY:-:0}"
      ;;
    *)
      echo "[error] SSH_ASKPASS_MODE 只能是 none 或 macos，当前值：$SSH_ASKPASS_MODE"
      exit 1
      ;;
  esac
}
