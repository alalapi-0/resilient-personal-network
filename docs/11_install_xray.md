# 11 Xray 安装与服务端配置模板

本文件说明 Round 2 的内容：安装 Xray-core，并准备 VLESS + REALITY 服务端配置模板。  
本轮仍然不把真实 UUID、私钥、域名或客户端链接写进仓库。

## 1. 本轮会做什么

1. 使用 `scripts/install_xray.sh` 在 VPS 上安装 Xray-core。
2. 在 VPS 上创建 systemd 服务文件：`/etc/systemd/system/xray.service`。
3. 生成配置模板：`templates/xray_server_vless_reality.json.template`。
4. 说明如何替换占位符、上传配置并启动服务。

默认情况下，安装脚本不会启动 Xray 服务。  
原因是服务必须读取真实配置文件 `/usr/local/etc/xray/config.json`，而仓库中只保存模板。

## 2. 安装 Xray-core

在本机仓库根目录执行：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/install_xray.sh
```

如果想安装指定版本，可以加上：

```bash
XRAY_VERSION="v版本号"
```

不指定时，脚本会从 Xray-core GitHub 最新发布版下载对应系统架构的安装包。

## 3. 安装后如何检查

登录 VPS：

```bash
ssh -p 22 root@<你的_VPS_IP>
```

检查 Xray 是否安装：

```bash
/usr/local/bin/xray version
systemctl status xray --no-pager
cat /opt/resilient-personal-network/logs/xray_install.log
```

如果能看到 Xray 版本和安装日志，说明程序安装成功。  
此时服务可能是 `inactive` 或 `failed`，只要还没有上传真实 `config.json`，这是可以接受的。

## 4. 配置模板字段说明

模板文件路径：

```text
templates/xray_server_vless_reality.json.template
```

主要占位符如下：

| 占位符 | 含义 | 示例 |
| --- | --- | --- |
| `${XRAY_PORT}` | 服务端监听端口 | `443` |
| `${XRAY_UUID}` | 客户端身份 UUID | 使用 `xray uuid` 生成 |
| `${XRAY_FLOW}` | VLESS flow | `xtls-rprx-vision` |
| `${XRAY_CLIENT_NAME}` | 客户端备注名 | `macbook` |
| `${XRAY_REALITY_PRIVATE_KEY}` | REALITY 服务端私钥 | 使用 `xray x25519` 生成 |
| `${XRAY_REALITY_SHORT_ID}` | REALITY shortId | 8 到 16 位十六进制字符串 |
| `${XRAY_REALITY_DEST}` | REALITY 伪装目标 | `www.microsoft.com:443` |
| `${XRAY_SERVER_NAME}` | REALITY serverName | `www.microsoft.com` |
| `${XRAY_LOG_LEVEL}` | 日志等级 | `warning` |

### 推荐第一次填写值

如果只是先跑通第一台 VPS，下面这些值可以直接按推荐填：

| 占位符 | 推荐填写 | 是否加引号 | 说明 |
| --- | --- | --- | --- |
| `${XRAY_LOG_LEVEL}` | `warning` | 模板已有引号 | 日志等级，先用 `warning`，排障时可改 `info` 或 `debug` |
| `${XRAY_PORT}` | `443` | 不加引号 | 服务端监听端口，必须是数字 |
| `${XRAY_FLOW}` | `xtls-rprx-vision` | 模板已有引号 | VLESS + REALITY 常用 flow |
| `${XRAY_CLIENT_NAME}` | `macbook` 或 `iphone` | 模板已有引号 | 只是备注名，便于以后区分客户端 |
| `${XRAY_REALITY_DEST}` | `www.microsoft.com:443` | 模板已有引号 | REALITY 伪装目标，格式是 `域名:端口` |
| `${XRAY_SERVER_NAME}` | `www.microsoft.com` | 模板已有引号 | 必须与上面的域名部分一致，不带 `:443` |

下面这些值必须用命令生成或从已有配置中复制，不能乱填：

| 占位符 | 获取方式 | 服务端/客户端 |
| --- | --- | --- |
| `${XRAY_UUID}` | `/usr/local/bin/xray uuid` | 服务端和客户端都要填同一个 |
| `${XRAY_REALITY_PRIVATE_KEY}` | `/usr/local/bin/xray x25519` 输出的 Private key | 只填服务端 |
| `${XRAY_REALITY_PUBLIC_KEY}` | `/usr/local/bin/xray x25519` 输出的 Public key | 只填客户端 |
| `${XRAY_REALITY_SHORT_ID}` | `openssl rand -hex 8` | 服务端和客户端都要填同一个 |

### 替换规则

替换时要替换整个 `${...}`，不要保留 `${` 和 `}`。

错误示例：

```json
"loglevel": "${warning}",
"port": "${443}",
"id": "${真实UUID}"
```

正确示例：

```json
"loglevel": "warning",
"port": 443,
"id": "真实UUID"
```

注意：`port` 是数字字段，所以正确写法是 `443`，不是 `"443"`。

### 你问到的字段逐个解释

`"loglevel": "${XRAY_LOG_LEVEL}"`：
填 Xray 日志等级。第一次建议填 `"warning"`。如果排查问题，可以改成 `"info"` 或 `"debug"`。

`"port": ${XRAY_PORT}`：
填 Xray 服务端监听端口。第一次建议填 `443`。这个字段是数字，不能加引号。

`"flow": "${XRAY_FLOW}"`：
填 VLESS flow。当前模板建议填 `"xtls-rprx-vision"`，客户端也必须填同样的值。

`"email": "${XRAY_CLIENT_NAME}"`：
填客户端备注名，不是真实邮箱也可以。建议填 `"macbook"`、`"iphone"`、`"client-01"` 这类容易识别的名字。

`"dest": "${XRAY_REALITY_DEST}"`：
填 REALITY 伪装目标，格式是 `域名:端口`。第一次建议保留模板思路，填 `"www.microsoft.com:443"`。

`"${XRAY_SERVER_NAME}"`：
填 REALITY serverName，也就是上面 `dest` 的域名部分，不带端口。  
如果 `dest` 是 `"www.microsoft.com:443"`，这里就填 `"www.microsoft.com"`。

## 5. 如何生成 UUID 和 REALITY 密钥

登录 VPS 后执行：

```bash
/usr/local/bin/xray uuid
/usr/local/bin/xray x25519
openssl rand -hex 8
```

含义：

1. `xray uuid`：生成一个客户端 UUID。
2. `xray x25519`：生成 REALITY 私钥和公钥。
3. `openssl rand -hex 8`：生成 shortId。

请注意：

1. 私钥只放在服务端配置中。
2. 公钥后续给客户端使用。
3. UUID、私钥、公钥、shortId 都不要提交到 Git。

## 6. 如何从模板生成真实配置

建议复制模板到一个不会提交的本地文件：

```bash
cp templates/xray_server_vless_reality.json.template configs/server/config.json
```

然后用编辑器把 `${...}` 占位符替换成真实值。  
`configs/server/*.json` 已在 `.gitignore` 中忽略，避免误提交真实配置。

替换完成后，先在本机检查是否还有占位符：

```bash
grep -nF '${' configs/server/config.json
```

如果没有输出，说明占位符已经替换完。

再运行专用校验脚本：

```bash
bash scripts/validate_xray_config.sh configs/server/config.json
```

看到下面输出才说明本地服务端配置通过基础检查：

```text
[done] xray config validation passed
```

## 7. 上传配置到 VPS

上传前必须先在本机验证。完整流程如下：

```bash
grep -nF '${' configs/server/config.json
jq empty configs/server/config.json
bash scripts/validate_xray_config.sh configs/server/config.json
```

判断标准：

1. `grep -nF '${'` 没有输出，说明没有残留占位符。
2. `jq empty` 没有报错，说明 JSON 格式正确。
3. `validate_xray_config.sh` 输出 `[done] xray config validation passed`。

如果任意一步失败，不要上传到 VPS。

推荐使用部署脚本上传配置。它会自动完成：

1. 本地配置校验。
2. 上传到 VPS 临时路径。
3. 远程再次检查占位符和 JSON。
4. 备份旧配置到 `/opt/resilient-personal-network/backups/`。
5. 设置 `root:xray` + `640` 权限。
6. 如果 VPS 启用了 UFW，则自动放行配置里的 TCP 监听端口。
7. 重启 Xray 并显示状态。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/deploy_xray_config.sh
```

如果你要手动上传，再使用下面的 `scp` 方式。

```bash
scp -P 22 configs/server/config.json root@<你的_VPS_IP>:/usr/local/etc/xray/config.json
```

登录 VPS 后设置权限：

```bash
chown root:xray /usr/local/etc/xray/config.json
chmod 640 /usr/local/etc/xray/config.json
chmod 755 /usr/local/etc/xray
```

原因：`xray.service` 默认以 `xray` 用户运行。  
如果配置文件是 `root:root` + `600`，服务进程会读不到配置，并在日志中出现 `permission denied`。

可以用下面的命令确认 `xray` 用户能读取配置：

```bash
su -s /bin/sh -c 'test -r /usr/local/etc/xray/config.json && echo readable' xray
```

## 8. 放行 VPS 防火墙端口

Xray 服务启动成功，只代表程序在 VPS 上跑起来了。  
如果 VPS 本机防火墙没有放行入站端口，手机仍然会连接超时。

本项目的部署脚本会在发现 UFW 已启用时自动执行等价于下面的动作：

```bash
ufw allow proto tcp to any port 443 comment 'resilient-personal-network xray inbound'
```

如果你手动部署，或者想自己确认，可以登录 VPS 后执行：

```bash
ufw status verbose
ss -lntp | grep ':443'
```

你需要同时看到：

1. `ss` 中有 `xray` 监听 `*:443` 或 `0.0.0.0:443`。
2. `ufw status` 中有 `443/tcp ALLOW IN`。

如果 UFW 只显示 `22/tcp ALLOW IN`，说明只开放了 SSH，客户端连接 443 会超时。

## 9. 启动服务端

登录 VPS 后执行：

```bash
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
systemctl status xray --no-pager
```

查看日志：

```bash
journalctl -u xray -n 80 --no-pager
tail -n 80 /var/log/xray/error.log
```

如果状态为 `active (running)`，说明服务端启动成功。

## 10. 常见问题：permission denied

如果看到：

```text
failed to read config
open /usr/local/etc/xray/config.json: permission denied
```

说明服务进程没有权限读取配置文件。执行：

```bash
chown root:xray /usr/local/etc/xray/config.json
chmod 640 /usr/local/etc/xray/config.json
chmod 755 /usr/local/etc/xray
systemctl restart xray
systemctl status xray --no-pager -l
```

## 11. 常见问题：443 超时但 Xray 正在运行

如果客户端日志出现：

```text
dial tcp <VPS_IP>:443: i/o timeout
```

并且 VPS 上 `systemctl status xray` 是 `active (running)`，先检查防火墙：

```bash
ufw status verbose
ss -lntp | grep ':443'
```

如果 `ss` 显示 Xray 正在监听，但 `ufw` 只允许 `22/tcp`，执行：

```bash
ufw allow proto tcp to any port 443 comment 'resilient-personal-network xray inbound'
ufw reload
ufw status verbose
```

然后重新在客户端连接。

## 12. 本轮不会做什么

1. 不生成真实客户端链接。
2. 不把 UUID、私钥或 shortId 写进仓库。
3. 不自动开放云厂商安全组。
4. 不配置域名解析。
5. 不保证客户端已经可连接，客户端配置将在 Round 3 完成。
