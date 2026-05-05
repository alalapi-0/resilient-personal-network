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
grep -n '\\${' configs/server/config.json
```

如果没有输出，说明占位符已经替换完。

## 7. 上传配置到 VPS

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

## 8. 启动服务端

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

## 9. 常见问题：permission denied

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

## 10. 本轮不会做什么

1. 不生成真实客户端链接。
2. 不把 UUID、私钥或 shortId 写进仓库。
3. 不自动开放云厂商安全组。
4. 不配置域名解析。
5. 不保证客户端已经可连接，客户端配置将在 Round 3 完成。
