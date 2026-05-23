#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于准备 Windows 客户端可导入的 VLESS 分享链接文件。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不在终端打印 vless:// 链接内容；
# 2) 生成前先校验链接字段是否与服务端配置一致；
# 3) 输出文件位于 configs/client/，已被 .gitignore 忽略；
# 4) 该文件包含真实节点信息，只能通过可信方式传到 Windows 电脑。

SOURCE_LINK_FILE="${SOURCE_LINK_FILE:-configs/client/shadowrocket_link.txt}"
SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/windows_vless_link.txt}"

echo "== Windows VLESS link =="

if [ ! -f "$SOURCE_LINK_FILE" ]; then
  echo "[error] 找不到 VLESS 链接文件：$SOURCE_LINK_FILE"
  echo "请先运行 scripts/generate_shadowrocket_link.sh 生成链接"
  exit 1
fi

if [ ! -f "$SERVER_CONFIG" ]; then
  echo "[error] 找不到服务端配置：$SERVER_CONFIG"
  exit 1
fi

# 复用 Shadowrocket 链接校验脚本，因为该 vless:// 链接本质上也是 v2rayN 可导入的通用链接。
bash scripts/validate_shadowrocket_link.sh "$SOURCE_LINK_FILE" "$SERVER_CONFIG" >/dev/null

mkdir -p "$(dirname "$OUTPUT_FILE")"
tr -d '\n' < "$SOURCE_LINK_FILE" > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

echo "[ok] Windows VLESS 导入链接已准备好"
echo "[info] 输出文件：$OUTPUT_FILE"
echo "[hint] 该文件包含真实节点链接，不要公开分享或提交到 Git"
echo "[done] windows vless link prepared"
