#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于在 macOS 上把 Shadowrocket 导入链接复制到剪贴板。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不在终端打印 vless:// 链接内容；
# 2) 复制前先调用校验脚本，确认链接字段与服务端配置一致；
# 3) 链接文件 configs/client/shadowrocket_link.txt 已被 .gitignore 忽略；
# 4) 剪贴板中会短暂保存真实节点链接，用完后可以复制一段普通文字覆盖。

LINK_FILE="${LINK_FILE:-configs/client/shadowrocket_link.txt}"
SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"

echo "== macOS Shadowrocket clipboard =="

if [ "$(uname -s)" != "Darwin" ]; then
  echo "[error] 当前系统不是 macOS，无法使用 pbcopy"
  exit 1
fi

if ! command -v pbcopy >/dev/null 2>&1; then
  echo "[error] 找不到 pbcopy，无法复制到剪贴板"
  exit 1
fi

if [ ! -f "$LINK_FILE" ]; then
  echo "[error] 找不到 Shadowrocket 链接文件：$LINK_FILE"
  echo "请先运行 scripts/generate_shadowrocket_link.sh 生成链接"
  exit 1
fi

if [ ! -f "$SERVER_CONFIG" ]; then
  echo "[error] 找不到服务端配置：$SERVER_CONFIG"
  exit 1
fi

# 复制前先验证链接，避免把旧链接或错误链接导入客户端。
bash scripts/validate_shadowrocket_link.sh "$LINK_FILE" "$SERVER_CONFIG" >/dev/null

tr -d '\n' < "$LINK_FILE" | pbcopy

echo "[ok] Shadowrocket 导入链接已复制到剪贴板"
echo "[hint] 打开 Shadowrocket 后选择从剪贴板或 URL 导入"
echo "[hint] 导入完成后，可以复制一段普通文字覆盖剪贴板中的节点链接"
echo "[done] shadowrocket link copied"
