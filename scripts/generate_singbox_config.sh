#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于从本地 Xray 服务端配置生成 sing-box 客户端配置。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 生成的真实客户端配置写入 configs/client/singbox.json；
# 2) configs/client/*.json 已被 .gitignore 忽略，不应提交到 Git；
# 3) 客户端只需要 REALITY 公钥，不需要私钥；
# 4) 脚本不打印 UUID、公钥、shortId 等真实敏感值。

SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"
TEMPLATE_FILE="${TEMPLATE_FILE:-templates/singbox_client_template.json}"
OUTPUT_FILE="${OUTPUT_FILE:-configs/client/singbox.json}"
NODE_HOST="${NODE_HOST:-}"
XRAY_REALITY_PUBLIC_KEY="${XRAY_REALITY_PUBLIC_KEY:-}"
SINGBOX_LOG_LEVEL="${SINGBOX_LOG_LEVEL:-info}"
SINGBOX_MIXED_PORT="${SINGBOX_MIXED_PORT:-2080}"
SINGBOX_MODE="${SINGBOX_MODE:-tun}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"

if [ -z "$NODE_HOST" ]; then
  echo "[error] 缺少 NODE_HOST，请传入 VPS IP 或域名"
  echo "示例：NODE_HOST=\"<你的_VPS_IP>\" XRAY_REALITY_PUBLIC_KEY=\"<公钥>\" bash scripts/generate_singbox_config.sh"
  exit 1
fi

if [ -z "$XRAY_REALITY_PUBLIC_KEY" ]; then
  echo "[error] 缺少 XRAY_REALITY_PUBLIC_KEY，请传入 xray x25519 输出中的 Public key"
  exit 1
fi

if [ ! -f "$SERVER_CONFIG" ]; then
  echo "[error] 找不到服务端配置：$SERVER_CONFIG"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "[error] 找不到 sing-box 模板：$TEMPLATE_FILE"
  exit 1
fi

if [ "$SINGBOX_MODE" != "tun" ] && [ "$SINGBOX_MODE" != "mixed" ]; then
  echo "[error] SINGBOX_MODE 只能是 tun 或 mixed"
  exit 1
fi

# 先校验服务端配置，避免从坏配置中生成客户端配置。
echo "[info] validating server config..."
bash scripts/validate_xray_config.sh "$SERVER_CONFIG" >/dev/null

# 从服务端配置读取客户端必需字段。
NODE_PORT="$(jq -r '.inbounds[0].port' "$SERVER_CONFIG")"
XRAY_UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$SERVER_CONFIG")"
XRAY_FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow' "$SERVER_CONFIG")"
XRAY_SERVER_NAME="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$SERVER_CONFIG")"
XRAY_REALITY_SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$SERVER_CONFIG")"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# 用 jq 生成 JSON，避免手工字符串替换导致引号或数字类型错误。
if [ "$SINGBOX_MODE" = "tun" ]; then
  # TUN 模式适合 sing-box VT 在 iPhone / iPad / Mac 上作为 VPN Profile 使用。
  jq -n \
    --arg log_level "$SINGBOX_LOG_LEVEL" \
    --arg node_host "$NODE_HOST" \
    --argjson node_port "$NODE_PORT" \
    --arg uuid "$XRAY_UUID" \
    --arg flow "$XRAY_FLOW" \
    --arg server_name "$XRAY_SERVER_NAME" \
    --arg fingerprint "$CLIENT_FINGERPRINT" \
    --arg public_key "$XRAY_REALITY_PUBLIC_KEY" \
    --arg short_id "$XRAY_REALITY_SHORT_ID" \
    '
    {
      log: {
        level: $log_level,
        timestamp: true
      },
      dns: {
        servers: [
          {
            tag: "cloudflare",
            address: "https://1.1.1.1/dns-query",
            detour: "proxy"
          },
          {
            tag: "local",
            address: "local"
          }
        ],
        rules: [
          {
            outbound: "any",
            server: "local"
          }
        ],
        final: "cloudflare"
      },
      inbounds: [
        {
          type: "tun",
          tag: "tun-in",
          address: [
            "172.18.0.1/30",
            "fdfe:dcba:9876::1/126"
          ],
          auto_route: true,
          strict_route: true
        }
      ],
      outbounds: [
        {
          type: "selector",
          tag: "proxy",
          outbounds: [
            "node-primary",
            "direct"
          ],
          default: "node-primary"
        },
        {
          type: "vless",
          tag: "node-primary",
          server: $node_host,
          server_port: $node_port,
          uuid: $uuid,
          flow: $flow,
          packet_encoding: "xudp",
          tls: {
            enabled: true,
            server_name: $server_name,
            utls: {
              enabled: true,
              fingerprint: $fingerprint
            },
            reality: {
              enabled: true,
              public_key: $public_key,
              short_id: $short_id
            }
          }
        },
        {
          type: "direct",
          tag: "direct"
        }
      ],
      route: {
        rules: [
          {
            inbound: "tun-in",
            action: "sniff",
            timeout: "1s"
          },
          {
            protocol: "dns",
            action: "hijack-dns"
          }
        ],
        final: "proxy",
        auto_detect_interface: true
      }
    }
    ' > "$OUTPUT_FILE"
else
  # mixed 模式适合 Mac 上手动设置 HTTP/SOCKS 代理时使用。
  jq -n \
  --arg log_level "$SINGBOX_LOG_LEVEL" \
  --argjson mixed_port "$SINGBOX_MIXED_PORT" \
  --arg node_host "$NODE_HOST" \
  --argjson node_port "$NODE_PORT" \
  --arg uuid "$XRAY_UUID" \
  --arg flow "$XRAY_FLOW" \
  --arg server_name "$XRAY_SERVER_NAME" \
  --arg fingerprint "$CLIENT_FINGERPRINT" \
  --arg public_key "$XRAY_REALITY_PUBLIC_KEY" \
  --arg short_id "$XRAY_REALITY_SHORT_ID" \
  '
  {
    log: {
      level: $log_level,
      timestamp: true
    },
    dns: {
      servers: [
        {
          tag: "cloudflare",
          address: "https://1.1.1.1/dns-query",
          detour: "proxy"
        },
        {
          tag: "local",
          address: "local"
        }
      ],
      rules: [
        {
          outbound: "any",
          server: "local"
        }
      ],
      final: "cloudflare"
    },
    inbounds: [
      {
        type: "mixed",
        tag: "mixed-in",
        listen: "127.0.0.1",
        listen_port: $mixed_port
      }
    ],
    outbounds: [
      {
        type: "selector",
        tag: "proxy",
        outbounds: [
          "node-primary",
          "direct"
        ],
        default: "node-primary"
      },
      {
        type: "vless",
        tag: "node-primary",
        server: $node_host,
        server_port: $node_port,
        uuid: $uuid,
        flow: $flow,
        packet_encoding: "xudp",
        tls: {
          enabled: true,
          server_name: $server_name,
          utls: {
            enabled: true,
            fingerprint: $fingerprint
          },
          reality: {
            enabled: true,
            public_key: $public_key,
            short_id: $short_id
          }
        }
      },
      {
        type: "direct",
        tag: "direct"
      }
    ],
    route: {
      rules: [
        {
          inbound: "mixed-in",
          action: "sniff",
          timeout: "1s"
        },
        {
          protocol: "dns",
          action: "hijack-dns"
        }
      ],
      final: "proxy",
      auto_detect_interface: true
    }
  }
  ' > "$OUTPUT_FILE"
fi

chmod 600 "$OUTPUT_FILE"

# 最后做一次 JSON 校验。
jq empty "$OUTPUT_FILE" >/dev/null

echo "[done] sing-box config saved to $OUTPUT_FILE"
echo "[info] sing-box mode: $SINGBOX_MODE"
echo "[hint] 该文件包含真实节点信息，不要提交、截图或公开分享"
