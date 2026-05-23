#!/usr/bin/env bash
set -euo pipefail

# 说明：本脚本用于生成 Windows 客户端一键配置包。
# 运行位置：在你的本机仓库根目录运行。
# 安全原则：
# 1) 不在终端打印 vless:// 链接内容；
# 2) 输出包会包含真实节点链接，因此 exports/ 已被 .gitignore 忽略；
# 3) Windows 包只做安全的“准备、复制、下载、检查”，不直接篡改客户端内部数据库；
# 4) 真实链接只能通过可信方式传输到 Windows 电脑。

SOURCE_LINK_FILE="${SOURCE_LINK_FILE:-configs/client/windows_vless_link.txt}"
SERVER_CONFIG="${SERVER_CONFIG:-configs/server/config.json}"
EXPORT_ROOT="${EXPORT_ROOT:-exports/windows-client}"
BUNDLE_NAME="${BUNDLE_NAME:-windows-vless-client-$(date -u '+%Y%m%d-%H%M%S')}"
EXPECTED_EXIT_IP="${EXPECTED_EXIT_IP:-}"

echo "== Windows client bundle =="

# 先确保 Windows VLESS 链接存在且通过校验。
if [ ! -f "$SOURCE_LINK_FILE" ]; then
  echo "[info] Windows VLESS 链接不存在，尝试自动生成"
  bash scripts/prepare_windows_vless_link.sh
fi

if [ ! -f "$SOURCE_LINK_FILE" ]; then
  echo "[error] 找不到 Windows VLESS 链接文件：$SOURCE_LINK_FILE"
  exit 1
fi

if [ ! -f "$SERVER_CONFIG" ]; then
  echo "[error] 找不到服务端配置：$SERVER_CONFIG"
  exit 1
fi

bash scripts/validate_shadowrocket_link.sh "$SOURCE_LINK_FILE" "$SERVER_CONFIG" >/dev/null

LINK_CONTENT="$(tr -d '\n' < "$SOURCE_LINK_FILE")"
if [ -z "$LINK_CONTENT" ]; then
  echo "[error] Windows VLESS 链接为空"
  exit 1
fi

# 从 vless:// 链接中提取节点地址和端口，只用于生成检查脚本，不输出敏感链接。
LINK_WITHOUT_SCHEME="${LINK_CONTENT#vless://}"
SERVER_PART="${LINK_WITHOUT_SCHEME#*@}"
NODE_HOST="${SERVER_PART%%:*}"
PORT_AND_QUERY="${SERVER_PART#*:}"
NODE_PORT="${PORT_AND_QUERY%%\?*}"

if [ -z "$EXPECTED_EXIT_IP" ]; then
  EXPECTED_EXIT_IP="$NODE_HOST"
fi

mkdir -p "$EXPORT_ROOT"
BUNDLE_DIR="$EXPORT_ROOT/$BUNDLE_NAME"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

printf '%s\n' "$LINK_CONTENT" > "$BUNDLE_DIR/vless-link.txt"
chmod 600 "$BUNDLE_DIR/vless-link.txt"

cat > "$BUNDLE_DIR/README_WINDOWS.md" <<'README'
# Windows 客户端配置包

这个文件夹由 resilient-personal-network 项目生成。
它包含当前节点的 VLESS 分享链接和几个 PowerShell 辅助脚本。

## 重要安全提醒

`vless-link.txt` 包含真实节点信息。
不要公开分享，不要上传到公共网盘，不要截图发给别人。

## 推荐流程

1. 右键 `03-download-v2rayn-latest.ps1`，选择使用 PowerShell 运行，下载官方 v2rayN。
2. 解压并打开 v2rayN。
3. 右键 `01-copy-link-and-open-v2rayn.ps1`，使用 PowerShell 运行。
4. 在 v2rayN 中选择“从剪贴板导入分享链接”。
5. 选中导入的节点。
6. 启用系统代理。
7. 运行 `02-check-windows-connection.ps1` 检查连接状态。

如果你已经安装 v2rayN，可以跳过第 1 步。
下载脚本默认把 zip 保存到当前 Windows 用户的 `Downloads` 文件夹。

所有 `.ps1` 脚本都会在结束时等待你按回车。
如果看到红色错误，请把错误文字拍照或复制出来，不要把 `vless-link.txt` 的完整内容发给别人。

## PowerShell 和 Bash 命令不要混用

本包里的 `.ps1` 是 Windows PowerShell 脚本，直接在 Windows 上运行。
如果你还需要在 Windows PowerShell 里运行仓库根目录下的 `scripts/*.sh`，环境变量要写成：

```powershell
$env:VPS_HOST="<你的_VPS_IP>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
bash scripts/check_xray_health.sh
```

不要把 macOS / Linux 里的 `VPS_HOST="..." \` 多行 Bash 写法复制到 PowerShell。
PowerShell 报 `无法将“VPS_HOST=...”项识别为 cmdlet` 时，就是这个原因。

## 为什么不是完全自动写入 v2rayN

v2rayN 的内部配置格式会随版本变化。
为了避免写坏客户端配置，本包只负责复制分享链接、打开官方下载页和做连接检查。导入动作交给 v2rayN 自己完成，更稳。
README

# 给 Windows PowerShell 5.x 写入 UTF-8 BOM，避免中文提示变成乱码。
printf '\357\273\277' > "$BUNDLE_DIR/01-copy-link-and-open-v2rayn.ps1"
cat >> "$BUNDLE_DIR/01-copy-link-and-open-v2rayn.ps1" <<'POWERSHELL'
# 说明：复制 VLESS 链接到 Windows 剪贴板，并打开 v2rayN 发布页面。
# 安全：不会在屏幕上显示完整链接。

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Wait-BeforeExit {
  Write-Host ""
  Read-Host "按回车键退出"
}

try {
  Write-Host "== 复制 VLESS 链接到剪贴板 =="

  $LinkPath = Join-Path $PSScriptRoot "vless-link.txt"
  if (-not (Test-Path $LinkPath)) {
    throw "找不到 vless-link.txt。请确认这个脚本和 vless-link.txt 在同一个解压文件夹里。"
  }

  $Link = (Get-Content -Raw -Encoding UTF8 $LinkPath).Trim()
  if (-not $Link.StartsWith("vless://")) {
    throw "vless-link.txt 不是 vless:// 链接。"
  }

  try {
    Set-Clipboard -Value $Link
  } catch {
    # 某些精简系统里 Set-Clipboard 不可用，退回到 Windows 自带 clip.exe。
    $Link | clip.exe
  }

  Write-Host "[ok] VLESS 链接已复制到剪贴板" -ForegroundColor Green
  Write-Host "[next] 回到 v2rayN，选择：服务器 -> 从剪贴板导入分享链接"
  Write-Host "[hint] 导入完成后，建议复制一段普通文字覆盖剪贴板"

  Start-Process "https://github.com/2dust/v2rayN/releases"
} catch {
  Write-Host "[error] 脚本执行失败" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host "[hint] 如果是执行策略问题，可以在当前文件夹地址栏输入 powershell，然后运行："
  Write-Host "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass"
  Write-Host ".\01-copy-link-and-open-v2rayn.ps1"
} finally {
  Wait-BeforeExit
}
POWERSHELL

# 给 Windows PowerShell 5.x 写入 UTF-8 BOM，避免中文提示变成乱码。
printf '\357\273\277' > "$BUNDLE_DIR/02-check-windows-connection.ps1"
cat >> "$BUNDLE_DIR/02-check-windows-connection.ps1" <<POWERSHELL
# 说明：检查 Windows 到节点端口是否连通，并检查当前公网出口 IP。
# 安全：不会打印完整 VLESS 链接。

\$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$OutputEncoding = [System.Text.Encoding]::UTF8

function Wait-BeforeExit {
  Write-Host ""
  Read-Host "按回车键退出"
}

try {
  \$LinkPath = Join-Path \$PSScriptRoot "vless-link.txt"
  \$ExpectedExitIP = "$EXPECTED_EXIT_IP"

  if (-not (Test-Path \$LinkPath)) {
    throw "找不到 vless-link.txt。请确认这个脚本和 vless-link.txt 在同一个解压文件夹里。"
  }

  \$Link = (Get-Content -Raw -Encoding UTF8 \$LinkPath).Trim()
  if (-not \$Link.StartsWith("vless://")) {
    throw "vless-link.txt 不是 vless:// 链接。"
  }

  \$Uri = [System.Uri]\$Link
  \$HostName = \$Uri.Host
  \$Port = \$Uri.Port

  Write-Host "== TCP 端口检查 =="
  \$TcpResult = Test-NetConnection -ComputerName \$HostName -Port \$Port -WarningAction SilentlyContinue
  if (\$TcpResult.TcpTestSucceeded) {
    Write-Host "[ok] Windows 可以连通节点 TCP 端口" -ForegroundColor Green
  } else {
    Write-Host "[error] Windows 无法连通节点 TCP 端口" -ForegroundColor Red
    Write-Host "[hint] 先确认 VPS 防火墙和云厂商防火墙仍允许该端口"
  }

  Write-Host ""
  Write-Host "== 公网出口检查 =="
  try {
    \$CurrentIP = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    Write-Host "[info] 当前公网出口 IP：\$CurrentIP"
    if (\$ExpectedExitIP -and (\$CurrentIP -eq \$ExpectedExitIP)) {
      Write-Host "[ok] 当前出口 IP 与预期 VPS IP 一致" -ForegroundColor Green
    } elseif (\$ExpectedExitIP) {
      Write-Host "[warn] 当前出口 IP 与预期 VPS IP 不一致" -ForegroundColor Yellow
      Write-Host "[hint] 如果还没在 v2rayN 启用系统代理，这是正常的；启用后再检查"
    }
  } catch {
    Write-Host "[warn] 未能获取当前公网出口 IP" -ForegroundColor Yellow
  }
} catch {
  Write-Host "[error] 脚本执行失败" -ForegroundColor Red
  Write-Host \$_.Exception.Message -ForegroundColor Red
} finally {
  Wait-BeforeExit
}
POWERSHELL

# 给 Windows PowerShell 5.x 写入 UTF-8 BOM，避免中文提示变成乱码。
printf '\357\273\277' > "$BUNDLE_DIR/03-download-v2rayn-latest.ps1"
cat >> "$BUNDLE_DIR/03-download-v2rayn-latest.ps1" <<'POWERSHELL'
# 说明：从 v2rayN 官方 GitHub Release 下载最新 Windows x64 便携包。
# 安全：只访问官方 2dust/v2rayN 仓库发布页。

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Wait-BeforeExit {
  Write-Host ""
  Read-Host "按回车键退出"
}

try {
  $Headers = @{ "User-Agent" = "resilient-personal-network" }
  $Api = "https://api.github.com/repos/2dust/v2rayN/releases/latest"
  $DownloadRoot = Join-Path $env:USERPROFILE "Downloads"

  Write-Host "[info] 正在读取 v2rayN 最新发布信息..."
  $Release = Invoke-RestMethod -Uri $Api -Headers $Headers -TimeoutSec 30

  $Asset = $Release.assets |
    Where-Object { $_.name -eq "v2rayN-windows-64.zip" } |
    Select-Object -First 1

  if (-not $Asset) {
    $Asset = $Release.assets |
      Where-Object { $_.name -like "*windows-64*.zip" -and $_.name -notlike "*desktop*" } |
      Select-Object -First 1
  }

  if (-not $Asset) {
    Write-Host "[error] 未找到 Windows x64 zip 发布包，请手动打开官方 Releases 页面" -ForegroundColor Red
    Start-Process "https://github.com/2dust/v2rayN/releases"
    return
  }

  $ZipPath = Join-Path $DownloadRoot $Asset.name
  Write-Host "[info] 下载文件：$($Asset.name)"
  Write-Host "[info] 保存位置：$ZipPath"
  Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $ZipPath -Headers $Headers

  Write-Host "[ok] 已下载到：$ZipPath" -ForegroundColor Green
  Write-Host "[hint] 请解压 zip 后运行 v2rayN.exe"
  Start-Process $DownloadRoot
} catch {
  Write-Host "[error] 下载脚本执行失败" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host "[hint] 可以手动打开官方页面下载 v2rayN-windows-64.zip："
  Write-Host "https://github.com/2dust/v2rayN/releases"
} finally {
  Wait-BeforeExit
}
POWERSHELL

chmod 600 "$BUNDLE_DIR"/*.ps1 "$BUNDLE_DIR"/*.md

ZIP_PATH="$EXPORT_ROOT/$BUNDLE_NAME.zip"
rm -f "$ZIP_PATH"
(
  cd "$EXPORT_ROOT"
  zip -qr "$BUNDLE_NAME.zip" "$BUNDLE_NAME"
)
chmod 600 "$ZIP_PATH"

echo "[ok] Windows 一键配置包已生成"
echo "[info] 文件夹：$BUNDLE_DIR"
echo "[info] 压缩包：$ZIP_PATH"
echo "[hint] 压缩包包含真实节点链接，只能通过可信方式传到 Windows 电脑"
echo "[done] windows client bundle built"
