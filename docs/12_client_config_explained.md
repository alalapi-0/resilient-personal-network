# 12 客户端配置说明

本文件说明如何使用 Round 3 生成的客户端模板。
本轮目标是让你能把服务端参数填入 sing-box 或 Shadowrocket，并进行第一次连接检查。

## 1. 本轮生成的文件

1. `templates/singbox_client_template.json`：modern sing-box 客户端配置模板（typed DNS）。
2. `templates/singbox_client_ios_legacy_1.11.4_template.json`：嵌入式 sing-box 1.11.4 手机客户端模板（address DNS）。
3. `templates/client_link_template.txt`：Shadowrocket / 通用 VLESS 导入链接模板。
4. `templates/shadowrocket_client.conf.template`：通用完整 Shadowrocket 配置模板。
5. `templates/shadowrocket_macos_ai_workflow.conf.template`：Shadowrocket macOS AI 工作流分流配置模板。

模板中只包含占位符，不包含真实 UUID、公钥、shortId 或服务器地址。

本文件中的 `NODE_HOST="..." \`、`VPS_HOST="..." \` 示例均为 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。
Windows PowerShell 需要改成 `$env:NODE_HOST="..."` 或 `$env:VPS_HOST="..."`，完整说明见 `docs/25_cross_platform_command_guide.md`。

## 2. 你需要准备哪些真实参数

这些参数来自服务端配置和 Xray 生成命令：

| 参数 | 来源 | 说明 |
| --- | --- | --- |
| `${NODE_HOST}` | VPS IP 或域名 | 你目前没有域名时，可以先用 VPS IP |
| `${NODE_PORT}` | 服务端配置 | 通常是 `443` |
| `${SINGBOX_MIXED_PORT}` | 本机客户端设置 | 本机代理监听端口，建议先用 `2080` |
| `${XRAY_UUID}` | `xray uuid` | 必须与服务端 `clients[0].id` 一致 |
| `${XRAY_FLOW}` | 服务端配置 | 通常是 `xtls-rprx-vision` |
| `${XRAY_SERVER_NAME}` | 服务端 REALITY 配置 | 必须与服务端 `serverNames` 一致 |
| `${XRAY_REALITY_PUBLIC_KEY}` | `xray x25519` 输出 | 客户端使用公钥，不使用私钥 |
| `${XRAY_REALITY_SHORT_ID}` | 服务端配置 | 必须与服务端 `shortIds` 一致 |
| `${SINGBOX_LOG_LEVEL}` | 本机客户端设置 | 建议先用 `info`，排障时可改为 `debug` |
| `${CLIENT_FINGERPRINT}` | 客户端设置 | 通常使用 `chrome` |
| `${NODE_NAME}` | 自定义 | 例如 `jp-tokyo-01` |

注意：REALITY 的 `${XRAY_SERVER_NAME}` 不是你的 VPS IP。
它通常是服务端配置里的伪装目标域名，例如 `www.microsoft.com`。

## 3. 每个参数具体怎么填

下面按“新手可直接照着填”的方式说明。

| 占位符 | 应该填什么 | 是否加引号 | 示例 |
| --- | --- | --- | --- |
| `${SINGBOX_LOG_LEVEL}` | sing-box 日志等级 | 已在模板里有引号 | `info` |
| `${SINGBOX_MIXED_PORT}` | 本机代理端口 | 不加引号，必须是数字 | `2080` |
| `${NODE_HOST}` | VPS IP 或域名 | 已在模板里有引号 | `<你的_VPS_IP>` |
| `${NODE_PORT}` | Xray 服务端监听端口 | 不加引号，必须是数字 | `443` |
| `${XRAY_UUID}` | 服务端配置中的 UUID | 已在模板里有引号 | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `${XRAY_FLOW}` | VLESS flow | 已在模板里有引号 | `xtls-rprx-vision` |
| `${XRAY_SERVER_NAME}` | REALITY serverName / SNI | 已在模板里有引号 | `www.microsoft.com` |
| `${CLIENT_FINGERPRINT}` | TLS 指纹 | 已在模板里有引号 | `chrome` |
| `${XRAY_REALITY_PUBLIC_KEY}` | REALITY 公钥 | 已在模板里有引号 | `xray x25519` 输出里的 Public key |
| `${XRAY_REALITY_SHORT_ID}` | REALITY shortId | 已在模板里有引号 | `openssl rand -hex 8` 的结果 |

重要规则：

1. `${SINGBOX_MIXED_PORT}` 和 `${NODE_PORT}` 是数字字段，所以模板里没有双引号。
2. 没替换前，编辑器会把这两个位置标红，这是正常现象。
3. 替换后应该长这样：`"listen_port": 2080`，不是 `"listen_port": "2080"`。
4. 客户端只填 REALITY 公钥，不填私钥。
5. `${XRAY_UUID}`、`${XRAY_FLOW}`、`${XRAY_SERVER_NAME}`、`${XRAY_REALITY_SHORT_ID}` 必须与服务端配置一致。

## 4. sing-box 配置生成

日常刷新推荐使用统一入口，而不是逐个手工生成：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
ALLOW_REMOTE_OPERATIONS="yes" \
RUN_BACKUP="no" \
UPDATE_XRAY="no" \
FETCH_REMOTE_CONFIG="yes" \
GENERATE_CLIENTS="yes" \
RUN_HEALTH_CHECK="yes" \
COPY_LINK_TO_CLIPBOARD="no" \
CONFIRM="yes" \
bash scripts/update_node_and_clients.sh
```

无开关运行时，统一入口默认不执行远端读取、健康检查或生成。上例显式授权只读访问 VPS 活跃配置并派生 REALITY 公钥，一次生成四个 sing-box JSON、三个链接和两个 Shadowrocket conf，不另造或轮换凭据，也不授权备份、升级、重启、部署或修改本机网络。

只有在已经持有可信本地服务端镜像及其正确派生公钥时，才单独运行生成器。例如生成 TUN 配置：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
SINGBOX_MODE="tun" \
bash scripts/generate_singbox_config.sh
```

如需 mixed 配置，显式设置 `SINGBOX_MODE="mixed"` 和不同的 `OUTPUT_FILE`。生成只准备文件，不会启动客户端。

统一入口生成：

```text
configs/client/singbox.json
configs/client/macos_singbox.json
configs/client/macos_singbox_mixed.json
configs/client/singbox-ios-legacy-1.11.4.json
```

前三个是 modern typed DNS；`singbox-ios-legacy-1.11.4.json` 按官方 v1.11.4 schema 生成，但未用 1.11.4 二进制验证运行兼容性。这些文件已被 `.gitignore` 忽略，不会提交到 Git。
它们包含真实节点信息，不要截图或公开发送。

如需单独生成 iOS legacy 产物：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
SINGBOX_DNS_STYLE="legacy" \
bash scripts/generate_singbox_config.sh
```

如果你想手动生成 modern 配置，也可以按下面流程操作。

复制模板到本地真实配置文件：

```bash
cp templates/singbox_client_template.json configs/client/singbox.json
```

然后编辑 `configs/client/singbox.json`，替换所有 `${...}` 占位符。

替换完成后检查是否还有占位符：

```bash
grep -nF '${' configs/client/singbox.json
```

如果还有占位符，会看到对应行号和内容。
如果没有输出，说明占位符替换完毕。

注意：旧文档中曾写成 `grep -n '\\${'`。这个写法容易因为 shell 和正则转义导致误判。
现在统一使用 `grep -nF '${'`，其中 `-F` 表示按固定文本搜索，不按正则解释。

再检查 JSON 格式：

```bash
jq empty configs/client/singbox.json
```

如果没有报错，说明 JSON 格式正确。

## 5. 替换前后示例

替换前：

```json
"listen_port": ${SINGBOX_MIXED_PORT},
"server": "${NODE_HOST}",
"server_port": ${NODE_PORT}
```

替换后：

```json
"listen_port": 2080,
"server": "<你的_VPS_IP>",
"server_port": 443
```

注意：`listen_port` 和 `server_port` 后面是数字，不要加引号。

## 6. sing-box 字段解释

`mixed-in`：
本地混合代理入口。默认监听 `127.0.0.1:2080`。
意思是 sing-box 在你的电脑本机开一个代理入口，浏览器或系统代理可以指向这个地址。
这个端口只在本机使用，不需要在 VPS 防火墙里开放。

`listen`：
本地监听地址。模板里是 `127.0.0.1`，表示只允许本机访问这个代理入口，比较安全。

`listen_port`：
本地监听端口。建议先用 `2080`。如果本机已有软件占用 `2080`，可以改成 `2081`、`2082` 等。

`node-primary`：
你的主节点。里面的 `server`、`server_port`、`uuid`、`flow`、`server_name`、`public_key`、`short_id` 必须与服务端匹配。

`server`：
VPS IP 或域名。你现在没有域名时，可以先填 VPS IP。

`server_port`：
Xray 服务端监听端口。它必须等于服务端配置模板里的 `${XRAY_PORT}`。

`uuid`：
客户端身份 ID。它必须等于服务端配置中 `clients[0].id`。

`flow`：
VLESS 的 flow。服务端使用 `xtls-rprx-vision` 时，客户端也必须填 `xtls-rprx-vision`。

`server_name`：
REALITY 的 SNI。它必须等于服务端 `realitySettings.serverNames` 中的域名。

`public_key`：
REALITY 公钥。来自 `xray x25519` 输出中的 Public key。不要填 Private key。

`short_id`：
REALITY shortId。它必须等于服务端 `realitySettings.shortIds` 中的值。

`utls.fingerprint`：
客户端 TLS 指纹。建议先用 `chrome`。

`proxy`：
节点选择器。当前模板只放了一个主节点和 `direct`，以后可以追加备用节点。

`route.final`：
默认走 `proxy`。在默认代理之前，配置会先显式匹配 AI 工作流和 GitHub 走代理，再用 `geosite-cn` / `geoip-cn` 和少量腾讯、微信补充域名直连大陆流量，避免中国流量绕到 VPS 再回中国。

## 7. 推荐第一次填写值

如果你只是想先跑通第一个节点，可以按下面思路填：

| 参数 | 推荐值 |
| --- | --- |
| `${SINGBOX_LOG_LEVEL}` | `info` |
| `${SINGBOX_MIXED_PORT}` | `2080` |
| `${NODE_HOST}` | 你的 VPS IP |
| `${NODE_PORT}` | `443`，除非服务端用了别的端口 |
| `${XRAY_FLOW}` | `xtls-rprx-vision` |
| `${XRAY_SERVER_NAME}` | 与服务端一致，例如 `www.microsoft.com` |
| `${CLIENT_FINGERPRINT}` | `chrome` |

剩下三个必须从你的真实服务端参数中取：

1. `${XRAY_UUID}`
2. `${XRAY_REALITY_PUBLIC_KEY}`
3. `${XRAY_REALITY_SHORT_ID}`

如果你忘记保存 public key 或 shortId，不要猜，也不要因此轮换稳定凭据。统一刷新入口会读取 VPS 活跃配置，并调用 VPS 上现有 Xray 从当前 REALITY 私钥派生公钥；shortId 直接来自同一份活跃配置。只有存在泄露或明确轮换授权时，才变更服务端凭据并重新部署。

## 8. 多节点如何扩展

当前模板是单节点可用结构。
以后新增备用节点时，可以复制 `node-primary` 这一段，改成：

```text
node-backup-1
```

然后把 `proxy.outbounds` 中增加：

```text
node-backup-1
```

这样客户端就可以在主节点和备用节点之间手动切换。

## 9. Shadowrocket 适合什么场景

Shadowrocket 更适合 iPhone / iPad 上快速导入和日常使用。
如果你的主要目标是手机访问，优先用 Shadowrocket 是合理选择。

本项目同时保留 sing-box 模板，是为了让 Mac 端也有稳定方案。
实际使用建议：

1. iPhone / iPad：优先 Shadowrocket。
2. Mac：优先 sing-box；如果你的 Mac App Store 可以安装 Shadowrocket，也可以尝试 Shadowrocket。
3. 多设备长期维护：仓库继续保存模板和脚本，真实链接只保存在本地忽略文件中。

## 10. 如何确认 sing-box VT App 是否买对

商店名称、开发者和支持设备可能随发布信息变化。安装前应从 sing-box 官方文档进入其 Apple 客户端链接，再在 App Store 页面核对发布者；不要仅凭图标、广告位或相似名称判断。本仓库不固定声称某个商店版本或安装方式当前有效。

## 11. 如何确认 Shadowrocket App 是否买对

从你信任的官方产品页面进入 App Store，再核对完整应用名和发布者。价格、图标、区服可用性和 UI 都不是稳定的身份依据；不要根据本文中的历史截图描述选择应用。

## 12. Shadowrocket 参数怎么填

Shadowrocket 可以用链接导入，也可以手动新增节点。
第一次建议用链接导入，因为字段少、不容易填错。

导入链接模板在：

```text
templates/client_link_template.txt
```

你需要替换这些占位符：

| 占位符 | 填什么 | 从哪里来 |
| --- | --- | --- |
| `${XRAY_UUID}` | 服务端 UUID | `configs/server/config.json` 中的 `clients[0].id` |
| `${NODE_HOST}` | VPS IP 或域名 | 目前没有域名就填 VPS IP |
| `${NODE_PORT}` | 服务端监听端口 | `configs/server/config.json` 中的 `port`，通常 `443` |
| `${XRAY_FLOW}` | VLESS flow | 通常 `xtls-rprx-vision` |
| `${XRAY_SERVER_NAME}` | REALITY SNI | 服务端 `serverNames[0]`，例如 `www.microsoft.com` |
| `${CLIENT_FINGERPRINT}` | TLS 指纹 | 建议 `chrome` |
| `${XRAY_REALITY_PUBLIC_KEY}` | REALITY 公钥 | `xray x25519` 输出中的 Public key |
| `${XRAY_REALITY_SHORT_ID}` | REALITY shortId | 服务端 `shortIds[0]` |
| `${NODE_NAME}` | 节点显示名 | 例如 `jp-tokyo-01` |

注意：

1. Shadowrocket 客户端填公钥，不填私钥。
2. `sni` 必须等于服务端 `serverNames[0]`。
3. `sid` 必须等于服务端 `shortIds[0]`。
4. `flow` 必须与服务端一致。
5. 生成后的真实链接包含敏感信息，不要公开分享。

## 13. 用脚本生成 Shadowrocket 链接

推荐使用脚本生成链接，减少手工复制错误。

前提：

1. 本地 `configs/server/config.json` 已通过校验。
2. 你知道 REALITY 公钥，也就是 `xray x25519` 输出中的 Public key。
3. VPS 上 Xray 已经恢复为 `active (running)`。

在本机仓库根目录执行：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
NODE_NAME="jp-tokyo-01" \
bash scripts/generate_shadowrocket_link.sh
```

脚本会生成：

```text
configs/client/shadowrocket_link.txt
```

这个文件已被 `.gitignore` 忽略，不会提交到 Git。
它包含真实节点信息，不要截图或公开发送。

统一入口还会从两个受版本控制的占位模板生成完整配置：

```text
templates/shadowrocket_client.conf.template
  -> configs/client/shadowrocket.conf
templates/shadowrocket_macos_ai_workflow.conf.template
  -> configs/client/shadowrocket-macos.conf
```

`shadowrocket.conf` 是不含 macOS 本地监听器的通用完整配置；`shadowrocket-macos.conf` 包含本地 HTTP/SOCKS 监听设置。两个运行时文件都包含真实节点信息并被 `.gitignore` 忽略。

不要在录屏、日志或共享终端中打印真实链接。需要导入时，通过受控文件传输或客户端的本地文件/URL 导入入口处理。

## 14. Shadowrocket 导入方式

不要导入 `templates/client_link_template.txt`；它只有占位符，不能连接。使用统一刷新生成的设备链接文件，并通过本地受控方式交给客户端。

导入步骤：

1. 在 iPhone 上复制完整链接。
2. 打开 Shadowrocket。
3. 点击右上角 `+`。
4. 如果 App 自动识别剪贴板，按提示导入。
5. 如果没有自动识别，选择 `Type` 或 `类型` 为 `Subscribe URL / URL / Import from Clipboard` 相关入口。
6. 保存节点。
7. 选择该节点。
8. 打开右上角连接开关。
9. iOS 第一次会弹出添加 VPN 配置权限，选择允许。

生成后的真实链接不要提交到 Git，也不要公开分享。

## 15. Shadowrocket 手动核对字段

导入后，点击节点右侧的 `i` 进入编辑页面。
不要只看第一页，REALITY 相关字段通常藏在 `TLS` 里面。

第一页应大致是：

| 页面字段 | 应填写/显示 |
| --- | --- |
| 类型 | `VLESS` |
| 地址 | VPS IP 或域名 |
| 端口 | `443`，或你的服务端监听端口 |
| UUID | 必须有值，点眼睛图标可显示 |
| 加密 | `none` 或空 |
| 传输方式 | `none` / `tcp`，不同版本显示不同 |
| TLS | `开启` |
| UDP 转发 | 可开启 |
| 备注 | `jp-tokyo-01` 或你的节点名 |

继续点 `TLS` 进入下一层，重点核对：

| TLS/REALITY 字段 | 应填写/显示 |
| --- | --- |
| TLS | 开启 |
| 允许不安全 | 关闭 |
| SNI / Server Name | 服务端 `serverNames[0]`，例如 `www.microsoft.com` |
| ECH | 留空 |
| ALPN | 可留空 |
| HTTP2 | 可关闭 |
| XTLS | `xtls-rprx-vision` |
| Fingerprint / 指纹 | `chrome` |
| Allow Insecure / 跳过证书验证 | 关闭 |
| Reality / REALITY | 开启 |
| Public Key / 公钥 / PBK | REALITY 公钥，不是私钥 |
| Short ID / SID | 服务端 `shortIds[0]` |
| 片段 / Fragment | 关闭 |
| SpiderX | 可留空或 `/`，通常不影响第一次测试 |

如果 `TLS` 页面里没有看到 REALITY、公钥、Short ID 这类字段，说明导入没有完整识别 REALITY 参数。
这种情况下建议：

1. 关闭 Shadowrocket 顶部总开关。
2. 删除旧节点。
3. 重新复制 `configs/client/shadowrocket_link.txt` 的整行 `vless://...` 链接。
4. 从剪贴板重新导入。

### 无法删除“使用中的配置”

如果看到“使用中的配置无法删除”，先做：

1. 回到 Shadowrocket 首页。
2. 关闭右上角总开关，等 iOS 顶部 VPN 图标消失。
3. 如果仍然无法删除，进入 iPhone 系统设置：`设置 -> VPN 与设备管理 -> VPN`，断开当前 VPN。
4. 回到 Shadowrocket，切到其他配置或默认配置。
5. 再左滑删除节点，或进入节点详情删除。

不要在总开关开启时删除节点；Shadowrocket 会认为当前配置正在使用。

### 你的截图这种页面怎么判断

如果 TLS 页面中能看到：

```text
SNI
XTLS xtls-rprx-vision
公钥
短 ID
片段
```

说明 Shadowrocket 已经识别到 VLESS + XTLS REALITY。
这时第一页看起来像“默认字段”不是问题，真正要排查的是：

1. 公钥是否和服务端私钥匹配。
2. 手机的连接包是否到达 VPS。
3. Shadowrocket 是否真的启用了 VPN。

确认公钥匹配的方法是在 VPS 上执行：

```bash
PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' /usr/local/etc/xray/config.json)
/usr/local/bin/xray x25519 -i "$PRIVATE_KEY"
```

输出中的 `Public key` 必须和 Shadowrocket 的 `公钥` 完全一致。
如果不一致，用新的 `Public key` 重新生成 Shadowrocket 链接并重新导入。

## 16. Shadowrocket 初次连接检查

连接前先确认服务端已经恢复运行。
在 VPS 上执行：

```bash
systemctl status xray --no-pager -l
ss -lntp | grep ":443"
```

在本机先验证 Shadowrocket 链接是否和服务端配置一致：

```bash
bash scripts/validate_shadowrocket_link.sh
```

如果看到：

```text
[done] shadowrocket link validation passed
```

说明链接里的 UUID、端口、flow、SNI、shortId 等字段和本地服务端配置一致。

在手机上连接后，打开 Safari 测试：

```text
https://www.google.com
https://www.youtube.com
https://chat.openai.com
```

如果连接失败：

1. 先确认 Shadowrocket 节点参数里 UUID、公钥、shortId、SNI、flow 是否正确。
2. 再确认 VPS 上 `systemctl status xray` 是否为 `active (running)`。
3. 再看 VPS 日志。
4. 如果 Shadowrocket 显示 `超时`，但本机 `nc -vz <VPS_IP> 443` 成功，优先怀疑 REALITY 公钥不匹配、Shadowrocket 字段导入异常，或手机网络到该 IP/端口不稳定。

也可以在本机运行健康检查脚本：

```bash
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/check_xray_health.sh
```

如果脚本显示本机端口通、服务端 active、链接字段也匹配，但手机仍然超时，继续做“实时连接观察”。

### 实时连接观察

在 VPS 上开一个 SSH 窗口，执行：

```bash
journalctl -u xray -f --no-pager -l
```

然后在手机 Shadowrocket 里关闭再打开连接。
观察是否出现新的 Xray 日志。

判断：

1. 有新日志：手机请求到达了 VPS，继续看日志里的错误类型。
2. 没有任何新日志：手机请求可能没有打到 Xray，检查 Shadowrocket 是否真的启用 VPN、节点是否选中、手机网络是否阻断该 IP/端口。
3. 仍然没有错误但超时：重点检查 REALITY 公钥是否和服务端私钥匹配。

如果需要确认是否有 TCP 包到达 VPS，可以临时安装并使用 `tcpdump`：

```bash
apt-get update
apt-get install -y tcpdump
timeout 20 tcpdump -ni any tcp port 443
```

执行 `tcpdump` 后立刻在手机里点连接。
如果完全没有包，说明手机流量没有到达 VPS；如果有包但 Xray 没成功，继续检查客户端参数。

建议分别测试：

1. 手机使用 5G。
2. 手机切到 Wi-Fi。

如果 Mac 能连通 `<你的_VPS_IP>:443`，但手机 5G 下 `tcpdump` 完全没有包，可能是手机运营商网络到该 IP/端口不通。
如果切到 Wi-Fi 后有包或能连接，说明服务端配置大概率没问题，问题在手机当前网络路径。

## 17. sing-box 初次连接检查

### sing-box VT 导入方式

在 Mac 上：

1. 打开 `sing-box VT`。
2. 进入 `Profiles`。
3. 新建本地 Profile，或导入本地 JSON。
4. 选择本项目生成的 `configs/client/singbox.json`。
5. 回到 `Dashboard`，启用该 Profile。
6. 打开 HTTP Proxy 或系统代理相关开关。

在 iPhone / iPad 上：

1. 确认 App 嵌入的 sing-box core 版本。
2. core 1.11.4：可尝试把 schema-targeted 的 `configs/client/singbox-ios-legacy-1.11.4.json` 传到手机；新核心：传 `configs/client/singbox.json`。
3. 打开 `sing-box VT`。
4. 在 `Profiles` 中导入对应 JSON 文件。
5. 启用 Profile。
6. 首次启用时允许添加 VPN 配置。

不同版本 UI 名称可能略有差异，但核心流程都是：导入 Profile -> 启用 Profile -> 开启代理/VPN。

### 配置兼容性警告

如果客户端提示旧字段或配置不兼容，不要猜测具体版本边界，也不要启用兼容环境变量绕过。嵌入式 core 1.11.4 可尝试 schema-targeted 的 `singbox-ios-legacy-1.11.4.json`；macOS / 新核心继续使用 modern `singbox.json`。重新运行统一刷新入口，并用实际选中的 sing-box 二进制做只读检查：

```bash
bash scripts/validate_client_artifacts.sh
```

modern 模板和默认生成器使用带类型的 DNS server、有效域名解析器以及 route action；legacy 独立模板使用 1.11.x 的 `address` DNS 与 `dns.rules.outbound`。校验通过后，再按 core 版本导入对应文件。导入本身不会自动连接。

legacy 结论依据官方 legacy DNS 文档、迁移/弃用说明，以及 SagerNet `v1.11.4` 标签下的 `option/dns.go`、`option/rule_dns.go` 和 `option/rule_action.go`。这些源码证明目标字段属于该版本 schema，但不替代真实 1.11.4 二进制或设备端运行验证：

- https://sing-box.sagernet.org/configuration/dns/server/legacy/
- https://sing-box.sagernet.org/migration/
- https://sing-box.sagernet.org/deprecated/
- https://github.com/SagerNet/sing-box/tree/v1.11.4/option

### sing-box 配置检查

本机先检查：

```bash
jq empty configs/client/singbox.json
grep -nF '${' configs/client/singbox.json
```

判断：

1. `jq empty` 不报错，说明 JSON 格式正确。
2. `grep -nF '${'` 没有输出，说明没有残留占位符。

先确认 VPS 上 Xray 正在运行：

```bash
systemctl status xray --no-pager -l
```

检查 VPS 是否监听端口：

```bash
ss -lntp | grep ":443"
```

在本机检查端口是否能连通：

```bash
nc -vz <你的_VPS_IP> 443
```

如果端口通，但客户端连接失败，查看 VPS 日志：

```bash
journalctl -u xray -n 80 --no-pager -l
tail -n 80 /var/log/xray/error.log
```

### sing-box 日志：dial tcp VPS:443 i/o timeout

如果 sing-box VT 日志出现类似：

```text
dns: exchange failed ... dial en0 ... dial tcp <VPS_IP>:443: i/o timeout
outbound/vless[node-primary]: outbound connection to 1.1.1.1:443
```

含义：

1. sing-box 已经开始使用 `node-primary` 这个 VLESS 节点。
2. 它尝试连接 VPS 的 `443` 端口。
3. `dial en0` 表示它正在通过 iPhone / iPad 的 Wi-Fi 物理接口出站。
4. `i/o timeout` 表示 TCP 连接 VPS 超时。
5. 这通常还没走到 REALITY 握手阶段，所以优先不是 UUID、公钥、shortId 错误。

下一步要确认手机的 TCP 包有没有到 VPS。

在 VPS 上开一个窗口执行：

```bash
timeout 40 tcpdump -ni any tcp port 443
```

如果提示没有 `tcpdump`，先安装：

```bash
apt-get update
apt-get install -y tcpdump
```

然后马上在手机 sing-box VT 里关闭再开启 Profile。

判断：

1. `tcpdump` 完全没有输出：手机流量没有到达 VPS。切换 Wi-Fi / 5G 再试。
2. 只看到手机发来的 `S` 包，没有返回：VPS 或云厂商防火墙可能没放行，或回程被阻断。
3. 能看到三次握手，但 Xray 没日志：继续看 Xray 监听和配置。
4. 有连接日志但失败：再检查 REALITY 公钥、shortId、SNI、flow。

如果输出长期类似：

```text
enp1s0 In IP <手机出口IP>.<随机端口> > <VPS_IP>.443: Flags [S]
```

并且没有看到类似：

```text
enp1s0 Out IP <VPS_IP>.443 > <手机出口IP>.<随机端口>: Flags [S.]
```

说明 VPS 已经收到手机发来的 TCP SYN，但没有发回 SYN-ACK。
这时不是 UUID、公钥、shortId 的问题，因为 TCP 握手还没完成。优先检查：

1. Xray 是否真的监听 `0.0.0.0:443`。
2. VPS 本机防火墙是否丢弃 443 入站。
3. 云厂商防火墙是否允许 443 入站和出站。
4. 是否有其他程序占用了 443。

在 VPS 上执行：

```bash
echo "== service =="
systemctl status xray --no-pager -l

echo "== listen =="
ss -lntp | grep ':443' || echo "no listener on 443"

echo "== ufw =="
ufw status verbose || true

echo "== nft =="
nft list ruleset 2>/dev/null | sed -n '1,160p' || true

echo "== iptables =="
iptables -S 2>/dev/null || true
iptables -L -n -v 2>/dev/null || true
```

如果 `ss -lntp` 没看到 `0.0.0.0:443` 或 `*:443`，说明 Xray 没有监听 443。
如果有监听但 tcpdump 仍只有 `In` 没有 `Out`，重点看防火墙规则。

如果检查结果类似下面这样：

```text
LISTEN ... *:443 ... users:(("xray",...))
Status: active
Default: deny (incoming)
22/tcp ALLOW IN Anywhere
```

说明 Xray 正在监听，但 UFW 只放行了 SSH，没有放行 Xray 的 443 端口。执行：

```bash
ufw allow proto tcp to any port 443 comment 'resilient-personal-network xray inbound'
ufw reload
ufw status verbose
```

看到 `443/tcp ALLOW IN` 后，再回到 Shadowrocket 或 sing-box 重新连接。

建议做一个对照测试：
保持 VPS 上 `tcpdump` 开着，在 Mac 上执行：

```bash
nc -vz <你的_VPS_IP> 443
```

如果 Mac 的连接能在 `tcpdump` 里出现，而手机连接完全不出现，说明 VPS 没问题，问题在手机当前网络路径或客户端是否真正启用。

## 18. 常见错误

1. UUID 不一致：客户端和服务端 UUID 必须完全一致。
2. 公钥/私钥混用：客户端填公钥，服务端填私钥。
3. shortId 不一致：客户端 `sid` 必须等于服务端 `shortIds` 中的值。
4. serverName 不一致：客户端 `sni` 必须匹配服务端 `serverNames`。
5. 端口不通：检查 VPS 防火墙和云厂商安全组。
6. 配置文件泄露：如果真实链接泄露，应重新生成 UUID 和 REALITY 密钥。
7. `grep` 没检查出占位符：请确认使用的是 `grep -nF '${' configs/client/singbox.json`。
8. 编辑器把模板标红：未替换数字占位符前会标红，替换成数字后再运行 `jq empty`。
9. 买错 App：从可信官方产品页面进入商店并核对发布者，不以本文历史截图为准。
10. 远程服务未恢复：如果 Xray 是 `failed`，先停止客户端刷新并诊断；部署或重启属于远端写操作，必须另行明确授权。
11. 连通性测试超时：先用 `scripts/validate_shadowrocket_link.sh` 检查链接，再看 VPS 日志里是否出现连接记录。
12. 只看第一页字段：VLESS 首页看起来“默认”不代表错，REALITY 关键字段在 `TLS` 里面。
13. 无法删除节点：先关闭 Shadowrocket 总开关和 iOS VPN，再删除。
14. sing-box 兼容性警告：统一刷新后用实际选择的二进制执行 `validate_client_artifacts.sh`，不要启用兼容绕过。

## 19. Mac 端怎么用

这个项目可以在 Mac 电脑端使用并连接。

推荐路线：

1. Mac 上继续用本仓库维护配置、脚本和文档。
2. Mac 代理客户端优先用 sing-box，因为本项目已经有 `templates/singbox_client_template.json`。
3. 如果你的 Mac App Store 能安装 Shadowrocket，也可以尝试用同一个 Shadowrocket 链接导入。
4. Intel Mac 或 Shadowrocket Mac 体验不稳定时，回到 sing-box 路线。

Mac 端连接不是新开一套服务端。
它仍然连接同一台 VPS，只是客户端从 iPhone 换成 Mac。

## 20. 当前推荐顺序

1. 在不改变 VPS 状态的前提下运行统一刷新入口。
2. 执行 `bash scripts/validate_client_artifacts.sh`；通过只代表文件已准备好。
3. 将对应文件导入客户端。
4. 由用户在客户端中手动连接并验证出口。
5. 如果只读健康检查失败，停止并诊断；不要把客户端刷新自动扩大为部署、重启、升级或防火墙修改。

## 21. 本轮不会做什么

1. 不把真实客户端配置提交到 Git。
2. 不生成公开订阅地址。
3. 不自动修改手机或电脑系统代理。
4. 不把本地忽略目录中的真实 UUID、密钥或链接写入受版本控制文件。
