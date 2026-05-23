# resilient-personal-network

## 项目名称
**resilient-personal-network**（个人网络通道韧性管理仓库）

## 项目定位
这是一个长期维护型工程仓库，用于管理个人多节点网络通道的**文档、配置模板、脚本与运维流程**。
本项目强调“工程化管理”，而不是“一次性脚本执行后就不再维护”。

## 当前阶段
当前处于 **多系统接入与操作说明整理阶段**：
- 已建立目录结构与基础文档。
- 已完成 VPS 基础初始化。
- 已完成 Xray 服务端安装与启动。
- 已准备 sing-box / Shadowrocket 客户端配置模板。
- 已完成 iPhone sing-box VT 实机连接验收。
- 已完成健康检查、远程备份、诊断采集和恢复流程。
- 已补齐 Mac 端导入、授权、验证和排障流程。
- 已补齐 Windows v2rayN 配置包和 PowerShell 操作说明。
- 已把 macOS、Windows、Linux/VPS 的命令写法拆分清楚，避免跨系统复制出错。

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
│   ├── 20_operations_runbook.md
│   ├── 21_macos_client_setup.md
│   ├── 22_windows_client_setup.md
│   ├── 23_windows_one_click_bundle.md
│   ├── 24_maintenance_schedule.md
│   ├── 25_cross_platform_command_guide.md
│   ├── 26_ssh_key_and_vps_trust.md
│   └── round_notes.md
├── scripts/
│   ├── init_project.sh
│   ├── snapshot_tree.sh
│   ├── vps_init.sh
│   ├── install_xray.sh
│   ├── validate_xray_config.sh
│   ├── deploy_xray_config.sh
│   ├── fetch_remote_xray_config.sh
│   ├── generate_shadowrocket_link.sh
│   ├── generate_singbox_config.sh
│   ├── validate_shadowrocket_link.sh
│   ├── check_xray_health.sh
│   ├── backup_remote_xray.sh
│   ├── restore_remote_xray_config.sh
│   ├── collect_remote_diagnostics.sh
│   ├── check_macos_singbox.sh
│   ├── copy_shadowrocket_link_macos.sh
│   ├── prepare_windows_vless_link.sh
│   ├── windows_generate_vless_link_from_vps.ps1
│   └── build_windows_client_bundle.sh
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

## 先分清系统和终端
本项目同时涉及本机仓库、Windows 客户端和 VPS 远程 Linux。不同终端的命令写法不同。

macOS / Linux / Git Bash / WSL 使用 Bash 写法：

```bash
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/check_xray_health.sh
```

Windows PowerShell 使用 `$env:` 写法：

```powershell
$env:VPS_HOST="<你的_VPS_IP>"; $env:SSH_USER="root"; $env:SSH_PORT="22"; bash scripts/check_xray_health.sh
```

如果看到 `PS C:\...>`，不要复制 `VPS_HOST="..." \` 这种 Bash 多行写法。
完整说明请看 `docs/25_cross_platform_command_guide.md`。

## SSH 密钥与 VPS 信任
每台本机电脑都需要具备可用的 SSH 登录能力，项目脚本才能通过 SSH 检查、备份或部署 VPS。

你需要分清两件事：

1. SSH 密钥：用于本机登录 VPS。
2. Xray / REALITY 密钥：用于客户端连接代理服务。

不同系统查看、生成和加载 SSH 密钥的方式不同：

- macOS / Linux / Git Bash / WSL：通常使用 `~/.ssh/id_ed25519`。
- Windows PowerShell：通常使用 `C:\Users\<你的用户名>\.ssh\id_ed25519`。
- 首次连接 VPS 时，需要输入 `yes` 把 VPS 主机指纹写入本机 `known_hosts`。

详细步骤请看 `docs/26_ssh_key_and_vps_trust.md`。

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

Windows、Linux、WSL、Git Bash 的 SSH 密钥和 `ssh-agent` 配置方式请看 `docs/26_ssh_key_and_vps_trust.md`。

## VPS 初始化方式
在仓库根目录执行：

以下是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

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

以下是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

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
grep -nF '${' configs/server/config.json
bash scripts/validate_xray_config.sh configs/server/config.json
```

确认没有占位符，并看到 `[done] xray config validation passed` 后，再上传：

```bash
scp -P 22 configs/server/config.json root@<你的_VPS_IP>:/usr/local/etc/xray/config.json
```

更推荐使用部署脚本自动完成上传、远程备份、权限设置、UFW 端口放行和重启：

以下是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/deploy_xray_config.sh
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

以下是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
bash scripts/generate_singbox_config.sh
```

默认生成 `tun` 模式，适合 sing-box VT 在 iPhone / iPad / Mac 上作为 VPN Profile 使用。
如果 sing-box VT 提示 `legacy special outbounds` 弃用警告，请重新生成并导入最新配置。

生成后检查：

```bash
grep -nF '${' configs/client/singbox.json
jq empty configs/client/singbox.json
```

如果 `grep -nF '${'` 没有输出，才表示占位符替换完毕。
`${SINGBOX_MIXED_PORT}` 和 `${NODE_PORT}` 是数字字段，替换时不要加引号。

Shadowrocket 客户端：

推荐用脚本生成导入链接：

以下是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
NODE_NAME="jp-tokyo-01" \
bash scripts/generate_shadowrocket_link.sh
```

然后复制 `configs/client/shadowrocket_link.txt` 里的 `vless://...` 链接，在 Shadowrocket 中从剪贴板或 URL 导入。

导入前可以先验证链接字段：

```bash
bash scripts/validate_shadowrocket_link.sh
```

导入后进入节点详情，点 `TLS`，确认 `Reality`、`SNI`、`Public Key`、`Short ID`、`Fingerprint` 都已正确显示。
如果提示“使用中的配置无法删除”，先关闭 Shadowrocket 总开关和 iOS VPN，再删除旧节点。

详细说明请看 `docs/12_client_config_explained.md`。

## Mac 电脑端接入
Mac 端推荐继续使用 sing-box VT，并复用 `configs/client/singbox.json`。

如果需要重新生成 Mac 可用配置：

以下是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
SINGBOX_MODE="tun" \
bash scripts/generate_singbox_config.sh
```

导入到 Mac sing-box VT 后，先允许 macOS 添加 VPN Profile，再启用配置。

启用前后都可以运行本地检查：

```bash
EXPECTED_EXIT_IP="<你的_VPS_IP>" \
bash scripts/check_macos_singbox.sh
```

启用前如果出口 IP 不一致是正常的；启用后应看到出口 IP 与 VPS IP 一致。
详细说明请看 `docs/21_macos_client_setup.md`。

如果 Mac App Store 暂时无法下载 sing-box VT，而你已经安装了 Shadowrocket，可以直接重新导入 Shadowrocket 链接：

```bash
bash scripts/copy_shadowrocket_link_macos.sh
```

脚本会把已校验的 `vless://...` 链接复制到剪贴板，但不会在终端显示完整链接。
然后在 Shadowrocket 中选择从剪贴板或 URL 导入即可。

## Windows 电脑端接入
Windows 上不要使用只有“服务器、端口、密码、加密方式”的 Shadowsocks 配置界面。
当前节点是 VLESS + REALITY，推荐使用支持 VLESS + REALITY 的客户端，例如 v2rayN。

如果你在 Windows PowerShell 中运行仓库脚本，不要使用 `VPS_HOST="..." \` 这种 Bash 写法。
PowerShell 环境变量应写成 `$env:变量名="值"`，完整示例见 `docs/25_cross_platform_command_guide.md`。
如果只是配置 Windows 客户端，不需要重新运行 `vps_init.sh` 或 `install_xray.sh`。

如果 VPS 已经配置好，但 Windows 本机还没有 `jq` 或 GitHub 访问暂时不稳定，推荐直接从 VPS 生成 v2rayN 导入链接。
该脚本会显式调用 `C:\Windows\System32\OpenSSH\ssh.exe`，避开某些 Windows 环境中 `ssh` 打开空文档的问题：

```powershell
$env:VPS_HOST="<你的_VPS_IP或域名>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
powershell -ExecutionPolicy Bypass -File .\scripts\windows_generate_vless_link_from_vps.ps1
```

脚本会把 `vless://...` 链接复制到剪贴板，并保存到桌面的 `vless-link.txt`。
然后在 Windows v2rayN 中选择从剪贴板导入分享链接。

如果是在 macOS / Linux / Git Bash / WSL 上准备链接，也可以运行：

```bash
bash scripts/prepare_windows_vless_link.sh
```

输出文件：

```text
configs/client/windows_vless_link.txt
```

在 Windows v2rayN 中选择从剪贴板导入分享链接，然后启用系统代理。
详细说明请看 `docs/22_windows_client_setup.md`。

也可以直接生成 Windows 一键配置包：

```bash
bash scripts/build_windows_client_bundle.sh
```

生成的 zip 会放在 `exports/windows-client/`，里面包含复制链接、下载 v2rayN、连接检查的 PowerShell 脚本。
详细说明请看 `docs/23_windows_one_click_bundle.md`。

## 初次连接检查
登录 VPS 后确认服务运行：

```bash
systemctl status xray --no-pager -l
ss -lntp | grep ":443"
ufw status verbose
```

在本机检查端口连通：

```bash
nc -vz <你的_VPS_IP> 443
```

如果 `ufw status verbose` 只看到 `22/tcp ALLOW IN`，说明 VPS 只放行了 SSH，需要先放行 Xray 的 TCP 端口：

```bash
ufw allow proto tcp to any port 443 comment 'resilient-personal-network xray inbound'
ufw reload
```

如果端口通但客户端连不上，优先检查 UUID、公钥、shortId、serverName 和 flow 是否与服务端一致。

也可以运行完整健康检查：

以下是 Bash 写法；Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/check_xray_health.sh
```

## 稳定性、备份和恢复
如果 VPS 已经配置好，但当前本机缺少 `configs/server/config.json`，可以先从远端拉取当前正在使用的配置：

以下是 Bash 写法；Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/fetch_remote_xray_config.sh
```

拉取后的文件会保存到 `configs/server/config.json`，该文件包含真实密钥并已被 `.gitignore` 忽略。
如果本地原来已有同名配置，脚本会先备份到 `backups/`。
如果 Windows 提示缺少 `jq`，新版脚本会在远端校验通过后继续保存；但后续生成客户端配置仍建议安装：`winget install jqlang.jq`。

节点跑通后，建议先做一次远程备份：

以下是 Bash 写法；Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/backup_remote_xray.sh
```

备份包会保存在 VPS 的 `/opt/resilient-personal-network/backups/`，并默认下载到本机 `backups/`。
注意：备份包包含真实服务端配置，不要公开分享，也不要提交到 Git。

如果需要采集排障信息：

以下是 Bash 写法；Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/collect_remote_diagnostics.sh
```

诊断日志会保存在本机 `logs/`，并做基础脱敏。

如果配置损坏，需要从备份恢复：

以下是 Bash 写法；Windows PowerShell 请参考 `docs/25_cross_platform_command_guide.md`。

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/restore_remote_xray_config.sh backups/<你的备份包>.tar.gz
```

详细说明请看 `docs/20_operations_runbook.md`。

## 定期维护建议
稳定节点不需要频繁改 UUID、REALITY 密钥、shortId、SNI 或端口。
建议每月做一次备份和健康检查，每 1 到 3 个月查看是否有重要安全更新。

详细维护计划请看 `docs/24_maintenance_schedule.md`。

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
4. **Round 4：稳定性、备份与恢复**
   - 增加节点备份、健康检查、诊断采集和恢复流程。
5. **Round 5：Mac 电脑端接入**
   - 复用当前节点配置，整理 Mac sing-box VT 导入、启用和验证流程。
6. **Round 6：节点资产管理**
   - 增加节点档案、续费信息、变更日志和设备清单。
7. **Windows 电脑端接入补充**
   - 说明 Windows 客户端选择、v2rayN 导入方式和 Shadowsocks 客户端不兼容的原因。
8. **多系统命令写法整理**
   - 区分 macOS/Linux/Git Bash/WSL、Windows PowerShell、VPS 远程 shell 的命令写法。
   - 避免把 Bash 环境变量写法复制到 PowerShell。
9. **SSH 密钥与 VPS 信任配置**
   - 说明不同系统如何生成 SSH 密钥、写入 `authorized_keys`、处理 `known_hosts` 和首次信任。
10. **后续轮次：安全加固与故障切换**
   - 增加 SSH 加固、多节点备份和故障切换流程。

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
请按顺序执行。以下为 Bash 写法，Windows PowerShell 请看 `docs/25_cross_platform_command_guide.md`：

```bash
bash scripts/vps_init.sh
ssh -p 22 root@<你的_VPS_IP>
ls -la /opt/resilient-personal-network
cat /opt/resilient-personal-network/logs/vps_init.log
```

若能看到远程目录和初始化日志，则 Round 1 验收通过。

## Round 2 验收命令
请按顺序执行。以下为 Bash 写法，Windows PowerShell 请看 `docs/25_cross_platform_command_guide.md`：

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
grep -nF '${' configs/client/singbox.json
jq empty configs/client/singbox.json
```

注意：复制后需要先替换所有 `${...}` 占位符。
替换完成后，`grep` 没有输出且 `jq` 不报错，则客户端配置文件格式通过。
导入客户端并能连接节点，则 Round 3 初步连接验收通过。

## Round 4 验收命令
请按顺序执行。以下为 Bash 写法，Windows PowerShell 请看 `docs/25_cross_platform_command_guide.md`：

```bash
bash -n scripts/*.sh
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/check_xray_health.sh
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/collect_remote_diagnostics.sh
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/backup_remote_xray.sh
bash scripts/snapshot_tree.sh
```

若健康检查通过、诊断日志生成、备份包生成，且快照可读，则 Round 4 验收通过。

## Round 5 验收命令
请按顺序执行。以下为 Bash 写法，Windows PowerShell 请看 `docs/25_cross_platform_command_guide.md`：

```bash
bash -n scripts/*.sh
jq empty configs/client/singbox.json
EXPECTED_EXIT_IP="<你的_VPS_IP>" bash scripts/check_macos_singbox.sh
bash scripts/copy_shadowrocket_link_macos.sh
bash scripts/snapshot_tree.sh
```

在 Mac sing-box VT 启用配置后，再运行一次：

```bash
EXPECTED_EXIT_IP="<你的_VPS_IP>" bash scripts/check_macos_singbox.sh
```

若启用后脚本显示当前出口 IP 与 VPS IP 一致，则 Round 5 Mac 端验收通过。

## 路线选择：自建、托管订阅与混合模式
本项目不只服务于自建 VPS 路线，也会记录托管订阅方案。

- 短期建议：优先使用托管订阅恢复 ChatGPT / Claude / YouTube / GitHub 等生产力访问。
- 中长期建议：保留并持续建设自建节点，作为备用与学习路线。
- 详细策略请见：`docs/05_managed_provider_strategy.md`。
