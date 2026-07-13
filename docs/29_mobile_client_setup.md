# 29 客户端统一刷新与移动端导入

本文件说明如何从 VPS 当前活跃的 Xray 配置统一派生客户端文件。生成、校验、导入和连接是不同步骤：脚本只准备并检查文件，不会启动代理或修改系统网络。

## 1. 默认安全的刷新入口

macOS / Linux / Git Bash / WSL 在仓库根目录使用 Bash：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
SSH_USER="root" \
SSH_PORT="22" \
RUN_BACKUP="no" \
UPDATE_XRAY="no" \
FETCH_REMOTE_CONFIG="yes" \
GENERATE_CLIENTS="yes" \
RUN_HEALTH_CHECK="yes" \
COPY_LINK_TO_CLIPBOARD="no" \
CONFIRM="yes" \
bash scripts/update_node_and_clients.sh
```

Windows PowerShell 必须使用 `$env:`，并确保 Git Bash 或 WSL 提供了 `bash`：

```powershell
$env:VPS_HOST="<你的_VPS_IP或域名>"
$env:SSH_USER="root"
$env:SSH_PORT="22"
$env:RUN_BACKUP="no"
$env:UPDATE_XRAY="no"
$env:FETCH_REMOTE_CONFIG="yes"
$env:GENERATE_CLIENTS="yes"
$env:RUN_HEALTH_CHECK="yes"
$env:COPY_LINK_TO_CLIPBOARD="no"
$env:CONFIRM="yes"
bash scripts/update_node_and_clients.sh
```

该流程只执行授权的远端读取和健康检查：拉取活跃配置、从其中的 REALITY 私钥派生公钥、生成本地文件并校验服务状态。默认不会远端备份、升级、重启、部署、恢复、改防火墙或轮换凭据，也不会启动 mixed/TUN、修改系统代理/VPN 或写剪贴板。

## 2. 八个客户端产物

- `configs/client/singbox.json`：通用 TUN/GUI 导入配置。
- `configs/client/macos_singbox.json`：macOS sing-box CLI 的 TUN 配置。
- `configs/client/macos_singbox_mixed.json`：macOS sing-box CLI 的 mixed 配置。
- `configs/client/shadowrocket_link.txt`：通用 VLESS + REALITY 导入链接。
- `configs/client/ios_shadowrocket_vless_link.txt`：iPhone/iPad Shadowrocket 链接。
- `configs/client/android_v2rayng_vless_link.txt`：Android v2rayNG/NekoBox 链接。
- `configs/client/shadowrocket.conf`：通用完整 Shadowrocket 配置，不包含 macOS 本地监听器。
- `configs/client/shadowrocket-macos.conf`：macOS 完整 Shadowrocket 配置，包含本地 HTTP/SOCKS 监听设置。

三个链接文件来自同一次生成且内容一致。三个 sing-box JSON、三个链接和两个 Shadowrocket 配置共用同一组服务端端口、UUID、flow、SNI、short ID 和派生公钥。

所有运行时文件必须保持 mode `600`，由 `.gitignore` 忽略且不得进入 Git。

## 3. 只读校验

```bash
bash scripts/validate_client_artifacts.sh
```

该命令检查：

1. 服务端镜像与八个客户端文件存在且权限正确。
2. 三个 sing-box JSON 通过 `jq` 和实际选择的 `sing-box check`。
3. 三个 VLESS 链接均为单行并与服务端字段一致。
4. 两个 Shadowrocket 配置包含相同节点字段和必需分流规则。
5. 所有关键字段跨产物一致，但不显示字段值。
6. 九个运行时文件均被忽略且未被 Git 跟踪。

校验通过只说明文件可供导入，不说明设备已经连接。

## 4. iPhone / iPad

可选择：

1. sing-box 图形客户端：导入 `configs/client/singbox.json`，随后由用户在 App 中启用 VPN Profile。
2. Shadowrocket：安全复制 `ios_shadowrocket_vless_link.txt` 的单行内容并导入，或导入 `shadowrocket.conf` 完整配置。

脚本默认不把链接复制到剪贴板。导入后实际开启 VPN 才会改变设备网络。

## 5. Android

可选择：

1. 支持 sing-box 配置的客户端：导入 `configs/client/singbox.json`。
2. v2rayNG、NekoBox 等支持 VLESS + REALITY 的客户端：导入 `android_v2rayng_vless_link.txt`。

导入后确认协议为 VLESS、传输为 TCP、安全层为 REALITY，再由用户手动连接。

## 6. macOS 与 Windows

macOS 图形客户端和 CLI 的区别、mixed/TUN 启动与停止方式见 `docs/30_macos_local_singbox_backup.md`。TUN 与 Shadowrocket 不得同时接管系统流量。

Windows v2rayN 可以导入同次刷新生成的 VLESS 链接；PowerShell 与 Bash 写法区别见 `docs/25_cross_platform_command_guide.md`。

## 7. Git 与部署边界

`git commit` 只记录本地仓库历史，`git push` 只发布代码。它们都不会刷新 VPS，也不等于部署。远端部署、升级、重启、备份和防火墙修改必须作为独立操作获得明确授权。
