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
| `${XRAY_UUID}` | `xray uuid` | 必须与服务端 `clients[0].id` 一致 |
| `${XRAY_FLOW}` | 服务端配置 | 通常是 `xtls-rprx-vision` |
| `${XRAY_SERVER_NAME}` | 服务端 REALITY 配置 | 必须与服务端 `serverNames` 一致 |
| `${XRAY_REALITY_PUBLIC_KEY}` | `xray x25519` 输出 | 客户端使用公钥，不使用私钥 |
| `${XRAY_REALITY_SHORT_ID}` | 服务端配置 | 必须与服务端 `shortIds` 一致 |
| `${CLIENT_FINGERPRINT}` | 客户端设置 | 通常使用 `chrome` |
| `${NODE_NAME}` | 自定义 | 例如 `jp-tokyo-01` |

注意：REALITY 的 `${XRAY_SERVER_NAME}` 不是你的 VPS IP。  
它通常是服务端配置里的伪装目标域名，例如 `www.microsoft.com`。

## 3. sing-box 配置生成

复制模板到本地真实配置文件：

```bash
cp templates/singbox_client_template.json configs/client/singbox.json
```

然后编辑 `configs/client/singbox.json`，替换所有 `${...}` 占位符。

替换完成后检查是否还有占位符：

```bash
grep -n '\\${' configs/client/singbox.json
```

如果没有输出，说明占位符替换完毕。

再检查 JSON 格式：

```bash
jq empty configs/client/singbox.json
```

如果没有报错，说明 JSON 格式正确。

## 4. sing-box 字段解释

`mixed-in`：
本地混合代理入口。默认监听 `127.0.0.1:${SINGBOX_MIXED_PORT}`，浏览器或系统代理可以指向这个端口。

`node-primary`：
你的主节点。里面的 `server`、`server_port`、`uuid`、`flow`、`server_name`、`public_key`、`short_id` 必须与服务端匹配。

`proxy`：
节点选择器。当前模板只放了一个主节点和 `direct`，以后可以追加备用节点。

`route.final`：
默认走 `proxy`。这适合初次连接测试，后续可改成更细的分流规则。

## 5. 多节点如何扩展

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

## 6. Shadowrocket 导入方式

打开 `templates/client_link_template.txt`，复制其中的 `vless://...` 链接模板。

把所有 `${...}` 占位符替换成真实值后：

1. 在 iPhone 上复制完整链接。
2. 打开 Shadowrocket。
3. 点击右上角 `+`。
4. 选择从剪贴板或 URL 导入。
5. 保存节点。
6. 选择该节点并连接。

生成后的真实链接不要提交到 Git，也不要公开分享。

## 7. 初次连接检查

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

## 8. 常见错误

1. UUID 不一致：客户端和服务端 UUID 必须完全一致。
2. 公钥/私钥混用：客户端填公钥，服务端填私钥。
3. shortId 不一致：客户端 `sid` 必须等于服务端 `shortIds` 中的值。
4. serverName 不一致：客户端 `sni` 必须匹配服务端 `serverNames`。
5. 端口不通：检查 VPS 防火墙和云厂商安全组。
6. 配置文件泄露：如果真实链接泄露，应重新生成 UUID 和 REALITY 密钥。

## 9. 本轮不会做什么

1. 不把真实客户端配置提交到 Git。
2. 不生成公开订阅地址。
3. 不自动修改手机或电脑系统代理。
4. 不替你保存真实 UUID、密钥或链接。
