#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于校验 Shadowrocket 导入链接是否与本地服务端配置匹配。
# 默认读取 configs/client/shadowrocket_link.txt 和 configs/server/config.json。
# 安全原则：
# 1) 不打印 UUID、公钥、shortId 等真实敏感值；
# 2) 只输出字段是否匹配；
# 3) 公钥无法从链接本身证明一定匹配私钥，只做存在性和格式检查。

LINK_FILE="${1:-configs/client/shadowrocket_link.txt}"
CONFIG_FILE="${2:-configs/server/config.json}"

if [ ! -f "$LINK_FILE" ]; then
  echo "[error] 找不到 Shadowrocket 链接文件：$LINK_FILE"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[error] 找不到服务端配置文件：$CONFIG_FILE"
  exit 1
fi

python3 - "$LINK_FILE" "$CONFIG_FILE" <<'PY'
import json
import re
import sys
from urllib.parse import parse_qs, unquote, urlsplit

link_file, config_file = sys.argv[1], sys.argv[2]
errors = 0

def ok(message):
    print(f"[ok] {message}")

def err(message):
    global errors
    errors += 1
    print(f"[error] {message}")

with open(link_file, "r", encoding="utf-8") as f:
    link = f.read().strip()

with open(config_file, "r", encoding="utf-8") as f:
    cfg = json.load(f)

parsed = urlsplit(link)
query = {k: v[0] for k, v in parse_qs(parsed.query).items()}

if parsed.scheme != "vless":
    err("链接协议应为 vless://")
else:
    ok("链接协议为 vless")

if "@" not in parsed.netloc:
    err("链接缺少 UUID 或服务器地址")
    user = ""
    host_port = ""
else:
    user, host_port = parsed.netloc.split("@", 1)
    ok("链接包含 UUID 和服务器地址")

server_uuid = cfg["inbounds"][0]["settings"]["clients"][0]["id"]
server_port = str(cfg["inbounds"][0]["port"])
server_flow = cfg["inbounds"][0]["settings"]["clients"][0]["flow"]
server_sni = cfg["inbounds"][0]["streamSettings"]["realitySettings"]["serverNames"][0]
server_sid = cfg["inbounds"][0]["streamSettings"]["realitySettings"]["shortIds"][0]

if user == server_uuid:
    ok("UUID 与服务端配置一致")
else:
    err("UUID 与服务端配置不一致")

if ":" in host_port:
    host, port = host_port.rsplit(":", 1)
else:
    host, port = host_port, ""

if host:
    ok("服务器地址存在")
else:
    err("服务器地址为空")

if port == server_port:
    ok("端口与服务端配置一致")
else:
    err("端口与服务端配置不一致")

if query.get("security") == "reality":
    ok("security=reality")
else:
    err("security 应为 reality")

if query.get("type") == "tcp":
    ok("type=tcp")
else:
    err("type 应为 tcp")

if query.get("flow") == server_flow:
    ok("flow 与服务端配置一致")
else:
    err("flow 与服务端配置不一致")

if query.get("sni") == server_sni:
    ok("sni 与服务端 serverName 一致")
else:
    err("sni 与服务端 serverName 不一致")

if query.get("sid") == server_sid:
    ok("shortId 与服务端配置一致")
else:
    err("shortId 与服务端配置不一致")

public_key = query.get("pbk", "")
if re.fullmatch(r"[A-Za-z0-9_-]{20,}", public_key):
    ok("REALITY 公钥字段存在且格式看起来正常")
else:
    err("REALITY 公钥字段缺失或格式异常")

fingerprint = query.get("fp", "")
if fingerprint in {"chrome", "firefox", "safari", "ios", "android", "edge", "random", "randomized"}:
    ok("fingerprint 看起来正常")
else:
    err("fingerprint 不在常见取值内")

node_name = unquote(parsed.fragment)
if node_name:
    ok("节点名称存在")
else:
    err("节点名称为空")

if errors:
    print(f"[failed] shadowrocket link validation failed, error count: {errors}")
    sys.exit(1)

print("[done] shadowrocket link validation passed")
PY
