# 说明：从已经配置好的 VPS 远程读取 Xray 配置，生成 Windows v2rayN 可导入的 VLESS 链接。
# 运行位置：Windows PowerShell。
# 安全原则：
# 1) 不需要 Windows 本机安装 jq；
# 2) 使用 VPS 上已经安装的 jq 和 xray 生成链接；
# 3) 不在屏幕上打印完整 vless:// 链接；
# 4) 链接会复制到剪贴板，并保存到桌面 vless-link.txt；
# 5) vless-link.txt 包含真实节点信息，导入后请妥善保存或删除。

$ErrorActionPreference = "Stop"

function Wait-BeforeExit {
  Write-Host ""
  Read-Host "按回车键退出"
}

function Get-OpenSshPath {
  # 优先使用 Windows OpenSSH 的真实 ssh.exe，避免被 C:\Windows\System32\ssh 这类异常同名文件抢先匹配。
  $DefaultPath = Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe"
  if (Test-Path $DefaultPath) {
    return $DefaultPath
  }

  $Candidates = Get-Command ssh.exe -All -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -like "*\OpenSSH\ssh.exe" } |
    Select-Object -ExpandProperty Source -First 1

  if ($Candidates) {
    return $Candidates
  }

  throw "找不到 Windows OpenSSH ssh.exe。请先安装 OpenSSH Client，或确认 C:\Windows\System32\OpenSSH\ssh.exe 存在。"
}

function ConvertTo-ShellSingleQuoted {
  param([string]$Value)
  # 给远程 bash 命令使用的单引号转义。
  return "'" + ($Value -replace "'", "'\''") + "'"
}

try {
  $VpsHost = $env:VPS_HOST
  if (-not $VpsHost) {
    $VpsHost = Read-Host "请输入 VPS IP 或域名"
  }

  if (-not $VpsHost) {
    throw "VPS_HOST 不能为空"
  }

  $SshUser = $env:SSH_USER
  if (-not $SshUser) {
    $SshUser = "root"
  }

  $SshPort = $env:SSH_PORT
  if (-not $SshPort) {
    $SshPort = "22"
  }

  $NodeName = $env:NODE_NAME
  if (-not $NodeName) {
    $NodeName = "jp-tokyo-01"
  }

  $RemoteConfigPath = $env:REMOTE_CONFIG_PATH
  if (-not $RemoteConfigPath) {
    $RemoteConfigPath = "/usr/local/etc/xray/config.json"
  }

  $OutputFile = $env:OUTPUT_FILE
  if (-not $OutputFile) {
    $OutputFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "vless-link.txt"
  }

  $SshExe = Get-OpenSshPath
  $SshTarget = "$SshUser@$VpsHost"
  $RemotePrefix = "NODE_HOST=$(ConvertTo-ShellSingleQuoted $VpsHost) NODE_NAME=$(ConvertTo-ShellSingleQuoted $NodeName) REMOTE_CONFIG_PATH=$(ConvertTo-ShellSingleQuoted $RemoteConfigPath) bash -s"

  Write-Host "== 从 VPS 生成 v2rayN 导入链接 =="
  Write-Host "[info] SSH 程序：$SshExe"
  Write-Host "[info] 目标 VPS：$SshTarget"
  Write-Host "[info] SSH 端口：$SshPort"
  Write-Host "[info] 远程配置：$RemoteConfigPath"

  $RemoteScript = @'
set -euo pipefail

CFG="${REMOTE_CONFIG_PATH:-/usr/local/etc/xray/config.json}"

command -v jq >/dev/null || { echo "ERR: remote jq missing" >&2; exit 1; }
test -r "$CFG" || { echo "ERR: config not readable" >&2; exit 1; }
test -x /usr/local/bin/xray || { echo "ERR: xray not executable" >&2; exit 1; }

UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$CFG")"
PORT="$(jq -r '.inbounds[0].port' "$CFG")"
FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow' "$CFG")"
SNI="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CFG")"
SID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CFG")"
PRIV="$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CFG")"
PUB="$(/usr/local/bin/xray x25519 -i "$PRIV" | sed -n 's/^Public key: //p' | tr -d '\r\n ')"
NODE_NAME_ENCODED="$(jq -rn --arg value "${NODE_NAME:-jp-tokyo-01}" '$value | @uri')"

test -n "$UUID" || { echo "ERR: UUID empty" >&2; exit 1; }
test -n "$PORT" || { echo "ERR: PORT empty" >&2; exit 1; }
test -n "$FLOW" || { echo "ERR: FLOW empty" >&2; exit 1; }
test -n "$SNI" || { echo "ERR: SNI empty" >&2; exit 1; }
test -n "$SID" || { echo "ERR: SID empty" >&2; exit 1; }
test -n "$PUB" || { echo "ERR: PUBLIC KEY empty" >&2; exit 1; }

LINK="$(printf 'vless://%s@%s:%s?encryption=none&flow=%s&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s' "$UUID" "$NODE_HOST" "$PORT" "$FLOW" "$SNI" "$PUB" "$SID" "$NODE_NAME_ENCODED")"
printf '%s' "$LINK" | base64 -w 0
printf '\n'
'@

  $Raw = $RemoteScript | & $SshExe -p $SshPort $SshTarget $RemotePrefix 2>&1

  if ($LASTEXITCODE -ne 0) {
    Write-Host "[error] 远程生成失败：" -ForegroundColor Red
    $Raw
    throw "远程生成链接失败"
  }

  $Base64Line = $Raw |
    Where-Object { $_ -match '^[A-Za-z0-9+/=]+$' } |
    Select-Object -Last 1

  if (-not $Base64Line) {
    $Raw
    throw "没有拿到 base64 链接输出"
  }

  $Link = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64Line))

  if (-not $Link.StartsWith("vless://")) {
    throw "解码后不是 vless:// 链接"
  }

  try {
    Set-Clipboard -Value $Link
  } catch {
    $Link | clip.exe
  }

  Set-Content -Path $OutputFile -Value $Link -Encoding ASCII

  Write-Host "[ok] 已复制到剪贴板" -ForegroundColor Green
  Write-Host "[ok] 已保存到：$OutputFile" -ForegroundColor Green
  Write-Host "[info] 链接长度：$($Link.Length)"

  if ($Link -match 'pbk=([^&]+)') {
    Write-Host "[info] PublicKey 长度：$($Matches[1].Length)"
  }

  Write-Host "[next] 打开 v2rayN，选择：服务器 -> 从剪贴板导入分享链接"
} catch {
  Write-Host "[error] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "[hint] 请只截图错误文字，不要发送 vless-link.txt 的完整内容。"
  exit 1
} finally {
  Wait-BeforeExit
}
