# resilient-personal-network

## 项目名称
**resilient-personal-network**（个人网络通道韧性管理仓库）

## 项目定位
这是一个长期维护型工程仓库，用于管理个人多节点网络通道的**文档、配置模板、脚本与运维流程**。  
本项目强调“工程化管理”，而不是“一次性脚本执行后就不再维护”。

## 当前阶段
当前处于 **Round 3（客户端配置模板与初步连接阶段）**：
- 已建立目录结构与基础文档。
- 已完成 VPS 基础初始化。
- 已完成 Xray 服务端安装与启动。
- 已准备 sing-box / Shadowrocket 客户端配置模板。
- 真实客户端配置需要用户在本地替换占位符后导入。

## 本项目不做什么
为了保证后续可控迭代，本轮明确不做以下事情：
1. 不把真实密钥写入仓库。
2. 不生成公开可分发的订阅链接。
3. 不写入真实服务器 IP、域名、UUID、私钥、订阅链接。
4. 不在配置模板中保存可直接连接的敏感信息。

## 目录结构说明
```text
resilient-personal-network/
├── README.md
├── .gitignore
├── .env.example
├── docs/
│   ├── 00_project_overview.md
│   ├── 01_terms.md
│   ├── 02_architecture.md
│   ├── 03_security_notes.md
│   ├── 10_vps_init.md
│   ├── 11_install_xray.md
│   ├── 12_client_config_explained.md
│   └── round_notes.md
├── scripts/
│   ├── init_project.sh
│   ├── snapshot_tree.sh
│   ├── vps_init.sh
│   └── install_xray.sh
├── configs/
│   ├── server/
│   │   └── .gitkeep
│   └── client/
│       └── .gitkeep
├── templates/
│   ├── xray_server_vless_reality.json.template
│   ├── singbox_client_template.json
│   ├── client_link_template.txt
│   └── .gitkeep
├── nodes/
│   └── .gitkeep
├── logs/
│   └── .gitkeep
└── backups/
    └── .gitkeep
```

## 初始化方式
在仓库根目录执行：

```bash
bash scripts/init_project.sh
```

该脚本会：
- 按需创建标准目录与基础文件；
- 遇到已存在文件/目录时仅提示，不覆盖；
- 最后输出初始化完成信息。

## 快照生成方式
在仓库根目录执行：

```bash
bash scripts/snapshot_tree.sh
```

然后查看快照：

```bash
cat docs/tree_snapshot.txt
```

## 如何准备 VPS
你需要先在云厂商处创建一台 Linux VPS，并确认以下信息：

1. VPS 公网 IP 或已经解析好的域名。
2. SSH 登录用户，常见为 `root`。
3. SSH 端口，默认通常为 `22`。
4. 本机可以通过 SSH 登录 VPS。

本项目不会保存 SSH 密码。若你的私钥设置了密码短语，终端可能会要求你输入一次本机私钥密码或钥匙串密码，这是正常现象。

如需把私钥加入本机会话的 SSH agent，可先运行：

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

## VPS 初始化方式
在仓库根目录执行：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/vps_init.sh
```

脚本会在 VPS 上安装基础依赖，并创建 `/opt/resilient-personal-network` 目录结构。  
详细说明请看 `docs/10_vps_init.md`。

如果卡在 Ubuntu 软件源下载阶段超过 5 分钟没有任何输出，可以按 `Control + C` 停止后重试；脚本已配置 IPv4、超时和重试参数。

## 域名注册和 DNS 配置提示
当前没有域名也可以完成 Round 1。后续建议准备一个域名，用于长期维护与迁移。

如果你准备了域名，通常需要在 DNS 服务商后台添加：

```text
类型：A
主机记录：@ 或 node
记录值：<你的_VPS_IP>
TTL：默认即可
```

DNS 生效后，可以用以下命令检查：

```bash
dig <你的域名>
```

## 安装 Xray-core
在仓库根目录执行：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/install_xray.sh
```

脚本会在 VPS 上安装 Xray-core，并写入 systemd 服务文件。  
默认不会启动服务，因为真实配置需要先由模板生成。

详细说明请看 `docs/11_install_xray.md`。

## 上传配置到 VPS
先复制模板到本地真实配置文件：

```bash
cp templates/xray_server_vless_reality.json.template configs/server/config.json
```

替换所有 `${...}` 占位符后上传：

```bash
scp -P 22 configs/server/config.json root@<你的_VPS_IP>:/usr/local/etc/xray/config.json
```

登录 VPS 后设置权限，让 `xray` 服务进程可以读取配置：

```bash
chown root:xray /usr/local/etc/xray/config.json
chmod 640 /usr/local/etc/xray/config.json
chmod 755 /usr/local/etc/xray
```

## 启动服务端方法
登录 VPS 后执行：

```bash
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
systemctl status xray --no-pager
```

## 客户端配置导入方法
sing-box 客户端：

```bash
cp templates/singbox_client_template.json configs/client/singbox.json
```

替换 `configs/client/singbox.json` 中所有 `${...}` 占位符，然后检查：

```bash
grep -n '\\${' configs/client/singbox.json
jq empty configs/client/singbox.json
```

Shadowrocket 客户端：

1. 打开 `templates/client_link_template.txt`。
2. 复制 `vless://...` 模板。
3. 替换所有 `${...}` 占位符。
4. 在 Shadowrocket 中从剪贴板或 URL 导入。

详细说明请看 `docs/12_client_config_explained.md`。

## 初次连接检查
登录 VPS 后确认服务运行：

```bash
systemctl status xray --no-pager -l
ss -lntp | grep ":443"
```

在本机检查端口连通：

```bash
nc -vz <你的_VPS_IP> 443
```

如果端口通但客户端连不上，优先检查 UUID、公钥、shortId、serverName 和 flow 是否与服务端一致。

## 后续轮次简介
1. **Round 1：VPS 初始化脚本与文档**
   - 生成 `scripts/vps_init.sh`。
   - 说明如何准备 VPS、SSH、域名和 DNS。
   - 在需要真实 VPS IP、SSH 用户、端口或密码时提示用户输入并暂停。
2. **Round 2：服务端安装与配置模板**
   - 生成 `scripts/install_xray.sh`。
   - 生成 VLESS + REALITY 服务端配置模板。
   - 所有 UUID、密钥、IP、域名都使用 `.env` 或占位符。
3. **Round 3：客户端配置模板与初步连接**
   - 生成 sing-box / Shadowrocket 客户端配置模板。
   - 说明如何替换占位符、导入客户端并进行初次连接检查。
4. **后续轮次：备份、巡检与故障切换**
   - 逐步增加节点备份、健康检查、日志分析和多节点故障切换流程。

## 安全提醒
- 真实敏感数据只允许通过 `.env`（本地）或安全凭据系统管理。
- 仓库中仅保留模板与占位符。
- 提交前务必检查 `git diff`，避免泄露真实地址、密钥和链接。

## Round 0 验收命令
请按顺序执行以下命令：

```bash
bash scripts/init_project.sh
bash scripts/snapshot_tree.sh
cat docs/tree_snapshot.txt
```

若命令均成功，且 `docs/tree_snapshot.txt` 可读，则 Round 0 骨架验收通过。

## Round 1 验收命令
请按顺序执行：

```bash
bash scripts/vps_init.sh
ssh -p 22 root@<你的_VPS_IP>
ls -la /opt/resilient-personal-network
cat /opt/resilient-personal-network/logs/vps_init.log
```

若能看到远程目录和初始化日志，则 Round 1 验收通过。

## Round 2 验收命令
请按顺序执行：

```bash
bash scripts/install_xray.sh
ssh -p 22 root@<你的_VPS_IP>
/usr/local/bin/xray version
cat /opt/resilient-personal-network/logs/xray_install.log
```

若能看到 Xray 版本和安装日志，则 Round 2 的程序安装部分通过。  
真实配置上传和服务启动，请按 `docs/11_install_xray.md` 操作。

## Round 3 验收命令
请按顺序执行：

```bash
cp templates/singbox_client_template.json configs/client/singbox.json
grep -n '\\${' configs/client/singbox.json
jq empty configs/client/singbox.json
```

注意：复制后需要先替换所有 `${...}` 占位符。  
替换完成后，`grep` 没有输出且 `jq` 不报错，则客户端配置文件格式通过。  
导入客户端并能连接节点，则 Round 3 初步连接验收通过。
