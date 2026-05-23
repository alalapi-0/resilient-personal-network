# 22 Windows 电脑端接入手册

本文件说明如何在 Windows 电脑上使用当前已经跑通的 VLESS + REALITY 节点。

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
官方 GitHub 仓库说明它是 Windows、Linux、macOS 图形客户端，并支持 Xray 和 sing-box。
官方发布文件说明中也写明 Windows 10+ 可用，并列出了 `v2rayN-windows-64.zip` 和 `v2rayN-windows-64-desktop.zip`。

官方地址：

```text
https://github.com/2dust/v2rayN
https://github.com/2dust/v2rayN/releases
https://github.com/2dust/v2rayN/wiki/Release-files-introduction
```

下载建议：

1. 普通 Windows 10/11 x64：优先选 `v2rayN-windows-64.zip`。
2. 如果你想试新版跨平台界面：可选 `v2rayN-windows-64-desktop.zip`。
3. 不确定时，先用 `v2rayN-windows-64.zip`。

## 3. 准备 Windows 可导入链接

当前项目已经能生成 `vless://...` 分享链接。
这个链接可以给 Shadowrocket 使用，也可以给 v2rayN 导入。

如果你想少手工操作，推荐直接生成 Windows 一键配置包：

```bash
bash scripts/build_windows_client_bundle.sh
```

详细说明请看：

```text
docs/23_windows_one_click_bundle.md
```

如果 `configs/client/shadowrocket_link.txt` 已经是最新的，可以直接运行：

```bash
bash scripts/prepare_windows_vless_link.sh
```

输出文件：

```text
configs/client/windows_vless_link.txt
```

注意：这个文件包含真实节点信息，已经被 `.gitignore` 忽略，不要公开分享。

如果你不确定链接是不是最新，先重新生成：

```bash
NODE_HOST="<你的_VPS_IP或域名>" \
XRAY_REALITY_PUBLIC_KEY="<REALITY公钥>" \
NODE_NAME="jp-tokyo-01" \
bash scripts/generate_shadowrocket_link.sh
```

然后再执行：

```bash
bash scripts/prepare_windows_vless_link.sh
```

## 4. 在 v2rayN 中导入

在 Windows 上打开 v2rayN 后，推荐用分享链接导入，不要手动填字段。

常见入口名称可能是：

1. `服务器`
2. `从剪贴板导入分享链接`
3. `导入分享链接`
4. 右键服务器列表后选择导入

操作顺序：

1. 将 `configs/client/windows_vless_link.txt` 里的整行 `vless://...` 链接放到 Windows 剪贴板。
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
