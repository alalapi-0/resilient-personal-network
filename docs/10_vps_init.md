# 10 VPS 初始化说明

本文件说明如何把一台新 VPS 初始化为本项目可管理的节点。
本轮只做基础系统准备，不安装 Xray-core，也不生成真实代理配置。

## 1. 本轮会做什么

执行 `scripts/vps_init.sh` 后，会在 VPS 上完成：

1. 安装基础依赖：`curl`、`wget`、`unzip`、`jq`、`cron`、`tar`、`gzip`、`lsof`、`openssl` 等。
2. 创建远程项目目录：`/opt/resilient-personal-network`。
3. 创建远程子目录：`configs/`、`templates/`、`nodes/`、`logs/`、`backups/`、`scripts/`。
4. 写入初始化日志：`/opt/resilient-personal-network/logs/vps_init.log`。

## 2. 需要你准备的信息

你当前提供的信息是：

| 项目 | 当前值 | 是否写入仓库 |
| --- | --- | --- |
| VPS IP | 已通过运行时输入提供 | 不写入 |
| SSH 用户 | `root` | 不写入 |
| SSH 端口 | `22` | 不写入 |
| 域名 | 暂无 | 不写入 |

仓库文件只保留占位符。真实 IP、域名、密钥、密码不要提交到 Git。

如果你还没有在当前电脑配置 SSH 密钥，或者 Windows 第一次连接 VPS 时出现 `Host key verification failed`，先看 `docs/26_ssh_key_and_vps_trust.md`。
那份文档会说明不同系统如何生成本机密钥、把公钥写入 VPS、完成 `known_hosts` 首次信任。

## 3. 推荐运行方式

在本机仓库根目录执行：

下面是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。
如果你在 Windows PowerShell 里操作，请使用 `$env:VPS_HOST="..."` 写法，完整示例见 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/vps_init.sh
```

如果不想把 IP 写在命令里，也可以直接执行：

```bash
bash scripts/vps_init.sh
```

脚本会暂停并提示你输入 VPS IP 或域名。

## 4. 关于“还要输入一次本机密码”

如果你已经配置好 SSH 登录，但每次登录仍需要输入一次密码，常见原因有两类：

1. SSH 私钥本身设置了密码短语。
2. macOS 钥匙串或系统安全策略要求你确认一次。

这通常不是 VPS 的 root 密码，也不应该写进脚本。
脚本不会读取、保存或记录这个密码；你只需要按终端提示输入即可。

如果你希望本次会话内不再重复输入私钥密码，可以先运行：

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

系统会要求你输入一次私钥密码。成功后，再运行初始化脚本。
如果你的 macOS 不支持 `--apple-use-keychain`，可以使用：

```bash
ssh-add ~/.ssh/id_ed25519
```

Windows PowerShell、Linux、WSL 和 Git Bash 的密钥加载方式不同，详见 `docs/26_ssh_key_and_vps_trust.md`。

## 5. 初始化后如何检查

初始化完成后，可以运行：

```bash
ssh -p 22 root@<你的_VPS_IP>
```

登录 VPS 后检查目录：

```bash
ls -la /opt/resilient-personal-network
cat /opt/resilient-personal-network/logs/vps_init.log
```

如果能看到目录和日志，说明 Round 1 的 VPS 基础初始化成功。

## 6. 如果卡在 apt-get update

如果终端长时间停在类似下面的输出：

```text
Get:22 http://security.ubuntu.com/ubuntu jammy-security InRelease
```

这通常表示 VPS 正在等待 Ubuntu 软件源响应。可能原因包括：

1. VPS 到 Ubuntu 安全源的网络较慢。
2. 软件源临时不可用。
3. IPv6 路由异常。

新版 `scripts/vps_init.sh` 已加入：

1. `Acquire::ForceIPv4=true`，优先使用 IPv4。
2. `Acquire::Retries=3`，下载失败时自动重试。
3. 下载超时限制，避免无限等待。
4. 单次 SSH 连接，减少重复输入私钥密码。

如果你确认 5 分钟以上完全没有新输出，可以按 `Control + C` 停止，然后重新执行初始化命令。

## 7. 域名暂时没有怎么办

没有域名不影响 Round 1。
Round 1 只需要 SSH 能连上 VPS。

后续 Round 2/3 如果使用 VLESS + REALITY，可以先用 IP 做基础连通性测试；如果后续要做更稳定的长期访问，建议准备一个域名，并在 DNS 中添加一条 A 记录指向 VPS IP。

## 8. 本轮不会做什么

1. 不安装 Xray-core。
2. 不创建真实代理账号。
3. 不生成真实客户端链接。
4. 不写入真实密钥或密码。
5. 不改变 SSH 端口或防火墙策略。
