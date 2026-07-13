# 22 Windows 电脑端接入手册

本文件说明如何在 Windows 电脑上使用当前已经跑通的 VLESS + REALITY 节点。

注意：Windows PowerShell 不能直接使用 `VPS_HOST="..." \` 这种 Bash 多行写法。
如果要在 PowerShell 中运行仓库里的 `scripts/*.sh`，请使用 `$env:变量名="值"`，完整示例见 `docs/25_cross_platform_command_guide.md`。

## 1. 先判断：你截图里的客户端不能直接用

你截图中的界面包含这些字段：

1. 服务器地址
2. 服务器端口
3. 密码
4. 加密方式，例如 `chacha20-ietf-poly1305`
5. 插件程序和插件选项

这是 Shadowsocks 类型客户端的配置界面。
而当前项目的服务端是：

```text
VLESS + REALITY + XTLS Vision
```

它需要的字段是：

1. VPS 地址或域名
2. 端口
3. UUID
4. flow
5. REALITY public key
6. shortId
7. SNI / serverName
8. fingerprint

所以不要在截图那个界面里硬填。
`8388`、密码、加密方式这些字段不适用于当前节点。

## 2. 推荐 Windows 客户端

Windows 端建议使用 **v2rayN**。

官方地址：

```text
https://github.com/2dust/v2rayN
https://github.com/2dust/v2rayN/releases
```

发布文件名、系统要求和安装方式可能变化。下载时以官方仓库当时的 Release 说明为准，不依据本文猜测具体包名。

## 3. 准备 Windows 可导入链接

当前项目已经能生成 `vless://...` 分享链接。
这个链接可以给 Shadowrocket 使用，也可以给 v2rayN 导入。

如果你的目标只是让 Windows 电脑连上现有节点，不需要重新运行 `scripts/vps_init.sh` 或 `scripts/install_xray.sh`。
那两个脚本是 VPS 服务端初始化和安装脚本，Windows 客户端阶段只需要准备分享链接或一键包。

### 3.1 推荐：统一刷新后传入 Windows

在能运行 Bash 的仓库环境中执行统一刷新。Windows PowerShell 写法：

```powershell
$env:VPS_HOST="<你的_VPS_IP或域名>"
$env:RUN_BACKUP="no"
$env:UPDATE_XRAY="no"
$env:FETCH_REMOTE_CONFIG="yes"
$env:GENERATE_CLIENTS="yes"
$env:RUN_HEALTH_CHECK="yes"
$env:COPY_LINK_TO_CLIPBOARD="no"
$env:CONFIRM="yes"
bash scripts/update_node_and_clients.sh
```

然后通过受控方式把 `configs/client/android_v2rayng_vless_link.txt` 传到 Windows 并导入 v2rayN。它与 iOS、通用链接来自同一次服务端派生。准备文件不会启用 v2rayN 或系统代理。

### 3.2 显式备用：Windows 远端生成脚本

下面的备用脚本会执行远端读取，并把真实链接写入桌面文件和 Windows 剪贴板。它不属于默认安全刷新流程；只有明确需要这些副作用时才运行。

在 Windows PowerShell 中进入仓库根目录，例如：

```powershell
cd D:\ProgramData\resilient-personal-network\resilient-personal-network
```

然后运行：

```powershell
$env:VPS_HOST="<你的_VPS_IP或域名>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
powershell -ExecutionPolicy Bypass -File .\scripts\windows_generate_vless_link_from_vps.ps1
```

不要继续运行桌面上旧的 `make-vless-link.ps1`。如果它出现乱码或语法错误，说明旧文件被 Windows PowerShell 5.1 按错误编码读取了。
新版 `windows_generate_vless_link_from_vps.ps1` 的可执行提示文本已经改为 ASCII，避免 PowerShell 5.1 解析中文字符串时出错。

这个脚本会做几件事：

1. 显式调用 `C:\Windows\System32\OpenSSH\ssh.exe`，避免 `ssh` 命令被异常同名文件抢占。
2. 通过 SSH 读取 VPS 上的 `/usr/local/etc/xray/config.json`。
3. 在 VPS 上使用已经安装好的 `jq` 和 `xray` 计算 VLESS + REALITY 分享链接。
4. 不在屏幕上打印完整链接。
5. 把链接复制到 Windows 剪贴板，并保存到桌面的 `vless-link.txt`。

如果你前面执行过下面这条命令，并且返回了 `ok`，说明 SSH 通道已经满足脚本要求：

```powershell
& "$env:WINDIR\System32\OpenSSH\ssh.exe" -p 22 root@<你的_VPS_IP或域名> "echo ok"
```

注意：桌面的 `vless-link.txt` 包含真实节点信息，导入后请妥善保存或删除，不要发到公开聊天或截图里。

### 3.3 从本机已有链接准备 Windows 文件

优先使用统一刷新生成的 `android_v2rayng_vless_link.txt`；v2rayN 可导入同一个 VLESS + REALITY 链接。不要为了 Windows 单独重新生成一组凭据或只刷新一个链接文件。

仓库中的 Windows 一键包属于额外分发方式，可能写入导出目录、桌面或剪贴板。需要这些副作用时再查阅 `docs/23_windows_one_click_bundle.md`，不要把它与默认只准备八个客户端产物的流程混在一起。

## 4. 在 v2rayN 中导入

在 Windows 上打开 v2rayN 后，推荐用分享链接导入，不要手动填字段。

常见入口名称可能是：

1. `服务器`
2. `从剪贴板导入分享链接`
3. `导入分享链接`
4. 右键服务器列表后选择导入

操作顺序：

1. 通过受控方式将 `configs/client/android_v2rayng_vless_link.txt` 的单行链接放到 Windows 剪贴板。
2. 在 v2rayN 中选择从剪贴板导入分享链接。
3. 导入后选择该节点。
4. 启用系统代理。
5. 打开浏览器访问 `https://ipinfo.io`。

如果出口 IP 显示为 VPS，说明 Windows 端连接成功。

## 5. 不建议手动填写的原因

VLESS + REALITY 的字段比较多，手动填写容易错：

1. UUID 少一位或多一位。
2. public key 和 private key 混用。
3. shortId 填错。
4. SNI 没有和服务端 `serverNames` 一致。
5. flow 没有设置为 `xtls-rprx-vision`。
6. fingerprint 漏填。

分享链接能把这些字段一次性带过去，适合初次配置。

## 6. 常见问题

### 6.1 只有服务器、端口、密码、加密方式

这说明你打开的是 Shadowsocks 配置界面。
当前节点不是 Shadowsocks，不能用这套字段。

处理方式：换 v2rayN，或者使用支持 VLESS + REALITY 的 Windows 客户端。

### 6.2 导入后节点存在，但网页打不开

按顺序检查：

1. v2rayN 是否已经启动。
2. 是否选择了正确节点。
3. 是否启用了系统代理。
4. VPS 的 `443/tcp` 是否仍然通。
5. 手机或 Mac 是否仍然能连接同一节点。

如果手机和 Mac 都能连，Windows 不能连，问题多半在 Windows 客户端或系统代理设置。

### 6.3 v2rayN 提示 core 缺失

重新下载包含 core 的发布包，或按照 v2rayN 文档补齐 core。
初学者建议优先下载官方发布说明推荐的 Windows x64 包。

### 6.4 Windows 安全软件拦截

如果 v2rayN 无法启动或无法代理流量，检查 Windows 安全软件是否拦截了程序或 core。
只从官方 GitHub 下载，避免使用来源不明的改包。

## 7. 验收标准

Windows 端验收通过应满足：

1. v2rayN 能导入 `vless://...` 链接。
2. 节点类型显示为 VLESS。
3. 启用系统代理后浏览器能打开网页。
4. `https://ipinfo.io` 显示 VPS 出口 IP。
