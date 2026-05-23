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
  Read-Host "Press Enter to exit"
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

  throw "Windows OpenSSH ssh.exe not found. Install OpenSSH Client or check C:\Windows\System32\OpenSSH\ssh.exe."
}

function ConvertTo-ShellSingleQuoted {
  param([string]$Value)
  # 给远程 bash 命令使用的单引号转义。
  return "'" + ($Value -replace "'", "'\''") + "'"
}

try {
  $VpsHost = $env:VPS_HOST
  if (-not $VpsHost) {
    $VpsHost = Read-Host "Enter VPS IP or domain"
  }

  if (-not $VpsHost) {
    throw "VPS_HOST is empty"
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

  Write-Host "== Generate v2rayN link from VPS =="
  Write-Host "[info] SSH executable: $SshExe"
  Write-Host "[info] SSH target: $SshTarget"
  Write-Host "[info] SSH port: $SshPort"
  Write-Host "[info] Remote config: $RemoteConfigPath"

  $RemoteScript = @'
# 远端脚本使用保守的 set -eu，避免某些 SSH/PowerShell 组合下 pipefail 被兼容 shell 误解析。
set -eu

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

  # 不直接把多行脚本管道传给 ssh.exe，避免 Windows PowerShell 5.1 把换行或编码转换后导致远端 bash 解析失败。
  $RemoteScriptLf = $RemoteScript -replace "`r`n", "`n" -replace "`r", "`n"
  $RemoteScriptBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemoteScriptLf))
  $RemoteDecodeCommand = "printf %s $(ConvertTo-ShellSingleQuoted $RemoteScriptBase64) | base64 -d | bash"
  $RemoteCommand = "NODE_HOST=$(ConvertTo-ShellSingleQuoted $VpsHost) NODE_NAME=$(ConvertTo-ShellSingleQuoted $NodeName) REMOTE_CONFIG_PATH=$(ConvertTo-ShellSingleQuoted $RemoteConfigPath) bash -lc $(ConvertTo-ShellSingleQuoted $RemoteDecodeCommand)"

  $Raw = & $SshExe -p $SshPort $SshTarget $RemoteCommand 2>&1

  if ($LASTEXITCODE -ne 0) {
    Write-Host "[error] Remote generation failed:" -ForegroundColor Red
    $Raw
    throw "Failed to generate link on remote VPS"
  }

  $Base64Line = $Raw |
    Where-Object { $_ -match '^[A-Za-z0-9+/=]+$' } |
    Select-Object -Last 1

  if (-not $Base64Line) {
    $Raw
    throw "No base64 link output received"
  }

  $Link = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64Line))

  if (-not $Link.StartsWith("vless://")) {
    throw "Decoded output is not a vless:// link"
  }

  try {
    Set-Clipboard -Value $Link
  } catch {
    $Link | clip.exe
  }

  Set-Content -Path $OutputFile -Value $Link -Encoding ASCII

  Write-Host "[ok] Copied link to clipboard" -ForegroundColor Green
  Write-Host "[ok] Saved link to: $OutputFile" -ForegroundColor Green
  Write-Host "[info] Link length: $($Link.Length)"

  if ($Link -match 'pbk=([^&]+)') {
    Write-Host "[info] PublicKey length: $($Matches[1].Length)"
  }

  Write-Host "[next] Open v2rayN, then import share link from clipboard."
} catch {
  Write-Host "[error] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "[hint] Screenshot only the error text. Do not share the full vless-link.txt."
  exit 1
} finally {
  Wait-BeforeExit
}
