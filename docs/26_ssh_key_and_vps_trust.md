# 26 SSH 密钥与 VPS 信任配置

本文件说明：不同系统如何准备本机 SSH 密钥、如何把公钥配置到远程 VPS、如何完成首次主机信任，以及项目脚本如何通过 SSH 连接 VPS。

先分清两类密钥：

| 类型 | 用途 | 是否提交到 Git |
| --- | --- | --- |
| SSH 私钥 / 公钥 | 用来登录和管理 VPS | 私钥绝不提交，公钥通常也不需要提交 |
| Xray UUID / REALITY 私钥 / 公钥 / shortId | 用来让客户端连接 Xray 服务 | 真实值绝不提交 |

你当前遇到的 `Host key verification failed` 属于 SSH 信任问题，不是 Xray 配置问题。

## 1. SSH 登录链路是什么

一条完整的 SSH 登录链路包含四部分：

1. 本机私钥：只保存在你自己的电脑上，例如 `id_ed25519`。
2. 本机公钥：可以复制到 VPS，例如 `id_ed25519.pub`。
3. VPS 的 `authorized_keys`：保存允许登录的公钥。
4. 本机 `known_hosts`：保存你信任过的 VPS 主机指纹。

关系可以理解为：

```text
本机私钥 -> 证明“我是我”
本机公钥 -> 放在 VPS 上，允许这个身份登录
known_hosts -> 本机记住“这台 VPS 是我信任过的那台”
```

## 2. macOS 查看和生成 SSH 密钥

查看是否已有密钥：

```bash
ls -la ~/.ssh
test -f ~/.ssh/id_ed25519.pub && cat ~/.ssh/id_ed25519.pub
```

如果没有 `id_ed25519` 和 `id_ed25519.pub`，生成一对新密钥：

```bash
ssh-keygen -t ed25519 -C "<你的邮箱或设备名>"
```

一路按回车会使用默认路径：

```text
~/.ssh/id_ed25519
~/.ssh/id_ed25519.pub
```

如果提示设置 passphrase，可以设置一个本机私钥密码。这个密码不会传给 VPS，也不会写入项目。

把私钥加入 macOS 钥匙串：

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

如果你的 macOS 不支持 `--apple-use-keychain`，使用：

```bash
ssh-add ~/.ssh/id_ed25519
```

可选：给这台 VPS 配一个 SSH 别名。编辑 `~/.ssh/config`：

```sshconfig
Host resilient-vps
  HostName <你的_VPS_IP或域名>
  User root
  Port 22
  IdentityFile ~/.ssh/id_ed25519
  AddKeysToAgent yes
  UseKeychain yes
```

保存后可以用：

```bash
ssh resilient-vps
```

## 3. Linux / WSL / Git Bash 查看和生成 SSH 密钥

查看是否已有密钥：

```bash
ls -la ~/.ssh
test -f ~/.ssh/id_ed25519.pub && cat ~/.ssh/id_ed25519.pub
```

生成新密钥：

```bash
ssh-keygen -t ed25519 -C "<你的邮箱或设备名>"
```

启动 ssh-agent 并加载私钥：

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

可选：配置 SSH 别名。编辑 `~/.ssh/config`：

```sshconfig
Host resilient-vps
  HostName <你的_VPS_IP或域名>
  User root
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

然后运行：

```bash
ssh resilient-vps
```

## 4. Windows PowerShell 查看和生成 SSH 密钥

先确认 Windows 有 OpenSSH 客户端：

```powershell
Get-Command ssh
Get-Command ssh-keygen
```

查看是否已有密钥：

```powershell
Get-ChildItem "$env:USERPROFILE\.ssh"
Test-Path "$env:USERPROFILE\.ssh\id_ed25519.pub"
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

如果没有密钥，生成一对新密钥：

```powershell
ssh-keygen -t ed25519 -C "<你的邮箱或设备名>"
```

默认路径通常是：

```text
C:\Users\<你的用户名>\.ssh\id_ed25519
C:\Users\<你的用户名>\.ssh\id_ed25519.pub
```

启动 Windows 的 ssh-agent：

```powershell
Get-Service ssh-agent
Start-Service ssh-agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
```

如果 `Start-Service ssh-agent` 提示权限不足，用管理员身份打开 PowerShell 后运行：

```powershell
Set-Service -Name ssh-agent -StartupType Manual
Start-Service ssh-agent
```

然后回到普通 PowerShell，再执行：

```powershell
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
```

可选：配置 SSH 别名。编辑：

```powershell
notepad "$env:USERPROFILE\.ssh\config"
```

写入：

```sshconfig
Host resilient-vps
  HostName <你的_VPS_IP或域名>
  User root
  Port 22
  IdentityFile C:/Users/<你的用户名>/.ssh/id_ed25519
```

保存后运行：

```powershell
ssh resilient-vps
```

## 5. 把本机公钥放到 VPS

如果你在创建 VPS 时已经把公钥填进云厂商控制台，通常不需要重复操作。

如果你还能用密码登录 VPS，可以把当前电脑的公钥追加到 VPS 的 `authorized_keys`。

macOS / Linux / WSL / Git Bash：

```bash
cat ~/.ssh/id_ed25519.pub | ssh -p 22 root@<你的_VPS_IP或域名> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Windows PowerShell：

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | ssh -p 22 root@<你的_VPS_IP或域名> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

如果你没有密码登录能力，也没有云厂商控制台救援入口，就不能凭空把公钥写进 VPS。需要先通过云厂商控制台、快照重装或救援模式恢复登录权限。

## 6. 首次连接和 known_hosts

第一次从某台电脑连接 VPS 时，会看到类似提示：

```text
The authenticity of host '<你的_VPS_IP>' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

含义是：这台电脑还没见过这台 VPS，需要你确认是否信任。

如果这是你刚创建或确认正在使用的 VPS，输入：

```text
yes
```

成功后，本机会把 VPS 主机指纹写入 `known_hosts`。以后项目脚本就不会卡在这个确认步骤。

macOS / Linux / WSL / Git Bash 的 `known_hosts` 通常在：

```text
~/.ssh/known_hosts
```

Windows PowerShell 原生 OpenSSH 的 `known_hosts` 通常在：

```text
C:\Users\<你的用户名>\.ssh\known_hosts
```

如果你在 Windows PowerShell 里通过 Git Bash 的 `bash scripts/check_xray_health.sh` 运行脚本，可以先让 Git Bash 记住主机：

```powershell
bash -lc 'ssh -p 22 root@<你的_VPS_IP或域名>'
```

如果不确定 Git Bash 使用的是哪个家目录，可以先看：

```powershell
bash -lc 'echo $HOME; ls -la ~/.ssh'
```

看到确认提示时输入 `yes`，登录成功后执行：

```bash
exit
```

## 7. VPS 重装或更换后的主机指纹变化

如果 VPS 重装过系统、恢复过快照、换过 IP，可能出现：

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

这表示本机记住的主机指纹和当前 VPS 返回的指纹不一致。

不要无脑删除。先确认：

1. 这个 IP 确实还是你的 VPS。
2. 云厂商控制台里显示的实例没有异常。
3. 你最近确实重装、重建或迁移过系统。

确认无误后，可以删除旧记录。

默认 22 端口：

```bash
ssh-keygen -R <你的_VPS_IP或域名>
```

非 22 端口：

```bash
ssh-keygen -R '[<你的_VPS_IP或域名>]:<SSH端口>'
```

然后重新连接并输入 `yes`。

## 8. 验证 SSH 是否真正可用

直接连接：

```bash
ssh -p 22 root@<你的_VPS_IP或域名>
```

如果配置了别名：

```bash
ssh resilient-vps
```

非交互验证：

```bash
ssh -p 22 root@<你的_VPS_IP或域名> 'hostname; whoami; date -u'
```

成功时你应该看到：

1. VPS 主机名。
2. 当前用户，例如 `root`。
3. UTC 时间。

退出远程 VPS：

```bash
exit
```

## 9. 项目脚本如何使用 SSH

本项目脚本不会保存 SSH 密码或私钥密码。它们只读取运行时传入的连接参数：

| 环境变量 | 含义 | 示例 |
| --- | --- | --- |
| `VPS_HOST` | VPS IP 或域名 | `<你的_VPS_IP>` |
| `SSH_USER` | SSH 用户 | `root` |
| `SSH_PORT` | SSH 端口 | `22` |
| `NODE_PORT` | Xray 监听端口，健康检查时常用 | `443` |

macOS / Linux / Git Bash / WSL：

```bash
VPS_HOST="<你的_VPS_IP或域名>" SSH_USER="root" SSH_PORT="22" NODE_PORT="443" bash scripts/check_xray_health.sh
```

Windows PowerShell：

```powershell
$env:VPS_HOST="<你的_VPS_IP或域名>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
$env:NODE_PORT="443"
bash scripts/check_xray_health.sh
```

如果你的 VPS 已经配置好，不要重复执行初始化和安装：

```bash
bash scripts/vps_init.sh
bash scripts/install_xray.sh
```

日常只需要健康检查、备份、诊断和客户端配置。

## 10. 常见问题

### Host key verification failed

本机还没有信任 VPS 主机指纹，或脚本无法交互输入 `yes`。

先手动执行：

```bash
ssh -p 22 root@<你的_VPS_IP或域名>
```

Windows PowerShell 里如果脚本走 Git Bash，可以执行：

```powershell
bash -lc 'ssh -p 22 root@<你的_VPS_IP或域名>'
```

输入 `yes`，登录成功后 `exit`，再重新运行项目脚本。

### Permission denied (publickey)

VPS 没有你的公钥，或脚本没有用到正确私钥。

按顺序检查：

1. 本机是否存在 `id_ed25519` 和 `id_ed25519.pub`。
2. 私钥是否已加入 ssh-agent。
3. VPS 的 `~/.ssh/authorized_keys` 是否包含你的公钥。
4. SSH 用户是否正确，例如是 `root` 还是云厂商默认用户。

### 每次都要求输入私钥密码

说明私钥设置了 passphrase，但没有成功加入 ssh-agent。

macOS：

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Windows PowerShell：

```powershell
Start-Service ssh-agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
```

### Connection timed out

SSH 请求没有连到 VPS。常见原因：

1. IP 或端口写错。
2. VPS 防火墙或云厂商防火墙没放行 SSH 端口。
3. VPS 已关机。
4. 当前网络到 VPS 不通。

### Connection refused

请求到了 VPS，但目标端口没有 SSH 服务监听。常见原因：

1. SSH 端口不是 `22`。
2. `sshd` 服务没有运行。
3. VPS 防火墙规则异常。

## 11. 当前项目建议流程

如果你已经有一台配置好的 VPS，新电脑接入时建议按这个顺序：

1. 在新电脑生成或确认 SSH 密钥。
2. 确认 VPS 已有这台电脑的公钥。
3. 手动 SSH 一次，输入 `yes` 完成 `known_hosts` 信任。
4. 运行 `check_xray_health.sh` 做远程健康检查。
5. 如果只是 Windows 客户端配置，直接使用 `vless://...` 链接导入 v2rayN，不要重跑 VPS 初始化。
