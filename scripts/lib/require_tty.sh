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
