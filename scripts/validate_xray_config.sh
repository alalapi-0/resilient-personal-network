#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于校验 Xray 服务端配置文件。
# 默认检查 configs/server/config.json，也可以传入其他路径。
# 安全原则：
# 1) 不打印 UUID、私钥、shortId 等真实敏感值；
# 2) 只输出检查结果、错误类型和必要的行号；
# 3) 先检查占位符和 JSON 格式，再检查关键字段类型。

CONFIG_FILE="${1:-configs/server/config.json}"
ERROR_COUNT=0

# 输出错误并累计错误数。
report_error() {
  local message="$1"
  ERROR_COUNT=$((ERROR_COUNT + 1))
  echo "[error] $message"
}

# 输出成功检查项。
report_ok() {
  local message="$1"
  echo "[ok] $message"
}

# 确认配置文件存在。
if [ ! -f "$CONFIG_FILE" ]; then
  report_error "配置文件不存在：$CONFIG_FILE"
  exit 1
fi

# 确认 jq 可用。
if ! command -v jq >/dev/null 2>&1; then
  report_error "缺少 jq，请先安装 jq 后再校验"
  exit 1
fi

echo "[info] checking $CONFIG_FILE"

# 检查是否还有 ${...} 占位符。
if grep -qF '${' "$CONFIG_FILE"; then
  PLACEHOLDER_LINES="$(grep -nF '${' "$CONFIG_FILE" | cut -d ':' -f 1 | tr '\n' ',' | sed 's/,$//')"
  report_error "仍有未替换占位符，所在行：$PLACEHOLDER_LINES"
else
  report_ok "未发现未替换占位符"
fi

# 检查 JSON 是否有效。这里不打印文件内容，避免泄露敏感值。
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
  report_error "JSON 格式无效，请先修复逗号、引号、数字字段或残留占位符"
  echo "[hint] 常见错误：把 \"\${XRAY_UUID}\" 改成 \"\${真实UUID}\"，正确做法是改成 \"真实UUID\""
  echo "[hint] 常见错误：把 \"port\": \${XRAY_PORT} 改成 \"port\": \"443\"，正确做法是 \"port\": 443"
  exit 1
fi
report_ok "JSON 格式有效"

# 检查 jq 表达式。失败时只输出字段名称，不输出字段真实值。
check_jq() {
  local description="$1"
  local filter="$2"

  if jq -e "$filter" "$CONFIG_FILE" >/dev/null 2>&1; then
    report_ok "$description"
  else
    report_error "$description"
  fi
}

check_jq "log.loglevel 应为 debug/info/warning/error/none 之一" \
  '(.log.loglevel | type == "string") and (.log.loglevel == "debug" or .log.loglevel == "info" or .log.loglevel == "warning" or .log.loglevel == "error" or .log.loglevel == "none")'

check_jq "inbounds[0].port 应为 1 到 65535 的数字，不能加引号" \
  '(.inbounds[0].port | type == "number") and (.inbounds[0].port >= 1 and .inbounds[0].port <= 65535)'

check_jq "clients[0].id 应为标准 UUID 字符串" \
  '(.inbounds[0].settings.clients[0].id | type == "string") and (.inbounds[0].settings.clients[0].id | test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"))'

check_jq "clients[0].flow 建议为 xtls-rprx-vision" \
  '.inbounds[0].settings.clients[0].flow == "xtls-rprx-vision"'

check_jq "clients[0].email 应为非空备注字符串" \
  '(.inbounds[0].settings.clients[0].email | type == "string") and (.inbounds[0].settings.clients[0].email | length > 0)'

check_jq "realitySettings.dest 应为 域名:端口 格式，例如 www.microsoft.com:443" \
  '(.inbounds[0].streamSettings.realitySettings.dest | type == "string") and (.inbounds[0].streamSettings.realitySettings.dest | test("^[^:]+:[0-9]+$"))'

check_jq "realitySettings.serverNames[0] 应为不带端口的域名" \
  '(.inbounds[0].streamSettings.realitySettings.serverNames[0] | type == "string") and (.inbounds[0].streamSettings.realitySettings.serverNames[0] | length > 0) and ((.inbounds[0].streamSettings.realitySettings.serverNames[0] | contains(":")) | not)'

check_jq "realitySettings.privateKey 应为非空字符串" \
  '(.inbounds[0].streamSettings.realitySettings.privateKey | type == "string") and (.inbounds[0].streamSettings.realitySettings.privateKey | length > 0)'

check_jq "realitySettings.shortIds[0] 应为 2 到 16 位十六进制字符串" \
  '(.inbounds[0].streamSettings.realitySettings.shortIds[0] | type == "string") and (.inbounds[0].streamSettings.realitySettings.shortIds[0] | test("^[0-9a-fA-F]{2,16}$"))'

if [ "$ERROR_COUNT" -eq 0 ]; then
  echo "[done] xray config validation passed"
else
  echo "[failed] xray config validation failed, error count: $ERROR_COUNT"
  exit 1
fi
