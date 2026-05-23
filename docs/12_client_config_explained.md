# 12 客户端配置说明

本文件说明如何使用 Round 3 生成的客户端模板。
本轮目标是让你能把服务端参数填入 sing-box 或 Shadowrocket，并进行第一次连接检查。

## 1. 本轮生成的文件

1. `templates/singbox_client_template.json`：sing-box 客户端配置模板。
2. `templates/client_link_template.txt`：Shadowrocket / 通用 VLESS 导入链接模板。

模板中只包含占位符，不包含真实 UUID、公钥、shortId 或服务器地址。

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

推荐用脚本生成配置，减少手工替换出错。

前提：

1. 本地 `configs/server/config.json` 已通过校验。
2. 你知道 REALITY 公钥，也就是 `xray x25519` 输出中的 Public key。
3. VPS 上 Xray 已经是 `active (running)`。

在本机仓库根目录执行：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
bash scripts/generate_singbox_config.sh
```

默认会生成 `tun` 模式配置，适合 sing-box VT 在 iPhone / iPad / Mac 上作为 VPN Profile 使用。
如果你只想在 Mac 上手动设置本机 HTTP/SOCKS 代理，可以改用：

```bash
SINGBOX_MODE="mixed" \
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
bash scripts/generate_singbox_config.sh
```

脚本会生成：

```text
configs/client/singbox.json
```

这个文件已被 `.gitignore` 忽略，不会提交到 Git。
它包含真实节点信息，不要截图或公开发送。

如果你想手动生成，也可以按下面流程操作。

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
默认走 `proxy`。这适合初次连接测试，后续可改成更细的分流规则。

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

如果你忘记保存 public key 或 shortId，不要猜。需要重新生成并同步更新服务端和客户端。

如果只是不确定公钥在哪里，先回忆或查找当时执行 `/usr/local/bin/xray x25519` 的输出记录。
公钥不能从服务端 `privateKey` 文本里直接“看出来”。如果确实找不到公钥，需要重新生成一对 REALITY 密钥，并同步更新：

1. 服务端 `privateKey`。
2. 客户端 `public_key` 或 Shadowrocket 链接里的 `pbk`。
3. 然后重新部署服务端配置并重新生成客户端链接。

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

sing-box 在 Apple 平台上常见的可用客户端是 `sing-box VT`。
你截图中的 App 看起来是正确的：

| 检查项 | 应看到的内容 |
| --- | --- |
| App 名称 | `sing-box VT` |
| 开发者 | `VIRAL TECH, INC.` |
| 分类 | `Utilities` / 工具类 |
| 支持设备 | Mac、iPad、iPhone、Apple TV |
| 图标 | 深色方块图标 |

官方 App Store 页面显示 `sing-box VT` 的开发者为 `VIRAL TECH, INC.`，并支持 iPhone、iPad、Mac、Apple TV。
所以你截图里的这个 App 可以用于本项目。

## 11. 如何确认 Shadowrocket App 是否买对

官方 App Store 页面应满足以下特征：

| 检查项 | 应看到的内容 |
| --- | --- |
| App 名称 | `Shadowrocket` |
| 开发者 | `Shadow Launch Technology Limited` |
| 分类 | `Utilities` / 工具类 |
| 图标 | 白底、蓝紫色火箭 |
| 价格 | 不同区服价格不同，日区约 `500` 日元是合理范围 |

你的截图里第一项显示：

1. 名称是 `Shadowrocket`。
2. 开发者显示为 `Shadow Launch Technolo...`。
3. 图标是蓝紫色火箭。
4. 按钮是 `開く`，表示已经安装。

这看起来是正确的 Shadowrocket。
下面的 Trend Micro VPN 是广告，不是本项目要用的客户端。
下面那个带中文副标题、显示“App 内购买”的 `Shadowrocket-小火箭 VPN...` 不要安装，它不是我们要配置的那个。

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

查看链接：

```bash
cat configs/client/shadowrocket_link.txt
```

然后把整行 `vless://...` 复制到 iPhone。

## 14. Shadowrocket 导入方式

打开 `templates/client_link_template.txt`，复制其中的 `vless://...` 链接模板。

如果你已经使用脚本生成了 `configs/client/shadowrocket_link.txt`，直接复制该文件里的真实链接即可。

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

1. 把 `configs/client/singbox.json` 传到手机，例如 AirDrop、iCloud Drive 或文件 App。
2. 打开 `sing-box VT`。
3. 在 `Profiles` 中导入该 JSON 文件。
4. 启用 Profile。
5. 首次启用时允许添加 VPN 配置。

不同版本 UI 名称可能略有差异，但核心流程都是：导入 Profile -> 启用 Profile -> 开启代理/VPN。

### 弃用警告是什么意思

如果 sing-box VT 弹出：

```text
legacy special outbounds 已在 sing-box 1.11.0 中被弃用
```

这不是 VPS 服务端错误，而是客户端 JSON 使用了旧版 sing-box 配置写法。
旧模板里包含 `type: "block"` 这种 special outbound，sing-box 官方迁移文档说明它应改成 rule action。
本项目已更新：

1. 移除旧的 `block` 出站。
2. 默认生成 `tun` 入站，适合 Apple 平台的 VPN Profile。
3. 使用 `action: "sniff"` 和 `action: "hijack-dns"`，避免旧写法警告。

看到这个警告时，重新生成并导入配置：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
bash scripts/generate_singbox_config.sh
```

然后在 sing-box VT 里删除旧 Profile，重新导入新的 `configs/client/singbox.json`。

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
9. 买错 App：只认 `Shadowrocket` + `Shadow Launch Technology Limited`，不要安装广告位或名字相似的 VPN。
10. 远程服务未恢复：如果 Xray 是 `failed`，客户端一定连不上，先运行 `scripts/deploy_xray_config.sh` 恢复服务端。
11. 连通性测试超时：先用 `scripts/validate_shadowrocket_link.sh` 检查链接，再看 VPS 日志里是否出现连接记录。
12. 只看第一页字段：VLESS 首页看起来“默认”不代表错，REALITY 关键字段在 `TLS` 里面。
13. 无法删除节点：先关闭 Shadowrocket 总开关和 iOS VPN，再删除。
14. sing-box 弃用警告：重新生成最新 `tun` 配置，不要继续使用旧 `block` 出站模板。

## 19. Mac 端怎么用

这个项目可以在 Mac 电脑端使用并连接。

推荐路线：

1. Mac 上继续用本仓库维护配置、脚本和文档。
2. Mac 代理客户端优先用 sing-box，因为本项目已经有 `templates/singbox_client_template.json`。
3. 如果你的 Mac App Store 能安装 Shadowrocket，也可以尝试用同一个 Shadowrocket 链接导入。
4. Intel Mac 或 Shadowrocket Mac 体验不稳定时，回到 sing-box 路线。

Mac 端连接不是新开一套服务端。
它仍然连接同一台 VPS，只是客户端从 iPhone 换成 Mac。

## 20. 后续大概还有几个轮次

按当前项目状态，最少还需要 3 个轮次完成可长期维护版本：

1. Round 4：服务端健康检查、端口检查、日志检查脚本。
2. Round 5：备份与恢复，防止配置改坏后无法回滚。
3. Round 6：多节点与故障切换，为第二台 VPS 做准备。

如果你只想先能用，当前只差两步：

1. 用 `scripts/deploy_xray_config.sh` 把本地正确服务端配置部署到 VPS，让 Xray 恢复 `active (running)`。
2. 生成 Shadowrocket 链接并导入手机。

## 21. 本轮不会做什么

1. 不把真实客户端配置提交到 Git。
2. 不生成公开订阅地址。
3. 不自动修改手机或电脑系统代理。
4. 不替你保存真实 UUID、密钥或链接。
