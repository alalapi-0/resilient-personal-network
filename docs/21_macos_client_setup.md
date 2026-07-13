# 21 Mac 电脑端 sing-box 接入手册

本文件对应 Round 5。
iPhone 已经完成连接验收，Mac 端不需要重新搭建 VPS，只需要复用同一套 VLESS + REALITY 节点配置。

本文件面向 macOS，命令示例默认使用 Bash/zsh 可执行写法。
如果你要在 Windows PowerShell 运行同类仓库脚本，请看 `docs/25_cross_platform_command_guide.md`。

## 1. 本轮任务清单

### 文件生成

1. `scripts/check_macos_singbox.sh`
2. `scripts/copy_shadowrocket_link_macos.sh`
3. `docs/21_macos_client_setup.md`

### 脚本生成

1. Mac 本地配置检查脚本。
2. Mac 到 VPS TCP 端口连通性检查。
3. Mac 当前公网出口 IP 检查。
4. Mac Shadowrocket 链接复制脚本。

### 文档生成

1. Mac sing-box VT 导入流程。
2. macOS VPN Profile 授权说明。
3. Mac 端连接验收步骤。
4. iPhone 与 Mac 共用节点配置的注意事项。
5. Shadowrocket Mac 备用方案。

### README 更新

README 会加入 Mac 端接入入口和 Round 5 验收命令。

### 验收标准

1. `configs/client/singbox.json` 可以通过 JSON 检查。
2. Mac 能连通 VPS 的 TCP 端口。
3. sing-box VT 启用后，Mac 浏览器访问 `ipinfo.io` 显示 VPS 出口 IP。
4. `scripts/check_macos_singbox.sh` 运行后能看到配置和端口检查通过。

## 2. 推荐客户端

Mac 端优先使用 **sing-box VT**。
原因是你在 iPhone 上已经用 sing-box VT 跑通，同一份 `tun` 模式配置可以直接复用到 Mac。

如果你已经在 Mac App Store 安装 sing-box VT，就继续下面步骤。
如果还没安装，请从 sing-box 官方文档进入当前 Apple 客户端入口，再核对 App Store 发布者；本文不固定声称某个商店版本或安装方式仍然有效。

如果 App Store 没有下载按钮、按钮一直转圈，或者账号确认弹窗卡住，可以先跳过 sing-box VT。
你已经安装了 Shadowrocket 的情况下，也可以使用同次统一刷新生成的 Shadowrocket 配置；不要根据历史端口状态推断当前一定可连接。

## 3. 生成 Mac 可用配置

Mac 和 iPhone 共用同一套服务端凭据，但 GUI 与 CLI 使用不同命名的本地产物。推荐运行统一刷新入口：

```bash
VPS_HOST="<你的_VPS_IP或域名>" \
RUN_BACKUP="no" \
UPDATE_XRAY="no" \
FETCH_REMOTE_CONFIG="yes" \
GENERATE_CLIENTS="yes" \
RUN_HEALTH_CHECK="yes" \
COPY_LINK_TO_CLIPBOARD="no" \
CONFIRM="yes" \
bash scripts/update_node_and_clients.sh
```

Mac 相关文件：

```text
configs/client/singbox.json
configs/client/macos_singbox.json
configs/client/macos_singbox_mixed.json
configs/client/shadowrocket.conf
configs/client/shadowrocket-macos.conf
```

`singbox.json` 供图形客户端导入；后两个 macOS sing-box 文件分别供 CLI TUN 和 mixed 使用。准备这些文件不会启动代理。它们包含真实节点信息，已经被 `.gitignore` 忽略，不要提交或公开分享。

## 4. 导入到 Mac sing-box VT

打开 Mac 上的 sing-box VT，按应用界面选择导入本地配置文件。
不同版本界面名称可能略有差异，通常会在 `Profiles`、`配置`、`Import`、`从文件导入` 一类入口中。

选择这个文件：

```text
configs/client/singbox.json
```

导入后建议把配置命名为：

```text
jp-tokyo-01
```

或你自己容易识别的名字。

## 5. 启用 VPN Profile

Mac 第一次启用 TUN/VPN 模式时，macOS 可能弹出系统授权。
请允许 sing-box VT 添加 VPN 配置。

如果没有弹窗，或启用失败，可以检查：

1. macOS `系统设置`。
2. `VPN` 或 `网络`。
3. 是否存在 sing-box VT 相关 VPN 配置。
4. 是否已经允许该配置连接。

如果系统提示需要管理员密码，这是 macOS 对 VPN Profile 的正常授权要求。
这个密码不会进入本项目脚本或配置。

## 6. 启用前检查

导入配置前，先在仓库根目录执行：

```bash
EXPECTED_EXIT_IP="<你的_VPS_IP>" \
bash scripts/check_macos_singbox.sh
```

如果你还没有开启 sing-box，公网出口 IP 不一致是正常的。
这一步主要确认：

1. `configs/client/singbox.json` 格式正确。
2. 配置是 `tun` 模式。
3. Mac 可以连通 VPS 的 TCP 端口。

## 7. 启用后验收

在 Mac sing-box VT 中启用配置后，再执行：

```bash
EXPECTED_EXIT_IP="<你的_VPS_IP>" \
bash scripts/check_macos_singbox.sh
```

如果看到：

```text
[ok] 当前出口 IP 与预期 VPS IP 一致
```

说明 Mac 端已经通过验收。

也可以在浏览器访问：

```text
https://ipinfo.io
```

如果页面显示的是 VPS 的 IP、地区和云厂商信息，也说明成功。

## 8. mixed 模式备用方案

默认推荐 `tun` 模式，因为它能接管系统流量，体验更接近 iPhone。

如果 Mac 上 TUN/VPN 授权一直失败，可以使用统一刷新生成的 CLI mixed 配置。先只读校验：

```bash
bash scripts/check_local_singbox_macos.sh
```

校验不会连接。先按 `docs/30_macos_local_singbox_backup.md` 选择并设置 `SING_BOX_BIN`；实际启动必须由用户另开终端运行 `"$SING_BOX_BIN" run -c configs/client/macos_singbox_mixed.json`，并在结束时按 `Control + C`。mixed 模式只在本机监听：

```text
127.0.0.1:2080
```

这种模式需要你手动给浏览器或系统设置 HTTP/SOCKS 代理。
除非 TUN 模式无法使用，否则不建议作为第一选择。

## 9. Shadowrocket Mac 备用方案

如果 Mac 上已经安装 Shadowrocket，可以直接重新导入当前节点链接。
建议不要手动逐项填写，优先使用脚本生成的 `vless://...` 链接，减少 UUID、公钥、shortId 或 SNI 填错的机会。

### 9.1 重新生成 Shadowrocket 链接

使用第 3 节的统一入口刷新，不要只更新链接而保留旧的其他客户端文件。

生成文件：

```text
configs/client/shadowrocket_link.txt
```

该文件包含真实节点链接，已经被 `.gitignore` 忽略。

### 9.2 复制链接到剪贴板

只有你明确需要把真实链接写入 macOS 剪贴板时才执行：

```bash
bash scripts/copy_shadowrocket_link_macos.sh
```

脚本会先校验链接字段，再复制到剪贴板。
它不会在终端显示完整 `vless://...` 链接。

### 9.3 在 Shadowrocket 中导入

打开 Shadowrocket，选择从剪贴板或 URL 导入。
导入后确认节点类型显示为 VLESS，并在 TLS / REALITY 页面核对：

1. `SNI` 与服务端 `serverNames` 一致。
2. `Public Key` 存在。
3. `Short ID` 存在。
4. `Flow` 是 `xtls-rprx-vision`。
5. 地址是 VPS IP 或域名。
6. 端口是 `443` 或你服务端实际监听端口。

### 9.4 Shadowrocket 验收

启用 Shadowrocket 后，在浏览器打开：

```text
https://ipinfo.io
```

如果出口 IP 显示为 VPS，说明 Mac Shadowrocket 接入成功。

如果 Shadowrocket 仍然连不上，但 sing-box/iPhone 已经可用，优先删除旧节点后重新导入。
之前的失败节点可能仍保留旧参数。

## 10. iPhone 和 Mac 共用配置的注意事项

1. 可以共用同一个 UUID、公钥、shortId、SNI 和端口。
2. 两台设备同时连接通常没有问题。
3. 如果以后要区分设备流量，可以在服务端增加多个客户端 UUID。
4. 不要把配置文件通过公开聊天、截图或网盘公开链接传播。
5. 如果怀疑配置泄露，应该重新生成 UUID、REALITY 密钥和 shortId，并重新部署服务端。

## 11. 常见问题

### 11.1 Mac App Store 没有下载按钮

如果 sing-box VT 页面没有下载按钮，只显示账号确认或一直转圈，常见原因是：

1. App Store 登录状态卡住。
2. 当前 Apple ID 地区或购买记录需要刷新。
3. App Store 下载队列卡住。
4. macOS 版本或设备兼容状态需要商店重新判断。
5. 网络或 Apple 服务临时异常。

可以尝试：

1. 关闭 App Store 后重新打开。
2. 在 App Store 左下角退出账号再登录。
3. 重启 Mac。
4. 检查 App Store 的“已购项目”。
5. 暂时先用 Shadowrocket，不阻塞当前项目。

### 11.2 Mac 可以连端口，但启用后出口 IP 没变

常见原因：

1. sing-box VT 配置没有真正启用。
2. macOS 没有允许 VPN Profile。
3. 导入的是旧配置或 mixed 配置。
4. 浏览器用了自己的代理或安全 DNS 设置。

处理顺序：

1. 确认 sing-box VT 里当前配置处于启用状态。
2. 确认 `configs/client/singbox.json` 的 `inbounds[0].type` 是 `tun`。
3. 重新运行 `scripts/check_macos_singbox.sh`。
4. 打开 `https://ipinfo.io` 再看出口 IP。

### 11.3 Mac 无法连通 VPS TCP 端口

如果脚本提示：

```text
[error] Mac 无法连通节点 TCP 端口
```

优先检查：

1. VPS 上 Xray 是否运行。
2. VPS UFW 是否放行 `443/tcp`。
3. 云厂商防火墙是否放行 `443/tcp`。
4. 本机网络是否能访问该 VPS。

可以运行：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/check_xray_health.sh
```

### 11.4 sing-box 提示旧配置弃用

如果客户端提示旧字段或配置不兼容，不要启用兼容绕过。重新运行第 3 节统一刷新，再执行只读检查：

```bash
bash scripts/validate_client_artifacts.sh
```

检查通过后重新导入；这一步仍不代表已经连接。

### 11.5 Shadowrocket 重新导入后仍超时

处理顺序：

1. 确认 iPhone 或 sing-box 仍然能连，排除 VPS 故障。
2. 删除 Mac Shadowrocket 里的旧节点。
3. 重新运行 `scripts/generate_shadowrocket_link.sh`。
4. 运行 `scripts/copy_shadowrocket_link_macos.sh`。
5. 从剪贴板重新导入。
6. 如果仍失败，检查节点详情里的 SNI、公钥、shortId 和 flow。

## 12. Round 5 完成状态

Round 5 完成后，你应该可以：

1. 在 Mac 上导入 sing-box 配置。
2. 允许 macOS VPN Profile。
3. 启用后让 Mac 出口 IP 变成 VPS。
4. 在 sing-box VT 暂时不可下载时，使用 Shadowrocket 作为备用客户端。
5. 用脚本完成基础自检。
