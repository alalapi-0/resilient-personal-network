#!/usr/bin/env bash

define_client_artifact_manifest() {
  CLIENT_ARTIFACT_MANIFEST=(
    "modern|tun|singbox.json|singbox|modern-primary|通用 sing-box 配置"
    "modern|tun|macos_singbox.json|singbox|modern-macos-tun|macOS sing-box TUN 配置"
    "modern|mixed|macos_singbox_mixed.json|singbox|modern-macos-mixed|macOS sing-box mixed 配置"
    "legacy|tun|singbox-ios-legacy-1.11.4.json|singbox|legacy-ios|iOS legacy sing-box 1.11.4 配置"
    "link|-|shadowrocket_link.txt|link|link-primary|通用 VLESS 链接"
    "link|-|ios_shadowrocket_vless_link.txt|link|link-ios|iOS VLESS 链接"
    "link|-|android_v2rayng_vless_link.txt|link|link-android|Android VLESS 链接"
    "conf|-|shadowrocket.conf|shadowrocket|conf-primary|通用 Shadowrocket 配置"
    "conf|-|shadowrocket-macos.conf|shadowrocket-macos|conf-macos|macOS Shadowrocket 配置"
  )
}

validate_client_artifact_manifest_definition() {
  python3 - "${CLIENT_ARTIFACT_MANIFEST[@]}" <<'PY'
import sys
rows = [item.split("|") for item in sys.argv[1:]]
if not rows or any(len(row) != 6 or not all(row) for row in rows):
    raise SystemExit(1)
basenames = [row[2] for row in rows]
roles = [row[4] for row in rows]
if len(basenames) != len(set(basenames)) or len(roles) != len(set(roles)):
    raise SystemExit(1)
if any("/" in name or name in {".", ".."} for name in basenames):
    raise SystemExit(1)
PY
}

if [ "${CLIENT_ARTIFACT_MANIFEST_ONLY:-no}" = "yes" ]; then
  define_client_artifact_manifest
  return 0 2>/dev/null || exit 0
fi

set -euo pipefail

# 校验统一刷新产生的九个客户端产物。
# 输出只描述字段和 PASS/FAIL，不显示连接值。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"
CLIENT_OUTPUT_DIR="${CLIENT_OUTPUT_DIR:-configs/client}"
CHECK_GIT_STATE="${CHECK_GIT_STATE:-yes}"
STRICT_ARTIFACT_SET="${STRICT_ARTIFACT_SET:-yes}"
TRANSACTION_BACKUP_SUFFIX="${TRANSACTION_BACKUP_SUFFIX:-}"

ERROR_COUNT=0

ok() {
  echo "[ok] $1"
}

error() {
  ERROR_COUNT=$((ERROR_COUNT + 1))
  echo "[error] $1"
}

for command_name in jq python3 git; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[error] 缺少必需命令：$command_name"
    exit 1
  fi
done

if [ -n "${SING_BOX_BIN:-}" ]; then
  SELECTED_SING_BOX_BIN="$SING_BOX_BIN"
elif command -v sing-box >/dev/null 2>&1; then
  SELECTED_SING_BOX_BIN="$(command -v sing-box)"
else
  SELECTED_SING_BOX_BIN="$REPO_ROOT/tools/sing-box/sing-box"
fi

if [ ! -x "$SELECTED_SING_BOX_BIN" ]; then
  echo "[error] 找不到可执行的 sing-box 校验器"
  exit 1
fi

if "$SELECTED_SING_BOX_BIN" version >/dev/null 2>&1; then
  ok "sing-box 校验器可执行"
else
  echo "[error] sing-box 校验器无法运行"
  exit 1
fi

for flag_name in CHECK_GIT_STATE STRICT_ARTIFACT_SET; do
  if [ "${!flag_name}" != "yes" ] && [ "${!flag_name}" != "no" ]; then
    echo "[error] $flag_name 只能是 yes 或 no"
    exit 1
  fi
done

define_client_artifact_manifest
if ! validate_client_artifact_manifest_definition; then
  echo "[error] 客户端产物清单定义无效"
  exit 1
fi

CLIENT_ARTIFACT_PATHS=()
CLIENT_ARTIFACT_LABELS=()
CLIENT_ARTIFACT_KINDS=()
CLIENT_ARTIFACT_ROLES=()
SINGBOX_PATHS=()
SINGBOX_LABELS=()
SINGBOX_MODES=()
LINK_PATHS=()
LINK_LABELS=()
CONF_PATHS=()
CONF_LABELS=()
for manifest_entry in "${CLIENT_ARTIFACT_MANIFEST[@]}"; do
  IFS='|' read -r artifact_kind artifact_mode artifact_basename artifact_generator artifact_role artifact_label <<EOF
$manifest_entry
EOF
  artifact_path="$CLIENT_OUTPUT_DIR/$artifact_basename"
  CLIENT_ARTIFACT_KINDS+=("$artifact_kind")
  CLIENT_ARTIFACT_ROLES+=("$artifact_role")
  CLIENT_ARTIFACT_LABELS+=("$artifact_label")
  CLIENT_ARTIFACT_PATHS+=("$artifact_path")
  case "$artifact_kind" in
    modern)
      SINGBOX_PATHS+=("$artifact_path")
      SINGBOX_LABELS+=("$artifact_label")
      SINGBOX_MODES+=("$artifact_mode")
      ;;
    legacy)
      IOS_LEGACY_SINGBOX_CONFIG="$artifact_path"
      ;;
    link)
      LINK_PATHS+=("$artifact_path")
      LINK_LABELS+=("$artifact_label")
      ;;
    conf)
      CONF_PATHS+=("$artifact_path")
      CONF_LABELS+=("$artifact_label")
      ;;
    *)
      echo "[error] 客户端产物清单类型无效"
      exit 1
      ;;
  esac
done

ARTIFACT_PATHS=("$SERVER_CONFIG" "${CLIENT_ARTIFACT_PATHS[@]}")
ARTIFACT_LABELS=("服务端镜像" "${CLIENT_ARTIFACT_LABELS[@]}")

EXPECTED_CLIENT_ARTIFACT_COUNT="${#CLIENT_ARTIFACT_MANIFEST[@]}"
if [ "${#CLIENT_ARTIFACT_PATHS[@]}" -ne "$EXPECTED_CLIENT_ARTIFACT_COUNT" ] \
  || [ "${#CLIENT_ARTIFACT_LABELS[@]}" -ne "$EXPECTED_CLIENT_ARTIFACT_COUNT" ] \
  || [ "${#ARTIFACT_PATHS[@]}" -ne "${#ARTIFACT_LABELS[@]}" ]; then
  echo "[error] 客户端产物清单定义不一致"
  exit 1
fi

if python3 - "${CLIENT_ARTIFACT_PATHS[@]}" <<'PY'
from pathlib import Path
import sys
paths = [(Path(item).parent.resolve() / Path(item).name) for item in sys.argv[1:]]
raise SystemExit(0 if len(paths) == len(set(paths)) else 1)
PY
then
  ok "客户端产物清单路径唯一"
else
  error "客户端产物清单包含重复路径"
fi

if [ -n "$TRANSACTION_BACKUP_SUFFIX" ] && ! printf '%s' "$TRANSACTION_BACKUP_SUFFIX" | grep -Eq '^\.previous\.[0-9]+$'; then
  echo "[error] TRANSACTION_BACKUP_SUFFIX 格式无效"
  exit 1
fi

if [ "$STRICT_ARTIFACT_SET" = "yes" ]; then
  if python3 - "$EXPECTED_CLIENT_ARTIFACT_COUNT" "$TRANSACTION_BACKUP_SUFFIX" "${CLIENT_ARTIFACT_PATHS[@]}" <<'PY'
from pathlib import Path
import sys

expected_count = int(sys.argv[1])
backup_suffix = sys.argv[2]
expected = [(Path(item).parent.resolve() / Path(item).name) for item in sys.argv[3:]]
parents = {item.parent for item in expected}
if len(expected) != expected_count or len(set(expected)) != expected_count or len(parents) != 1:
    raise SystemExit(1)
parent = next(iter(parents))
actual_names = {item.name for item in parent.iterdir()}
expected_names = {item.name for item in expected}
if backup_suffix:
    allowed_backups = {"." + name + backup_suffix for name in expected_names}
    actual_names -= allowed_backups
if actual_names != expected_names:
    raise SystemExit(1)
PY
  then
    ok "客户端目录恰好包含清单中的九个产物"
  else
    error "客户端目录存在缺失、额外、重复或跨目录产物"
  fi
fi

file_mode() {
  local file_path="$1"
  if [ "$(uname -s)" = "Darwin" ]; then
    stat -f '%Lp' "$file_path"
  else
    stat -c '%a' "$file_path"
  fi
}

for index in "${!ARTIFACT_PATHS[@]}"; do
  file_path="${ARTIFACT_PATHS[$index]}"
  file_label="${ARTIFACT_LABELS[$index]}"
  if [ ! -f "$file_path" ] || [ -L "$file_path" ]; then
    error "$file_label 必须是存在的普通文件"
    continue
  fi
  if [ "$(file_mode "$file_path")" = "600" ]; then
    ok "$file_label 权限为 600"
  else
    error "$file_label 权限必须为 600"
  fi
done

if [ "$CHECK_GIT_STATE" = "yes" ]; then
  for index in "${!ARTIFACT_PATHS[@]}"; do
    file_path="${ARTIFACT_PATHS[$index]}"
    file_label="${ARTIFACT_LABELS[$index]}"
    case "$file_path" in
      "$REPO_ROOT"/*) repo_path="${file_path#"$REPO_ROOT"/}" ;;
      /*)
        error "$file_label 不在仓库内，无法检查 Git 状态"
        continue
        ;;
      *) repo_path="${file_path#./}" ;;
    esac

    if git check-ignore -q -- "$repo_path"; then
      ok "$file_label 已被 Git 忽略"
    else
      error "$file_label 必须被 Git 忽略"
    fi

    if git ls-files --error-unmatch -- "$repo_path" >/dev/null 2>&1; then
      error "$file_label 不得被 Git 跟踪"
    else
      ok "$file_label 未被 Git 跟踪"
    fi
  done
else
  ok "fixture 模式已跳过 Git 状态检查"
fi

if bash "$SCRIPT_DIR/validate_xray_config.sh" "$SERVER_CONFIG" >/dev/null; then
  ok "服务端镜像关键字段有效"
else
  error "服务端镜像关键字段无效"
fi

# shellcheck source=lib/check_ai_workflow_domains.sh
source "$SCRIPT_DIR/lib/check_ai_workflow_domains.sh"

for index in "${!SINGBOX_PATHS[@]}"; do
  config_path="${SINGBOX_PATHS[$index]}"
  config_label="${SINGBOX_LABELS[$index]}"
  expected_mode="${SINGBOX_MODES[$index]}"

  if ! jq empty "$config_path" >/dev/null 2>&1; then
    error "$config_label JSON 格式无效"
    continue
  fi
  ok "$config_label JSON 格式有效"

  if grep -qF '${' "$config_path"; then
    error "$config_label 仍有占位符"
  else
    ok "$config_label 没有占位符"
  fi

  if jq -e --arg expected_mode "$expected_mode" '
    (.inbounds[0].type == $expected_mode)
    and ((.route.default_domain_resolver | type) == "string")
    and ((.route.default_domain_resolver | length) > 0)
    and (.route.default_domain_resolver as $resolver
      | any(.dns.servers[]?; .tag == $resolver))
    and all(.dns.servers[]?; (has("address") | not))
    and all(.dns.servers[]?; ((.type | type) == "string") and ((.type | length) > 0))
    and all(.dns.rules[]?; (has("outbound") | not))
    and any(.dns.servers[]?;
      .type == "https"
      and ((.server | type) == "string")
      and ((.server | length) > 0)
      and ((.path | type) == "string")
      and ((.path | length) > 0))
    and any(.dns.servers[]?; .type == "local")
    and all(.outbounds[]?; .type != "block")
  ' "$config_path" >/dev/null 2>&1; then
    ok "$config_label 使用当前 DNS 与路由结构"
  else
    error "$config_label DNS、路由或入站结构不符合要求"
  fi

  if "$SELECTED_SING_BOX_BIN" check -c "$config_path" >/dev/null 2>&1; then
    ok "$config_label 通过 sing-box check"
  else
    error "$config_label 未通过 sing-box check"
  fi

  if check_singbox_ai_workflow_domains "$config_path" >/dev/null; then
    ok "$config_label AI 分流规则完整"
  else
    error "$config_label AI 分流规则不完整"
  fi
done

if ! jq empty "$IOS_LEGACY_SINGBOX_CONFIG" >/dev/null 2>&1; then
  error "iOS legacy sing-box 1.11.4 配置 JSON 格式无效"
else
  ok "iOS legacy sing-box 1.11.4 配置 JSON 格式有效"

  if grep -qF '${' "$IOS_LEGACY_SINGBOX_CONFIG"; then
    error "iOS legacy sing-box 1.11.4 配置仍有占位符"
  else
    ok "iOS legacy sing-box 1.11.4 配置没有占位符"
  fi

  if jq -e '
    (.inbounds[0].type == "tun")
    and ((.route | has("default_domain_resolver")) | not)
    and all(.dns.servers[]?; (has("type") | not))
    and all(.dns.servers[]?;
      ((.address | type) == "string") and ((.address | length) > 0))
    and any(.dns.servers[]?;
      (.address | startswith("https://"))
      and ((.detour | type) == "string")
      and ((.detour | length) > 0))
    and any(.dns.servers[]?; .address == "local")
    and any(.dns.rules[]?;
      .outbound == "any"
      and ((.server | type) == "string")
      and ((.server | length) > 0))
    and all(.outbounds[]?; .type != "block")
  ' "$IOS_LEGACY_SINGBOX_CONFIG" >/dev/null 2>&1; then
    ok "iOS legacy sing-box 1.11.4 配置使用 address DNS 与 outbound 规则"
  else
    error "iOS legacy sing-box 1.11.4 配置 DNS 或路由结构不符合 1.11.x 要求"
  fi

  ok "证据声明：未执行 1.11.4 sing-box check（本机无该版本二进制）"

  if check_singbox_ai_workflow_domains "$IOS_LEGACY_SINGBOX_CONFIG" >/dev/null; then
    ok "iOS legacy sing-box 1.11.4 配置 AI 分流规则完整"
  else
    error "iOS legacy sing-box 1.11.4 配置 AI 分流规则不完整"
  fi
fi

for index in "${!LINK_PATHS[@]}"; do
  link_path="${LINK_PATHS[$index]}"
  link_label="${LINK_LABELS[$index]}"
  if bash "$SCRIPT_DIR/validate_shadowrocket_link.sh" "$link_path" "$SERVER_CONFIG" >/dev/null; then
    ok "$link_label 结构及服务端字段一致"
  else
    error "$link_label 结构或服务端字段不一致"
  fi
done

for index in "${!CONF_PATHS[@]}"; do
  conf_path="${CONF_PATHS[$index]}"
  conf_label="${CONF_LABELS[$index]}"
  if grep -qF '${' "$conf_path"; then
    error "$conf_label 仍有占位符"
  else
    ok "$conf_label 没有占位符"
  fi
  if grep -Eq '^[^#;].* = vless, ' "$conf_path"; then
    ok "$conf_label 包含 VLESS 节点"
  else
    error "$conf_label 缺少 VLESS 节点"
  fi
  if check_shadowrocket_ai_workflow_domains "$conf_path" >/dev/null; then
    ok "$conf_label AI 分流规则完整"
  else
    error "$conf_label AI 分流规则不完整"
  fi
done

CLIENT_ARTIFACT_KINDS_CSV="$(IFS=,; echo "${CLIENT_ARTIFACT_KINDS[*]}")"
CLIENT_ARTIFACT_ROLES_CSV="$(IFS=,; echo "${CLIENT_ARTIFACT_ROLES[*]}")"
if CLIENT_ARTIFACT_KINDS_CSV="$CLIENT_ARTIFACT_KINDS_CSV" CLIENT_ARTIFACT_ROLES_CSV="$CLIENT_ARTIFACT_ROLES_CSV" python3 - \
  "$SERVER_CONFIG" \
  "${CLIENT_ARTIFACT_PATHS[@]}" 2>/dev/null <<'PY'
import json
import os
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

(
    server_path,
    *client_paths,
) = sys.argv[1:]
kinds = os.environ["CLIENT_ARTIFACT_KINDS_CSV"].split(",")
roles = os.environ["CLIENT_ARTIFACT_ROLES_CSV"].split(",")
if len(kinds) != len(client_paths) or len(roles) != len(client_paths):
    raise SystemExit(1)
paths_by_role = dict(zip(roles, client_paths))
if len(paths_by_role) != len(client_paths):
    raise SystemExit(1)
singbox_paths = [path for kind, path in zip(kinds, client_paths) if kind in {"modern", "legacy"}]
link_paths = [path for kind, path in zip(kinds, client_paths) if kind == "link"]
conf_paths = [path for kind, path in zip(kinds, client_paths) if kind == "conf"]


def fail(field):
    print(f"[error] 跨产物字段不一致：{field}")
    raise SystemExit(1)


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def singbox_fields(path):
    data = load_json(path)
    nodes = [item for item in data.get("outbounds", []) if item.get("type") == "vless"]
    if len(nodes) != 1:
        fail("VLESS 节点数量")
    node = nodes[0]
    tls = node.get("tls", {})
    reality = tls.get("reality", {})
    utls = tls.get("utls", {})
    return {
        "host": node.get("server"),
        "port": str(node.get("server_port", "")),
        "uuid": node.get("uuid"),
        "flow": node.get("flow"),
        "sni": tls.get("server_name"),
        "fingerprint": utls.get("fingerprint"),
        "public_key": reality.get("public_key"),
        "short_id": reality.get("short_id"),
    }


def link_fields(path):
    raw = Path(path).read_text(encoding="utf-8")
    lines = raw.splitlines()
    if len(lines) != 1:
        fail("VLESS 链接单行格式")
    parsed = urlsplit(lines[0].strip())
    query = parse_qs(parsed.query, keep_blank_values=True)
    if any(len(values) != 1 for values in query.values()):
        fail("VLESS 链接查询参数")
    try:
        port = str(parsed.port or "")
    except ValueError:
        fail("VLESS 链接端口")
    return {
        "host": parsed.hostname,
        "port": port,
        "uuid": parsed.username,
        "flow": query.get("flow", [""])[0],
        "sni": query.get("sni", [""])[0],
        "fingerprint": query.get("fp", [""])[0],
        "public_key": query.get("pbk", [""])[0],
        "short_id": query.get("sid", [""])[0],
        "node_name": unquote(parsed.fragment),
    }


def conf_fields(path):
    proxy_lines = []
    for raw_line in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")) or " = vless, " not in line:
            continue
        proxy_lines.append(line)
    if len(proxy_lines) != 1:
        fail("Shadowrocket VLESS 节点数量")
    node_name, raw_fields = proxy_lines[0].split(" = ", 1)
    parts = [part.strip() for part in raw_fields.split(",")]
    if len(parts) < 4 or parts[0] != "vless":
        fail("Shadowrocket VLESS 节点结构")
    options = {}
    for item in parts[3:]:
        if "=" in item:
            key, value = item.split("=", 1)
            options[key.strip()] = value.strip()
    return {
        "host": parts[1],
        "port": parts[2],
        "uuid": options.get("username"),
        "flow": options.get("flow"),
        "sni": options.get("serverName"),
        "fingerprint": options.get("fingerprint"),
        "public_key": options.get("public-key"),
        "short_id": options.get("short-id"),
        "node_name": node_name.strip(),
    }


server = load_json(server_path)
inbound = server["inbounds"][0]
server_expected = {
    "port": str(inbound["port"]),
    "uuid": inbound["settings"]["clients"][0]["id"],
    "flow": inbound["settings"]["clients"][0]["flow"],
    "sni": inbound["streamSettings"]["realitySettings"]["serverNames"][0],
    "short_id": inbound["streamSettings"]["realitySettings"]["shortIds"][0],
}

singbox_values = [singbox_fields(path) for path in singbox_paths]
link_values = [link_fields(path) for path in link_paths]
conf_values = [conf_fields(path) for path in conf_paths]
all_values = singbox_values + link_values + conf_values

for field, expected in server_expected.items():
    if any(item.get(field) != expected for item in all_values):
        fail(field)

reference = singbox_fields(paths_by_role["modern-primary"])
for field in ("host", "fingerprint", "public_key"):
    expected = reference.get(field)
    if not expected or any(item.get(field) != expected for item in all_values):
        fail(field)

reference_name = link_fields(paths_by_role["link-primary"]).get("node_name")
if not reference_name:
    fail("node_name")
for item in link_values + conf_values:
    if item.get("node_name") != reference_name:
        fail("node_name")

raw_links = [Path(path).read_bytes() for path in link_paths]
primary_link = Path(paths_by_role["link-primary"]).read_bytes()
if any(content != primary_link for content in raw_links):
    fail("VLESS 链接文件内容")

generic_conf = Path(paths_by_role["conf-primary"]).read_text(encoding="utf-8")
macos_conf = Path(paths_by_role["conf-macos"]).read_text(encoding="utf-8")
if "Managed placeholder template for the portable Shadowrocket profile." not in generic_conf:
    fail("通用 Shadowrocket 模板标记")
if "Managed placeholder template for the macOS Shadowrocket profile." not in macos_conf:
    fail("macOS Shadowrocket 模板标记")

print("[ok] 九个客户端产物的关键字段一致")
PY
then
  ok "跨产物一致性校验通过"
else
  error "跨产物一致性校验失败"
fi

if [ "$ERROR_COUNT" -ne 0 ]; then
  echo "[failed] client artifact validation failed"
  exit 1
fi

echo "[done] client artifact validation passed"
