# 25 多系统命令写法说明

本文件专门解决一个问题：同一条项目命令，在 macOS、Linux、Git Bash、WSL 和 Windows PowerShell 里的写法不一样。

如果你需要了解 SSH 密钥怎么生成、`authorized_keys` 怎么配置、第一次连接 VPS 为什么要输入 `yes`，请看 `docs/26_ssh_key_and_vps_trust.md`。

如果把 Bash 写法直接复制到 PowerShell，常见报错是：

```text
无法将“VPS_HOST=...”项识别为 cmdlet、函数、脚本文件或可运行程序的名称
```

这不是 VPS 坏了，也不是项目坏了，只是终端语法用错了。

## 1. 先分清你在哪个终端

本项目常见有三种执行位置：

| 执行位置 | 常见终端 | 用途 |
| --- | --- | --- |
| 本机仓库 | macOS 终端、Linux 终端、Git Bash、WSL | 运行 `scripts/*.sh`，生成配置、部署、备份、诊断 |
| Windows 本机 | Windows PowerShell | 运行 `.ps1` 辅助脚本，导入 v2rayN，检查 Windows 客户端 |
| VPS 远程 | SSH 登录后的 Ubuntu shell | 查看 `systemctl`、`ufw`、`journalctl`、`ss` 等服务状态 |

判断方法很简单：

1. 看到提示符类似 `alalapi@... %`，通常是 macOS zsh。
2. 看到提示符类似 `$`，通常是 Bash、Git Bash 或 WSL。
3. 看到提示符类似 `PS C:\...>`，就是 Windows PowerShell。
4. 看到提示符类似 `root@vultr:~#`，就是已经 SSH 到 VPS 上了。

## 2. macOS / Linux / Git Bash / WSL 写法

这些终端可以使用 Bash 环境变量写法。

单行写法：

```bash
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/check_xray_health.sh
```

多行写法：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/check_xray_health.sh
```

注意最后一行不能再加 `\`。
`\` 的意思是“这一行还没结束，下一行继续”。

常见例子：

```bash
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/vps_init.sh
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/install_xray.sh
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/deploy_xray_config.sh
VPS_HOST="<你的_VPS_IP>" SSH_USER="root" SSH_PORT="22" bash scripts/backup_remote_xray.sh
```

客户端配置生成也使用同样规则：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
bash scripts/generate_singbox_config.sh
```

## 3. Windows PowerShell 写法

PowerShell 不能直接使用 `VPS_HOST="..." \` 这种 Bash 写法。

推荐写成多行：

```powershell
$env:VPS_HOST="<你的_VPS_IP>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
bash scripts/check_xray_health.sh
```

也可以写成一行：

```powershell
$env:VPS_HOST="<你的_VPS_IP>"; $env:SSH_USER="root"; $env:SSH_PORT="22"; bash scripts/check_xray_health.sh
```

客户端配置生成示例：

```powershell
$env:NODE_HOST="<你的_VPS_IP或域名>"
$env:XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>"
bash scripts/generate_singbox_config.sh
```

PowerShell 环境变量只在当前窗口生效。关闭窗口后会自动消失。
如果想手动清理，可以执行：

```powershell
Remove-Item Env:VPS_HOST -ErrorAction SilentlyContinue
Remove-Item Env:SSH_USER -ErrorAction SilentlyContinue
Remove-Item Env:SSH_PORT -ErrorAction SilentlyContinue
Remove-Item Env:NODE_HOST -ErrorAction SilentlyContinue
Remove-Item Env:XRAY_REALITY_PUBLIC_KEY -ErrorAction SilentlyContinue
```

## 4. Windows 路径写法

同一个目录，在不同终端里路径也不一样。

PowerShell：

```powershell
cd D:\ProgramData\resilient-personal-network\resilient-personal-network
```

Git Bash：

```bash
cd /d/ProgramData/resilient-personal-network/resilient-personal-network
```

WSL：

```bash
cd /mnt/d/ProgramData/resilient-personal-network/resilient-personal-network
```

如果你在 PowerShell 里运行 `bash scripts/xxx.sh`，需要确保系统里已经安装 Git for Windows 或 WSL，并且 `bash` 命令可用。

## 5. 哪些命令应该在哪里运行

### 本机仓库运行

这些命令在你的电脑仓库目录里运行：

```bash
bash scripts/generate_singbox_config.sh
bash scripts/generate_shadowrocket_link.sh
bash scripts/prepare_windows_vless_link.sh
bash scripts/build_windows_client_bundle.sh
bash scripts/check_xray_health.sh
bash scripts/backup_remote_xray.sh
bash scripts/collect_remote_diagnostics.sh
```

它们会通过 SSH 操作 VPS，或者在本机生成配置文件。

### Windows PowerShell 运行

这些命令在 Windows 上运行：

```powershell
.\01-copy-link-and-open-v2rayn.ps1
.\02-check-windows-connection.ps1
.\03-download-v2rayn-latest.ps1
```

这些 `.ps1` 脚本来自 `exports/windows-client/` 里的 Windows 配置包。

### VPS 远程运行

这些命令是在 SSH 登录 VPS 之后运行：

```bash
systemctl status xray --no-pager -l
ss -lntp | grep ':443'
ufw status verbose
journalctl -u xray -n 100 --no-pager -l
```

看到 `root@...#` 这类提示符时，才表示你正在 VPS 上。

## 6. 常见错误对照

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| PowerShell 提示 `VPS_HOST=...` 无法识别 | 把 Bash 写法复制到了 PowerShell | 改用 `$env:VPS_HOST="..."` |
| 命令最后多了一个 `\` 后卡住 | Bash 以为下一行还有内容 | 删除最后一行末尾的 `\` |
| Windows 运行 `.ps1` 一闪而过 | 双击脚本后窗口自动关闭 | 在文件夹地址栏输入 `powershell`，再运行脚本 |
| PowerShell 阻止脚本执行 | 当前窗口执行策略限制 | 运行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `bash` 不是内部或外部命令 | Windows 没有可用 Bash | 安装 Git for Windows，或改用 WSL |
| `ssh` 打开空白文档，没有回显 | Windows 命令优先匹配到了异常的 `C:\Windows\System32\ssh` | 改用 `& "$env:WINDIR\System32\OpenSSH\ssh.exe"`，或运行项目的 Windows 专用 `.ps1` 脚本 |
| `.ps1` 里中文变乱码并报语法错误 | Windows PowerShell 5.1 按错误编码读取旧脚本 | 删除旧的桌面脚本，使用仓库里的新版 `scripts/windows_generate_vless_link_from_vps.ps1` |
| 在 VPS 上执行 `bash scripts/...` 找不到文件 | 这些脚本在本机仓库，不在 VPS 当前目录 | 回到本机仓库执行，或先上传相关脚本 |

## 7. Windows 客户端配置不要跑错脚本

如果你只是想让 Windows 电脑连接已经跑通的节点，通常不需要运行：

```bash
bash scripts/vps_init.sh
bash scripts/install_xray.sh
```

这两个脚本是给 VPS 服务端用的。

Windows 客户端更常用的是：

```bash
bash scripts/prepare_windows_vless_link.sh
bash scripts/build_windows_client_bundle.sh
```

然后在 Windows 上使用生成包里的 `.ps1` 脚本和 v2rayN 导入链接。

如果你的 VPS 已经配置好，Windows 本机只想直接拿到 v2rayN 链接，可以在 Windows PowerShell 运行：

```powershell
$env:VPS_HOST="<你的_VPS_IP或域名>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
powershell -ExecutionPolicy Bypass -File .\scripts\windows_generate_vless_link_from_vps.ps1
```

该脚本不要求 Windows 本机安装 `jq`，会让 VPS 自己读取当前 Xray 配置并生成链接。

## 8. 验收标准

完成本文件对应整理后，应满足：

1. macOS / Linux / Git Bash 用户能直接复制 Bash 示例。
2. Windows PowerShell 用户能直接复制 `$env:` 示例。
3. 用户能分清本机仓库、Windows 客户端和 VPS 远程 shell。
4. 不再把 `VPS_HOST="..." \` 这种 Bash 多行写法直接粘贴到 PowerShell。
