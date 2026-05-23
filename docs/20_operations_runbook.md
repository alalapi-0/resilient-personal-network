# 20 稳定性、备份与恢复手册

本文件对应 Round 4。
前面几轮已经完成“节点能连接”，这一轮的目标是让节点长期可维护：出问题能检查，改配置前能备份，配置损坏时能恢复。

本文件中的环境变量命令均为 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。
Windows PowerShell 请使用 `$env:VPS_HOST="..."` 写法，完整示例见 `docs/25_cross_platform_command_guide.md`。

## 1. 本轮任务清单

### 文件生成

1. `scripts/backup_remote_xray.sh`
2. `scripts/restore_remote_xray_config.sh`
3. `scripts/collect_remote_diagnostics.sh`
4. `scripts/fetch_remote_xray_config.sh`
5. `docs/20_operations_runbook.md`

### 脚本生成

1. 远程备份脚本：备份 VPS 上的 Xray 配置、服务文件、防火墙状态和近期日志。
2. 远程恢复脚本：从本地备份包恢复 VPS 上的 Xray 配置。
3. 远程诊断脚本：采集非敏感排障信息到本地 `logs/`。
4. 远程配置拉取脚本：把 VPS 上当前正在使用的 Xray 配置拉取到本地忽略目录。

### 文档生成

1. 说明什么时候需要备份。
2. 说明备份包里有什么。
3. 说明如何恢复配置。
4. 说明健康检查结果如何判断。
5. 说明常见故障的处理顺序。

### README 更新

README 会加入 Round 4 的常用命令入口，方便以后不用翻文档。

### 验收标准

1. 执行 `bash -n scripts/*.sh` 不报错。
2. 执行 `bash scripts/snapshot_tree.sh` 可生成快照。
3. 能用 `scripts/check_xray_health.sh` 检查当前节点。
4. 能用 `scripts/backup_remote_xray.sh` 生成远程和本地备份。
5. 能用 `scripts/collect_remote_diagnostics.sh` 生成本地诊断日志。
6. 能用 `scripts/fetch_remote_xray_config.sh` 把远程配置拉取到本地 `configs/server/config.json`。

## 2. 什么时候需要备份

建议在这些场景先做备份：

1. 节点刚刚跑通之后。
2. 修改服务端 `config.json` 之前。
3. 升级 Xray-core 之前。
4. 改 UFW、防火墙、SSH 配置之前。
5. 准备迁移 VPS 或新增节点之前。

备份不是为了频繁使用，而是为了在出错时有退路。
只要你不确定下一步会不会影响连接，就先备份。

## 3. 备份包里有什么

备份包默认包含：

1. `config.json`：真实 Xray 服务端配置，包含 REALITY 私钥和 shortId。
2. `xray.service`：systemd 服务文件。
3. `manifest.txt`：备份时间、路径、系统信息。
4. `xray_status.txt`：备份时的 Xray 服务状态。
5. `listen_tcp.txt`：备份时的监听端口。
6. `ufw_status.txt`：备份时的 UFW 防火墙状态。
7. `xray_journal_tail_redacted.txt`：近期 Xray 日志，已做基础脱敏。

注意：备份包里有真实服务端配置，所以不要发给别人，不要提交到 GitHub。
本项目已经在 `.gitignore` 中忽略 `backups/*`。

## 4. 从远程拉取当前配置到本地

如果 VPS 已经配置好，但你当前本机没有 `configs/server/config.json`，可以从远端拉取当前正在使用的 Xray 配置。

适用场景：

1. 新电脑刚同步 GitHub 仓库，本地没有真实配置。
2. Windows 端想基于当前 VPS 配置重新生成 v2rayN 导入链接。
3. Mac 端想基于远程配置重新生成 sing-box 或 Shadowrocket 配置。
4. 需要确认本地配置和远端正在运行的配置一致。

在本机仓库根目录执行：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/fetch_remote_xray_config.sh
```

脚本会做这些事：

1. SSH 登录 VPS。
2. 检查远程 `/usr/local/etc/xray/config.json` 是否存在、可读、JSON 有效、没有占位符。
3. 把远程配置下载到本地临时文件。
4. 如果本机有 `jq`，在本地运行 `scripts/validate_xray_config.sh` 做严格校验。
5. 如果本地已有 `configs/server/config.json`，先备份到 `backups/`。
6. 把下载后的配置保存为 `configs/server/config.json`，权限设置为 `600`。

注意：这个文件包含真实 UUID、REALITY 私钥和 shortId。
`configs/server/config.json` 已被 `.gitignore` 忽略，不要手动提交。

如果 Windows 提示本机缺少 `jq`，新版脚本会在远端校验通过后继续保存配置，但后续生成 sing-box、Shadowrocket、v2rayN 链接仍建议安装 `jq`。

Windows PowerShell 安装方式：

```powershell
winget install jqlang.jq
```

安装完成后重新打开 PowerShell 或 Git Bash，再检查：

```powershell
jq --version
```

## 5. 创建远程备份

在本机仓库根目录执行：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/backup_remote_xray.sh
```

脚本会做这些事：

1. SSH 登录 VPS。
2. 在 VPS 的 `/opt/resilient-personal-network/backups/` 生成备份包。
3. 默认把备份包下载到本机 `backups/`。
4. 设置本地备份包权限为 `600`。

如果只想保留远程备份，不下载到本机：

```bash
DOWNLOAD_BACKUP="no" \
VPS_HOST="<你的_VPS_IP或域名>" \
bash scripts/backup_remote_xray.sh
```

## 6. 恢复远程配置

恢复是高风险操作，只在这些场景使用：

1. 新配置部署后 Xray 启动失败。
2. 误删或误改了 `/usr/local/etc/xray/config.json`。
3. VPS 上配置损坏，且你确认某个旧备份可用。

恢复命令：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/restore_remote_xray_config.sh backups/<你的备份包>.tar.gz
```

脚本会要求你输入：

```text
RESTORE
```

只有明确输入 `RESTORE` 才会继续。

恢复脚本会做这些事：

1. 检查本地备份包格式。
2. 上传备份包到 VPS 临时目录。
3. 解出其中的 `config.json`。
4. 检查 JSON 格式和占位符。
5. 备份 VPS 当前配置。
6. 安装旧配置并设置 `root:xray` + `640` 权限。
7. 如果 UFW 已启用，确保配置端口被放行。
8. 重启 Xray 并显示服务状态。

## 7. 采集远程诊断日志

如果你向我求助排障，优先运行这个脚本。
它不会输出完整服务端配置，只会保存端口、监听、防火墙、服务状态和脱敏日志。

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/collect_remote_diagnostics.sh
```

输出文件会保存在：

```text
logs/remote-diagnostics-<主机>-<时间>.txt
```

`logs/` 已被 `.gitignore` 忽略。
如果需要发给别人看，仍建议先自己快速扫一眼，确认没有不想公开的信息。

## 8. 健康检查

日常检查用：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/check_xray_health.sh
```

重点看这些结果：

1. 本地服务端配置校验是否通过。
2. 本地到 VPS 的 TCP 端口是否通。
3. 远程 `xray` 是否是 `active`。
4. 远程 `ss` 是否显示 Xray 监听 `443`。
5. 远程 UFW 是否允许 `443/tcp`。

如果客户端连不上，排查顺序建议固定为：

1. 先看客户端是否启用。
2. 再看 `ipinfo.io` 出口 IP 是否变成 VPS。
3. 再运行健康检查脚本。
4. 如果 TCP 超时，优先查 UFW 和云厂商防火墙。
5. 如果 TCP 通但认证失败，再查 UUID、公钥、shortId、SNI、flow。

## 9. 快照

每次完成一轮变更后执行：

```bash
bash scripts/snapshot_tree.sh
```

快照保存在：

```text
docs/tree_snapshot.txt
```

快照会排除 `configs/server/*.json`、`configs/client/*.json`、`backups/`、`logs/` 等敏感或临时内容。

## 10. Round 4 完成状态

Round 4 完成后，你应该具备三件事：

1. 会检查：知道如何运行健康检查和诊断采集。
2. 会备份：知道改配置前先备份。
3. 会恢复：知道配置坏了以后如何回滚。

到这里，项目从“能连接”进入了“能长期维护”的阶段。
