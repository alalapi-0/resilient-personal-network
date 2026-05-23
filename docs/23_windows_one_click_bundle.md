# 23 Windows 一键配置包

本文件说明如何生成 Windows 端的配置包。
它的目标是让 Windows 电脑尽量少手填参数，只通过 `vless://...` 分享链接导入。

## 1. 这个一键包会做什么

一键包会生成一个文件夹和一个 zip 压缩包，里面包含：

1. `vless-link.txt`：当前节点的 VLESS 分享链接。
2. `01-copy-link-and-open-v2rayn.ps1`：复制链接到 Windows 剪贴板，并打开 v2rayN 官方发布页。
3. `02-check-windows-connection.ps1`：检查 Windows 到节点端口是否通，并检查当前公网出口 IP。
4. `03-download-v2rayn-latest.ps1`：从 v2rayN 官方 GitHub Release 下载最新 Windows x64 便携包。
5. `README_WINDOWS.md`：Windows 端操作说明。

注意：压缩包包含真实节点链接，不要公开分享。

## 2. 生成一键包

在本机仓库根目录执行：

下面是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。
如果你在 Windows PowerShell 里生成配置包，请先看 `docs/25_cross_platform_command_guide.md` 的 `$env:` 写法。

```bash
bash scripts/build_windows_client_bundle.sh
```

输出位置类似：

```text
exports/windows-client/windows-vless-client-20260522-120000/
exports/windows-client/windows-vless-client-20260522-120000.zip
```

`exports/` 已被 `.gitignore` 忽略。

## 3. 传到 Windows

把生成的 zip 通过可信方式传到 Windows 电脑，例如：

1. 局域网共享。
2. 加密 U 盘。
3. 私有云盘。
4. 临时隔空投送到中转设备后再传输。

不要把这个 zip 发到公开群聊、公开网盘或不可信设备。

## 4. Windows 端使用步骤

在 Windows 上解压 zip 后：

1. 运行 `03-download-v2rayn-latest.ps1` 下载 v2rayN。
2. 解压并打开 v2rayN。
3. 运行 `01-copy-link-and-open-v2rayn.ps1`。
4. 在 v2rayN 中选择从剪贴板导入分享链接。
5. 选中导入的节点。
6. 启用系统代理。
7. 运行 `02-check-windows-connection.ps1` 做验收。

如果 Windows 阻止 PowerShell 脚本运行，可以右键脚本，选择“使用 PowerShell 运行”。
如果仍被策略拦截，可以手动复制 `vless-link.txt` 中的整行链接，然后在 v2rayN 中导入。

新版配置包中的 `.ps1` 脚本会在结束时等待你按回车。
如果窗口一闪而过，说明你使用的是旧配置包，请重新生成并传输最新 zip。

新版 `.ps1` 文件会写入 UTF-8 BOM，尽量避免 Windows PowerShell 5.x 把中文提示显示成乱码。
如果仍然乱码，但脚本能继续运行，优先看 `[ok]`、`[error]`、下载路径和 v2rayN 界面状态。

如果看到红色错误，先不要截图 `vless-link.txt`，只截图 PowerShell 错误文字。
如果错误和执行策略有关，可以在当前文件夹地址栏输入 `powershell`，打开窗口后执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\01-copy-link-and-open-v2rayn.ps1
```

`Scope Process` 只对当前 PowerShell 窗口生效，关闭窗口后自动失效。

如果 PowerShell 中出现 `VPS_HOST=... 无法识别` 之类错误，说明你把 Bash 环境变量写法复制到了 PowerShell。
Windows 端应使用 `$env:VPS_HOST="..."`，不要使用 `VPS_HOST="..." \`。

## 5. 为什么不直接自动写入 v2rayN

v2rayN 的内部配置格式会随版本变化。
直接修改它的配置文件有风险，可能导致客户端打不开或配置丢失。

本项目选择更稳的方式：

1. 自动准备链接。
2. 自动复制到剪贴板。
3. 自动打开官方下载页。
4. 由 v2rayN 自己完成导入。

这已经减少了最容易填错的部分，同时避免破坏客户端内部状态。

## 6. 验收标准

Windows 端完成后，应满足：

1. v2rayN 中出现当前节点。
2. 节点类型是 VLESS。
3. 启用系统代理后，浏览器可以打开网页。
4. `02-check-windows-connection.ps1` 显示节点端口连通。
5. `https://ipinfo.io` 显示 VPS 出口 IP。
