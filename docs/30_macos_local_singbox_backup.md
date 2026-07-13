# 30 Mac 本地 sing-box CLI 备用方案

本文件说明如何使用 Mac 上的 sing-box CLI，或项目内的备用二进制。
默认策略是：自动化只准备配置，不连接、不导入、不接管系统网络。

## 1. 选择 CLI 二进制

检查脚本按以下顺序选择二进制：

1. `SING_BOX_BIN` 显式指定的可执行文件路径。
2. `PATH` 中已安装的 `sing-box` CLI。
3. 项目内备用二进制 `tools/sing-box/sing-box`。

先检查 `PATH` 中是否可用：

```bash
command -v sing-box
```

如果没有输出，说明当前终端的 `PATH` 中没有可用 CLI；这不代表本项目已通过某种包管理器安装 sing-box。确定路径后再运行 `"$SING_BOX_BIN" version` 记录实际版本。
如果第一条返回路径，为下面的连接命令保存它：

```bash
export SING_BOX_BIN="$(command -v sing-box)"
```

如果 CLI 安装在自定义位置，显式设置绝对路径：

```bash
export SING_BOX_BIN="/absolute/path/to/sing-box"
```

如果要明确使用项目内备用二进制：

```bash
export SING_BOX_BIN="$PWD/tools/sing-box/sing-box"
```

## 2. Mac 配置

```text
configs/client/macos_singbox.json
configs/client/macos_singbox_mixed.json
```

用途：

| 文件 | 用途 |
| --- | --- |
| `macos_singbox.json` | TUN 模式，手动运行后接管系统流量 |
| `macos_singbox_mixed.json` | mixed 模式，只开放本地代理端口，适合低风险测试 |

这些配置包含真实节点信息，已被 `.gitignore` 忽略。
它们由统一刷新入口从 VPS 活跃配置派生；不要只更新其中一个文件。生成配置只是准备阶段，不会连接。

## 3. 只检查，不连接

在仓库根目录运行：

```bash
bash scripts/check_local_singbox_macos.sh
```

这个脚本只做：

1. 按上述顺序定位 `sing-box` CLI 并显示实际使用路径。
2. 检查两份 Mac 配置是否为有效 JSON。
3. 使用选中的 `sing-box check` 只读校验配置。
4. 检查 mixed 端口是否被占用。

它不会启动 sing-box，也不会修改系统网络。

## 4. 低风险 mixed 连接

这种方式不会自动接管系统网络，只启动本地 HTTP/SOCKS 代理端口。
以下命令假定已按第 1 节设置 `SING_BOX_BIN`；如果 `sing-box` 在 `PATH` 中，也可将 `"$SING_BOX_BIN"` 替换为 `sing-box`。

终端 1：

```bash
"$SING_BOX_BIN" run -c configs/client/macos_singbox_mixed.json
```

终端 2：

```bash
curl -x http://127.0.0.1:2080 https://ipinfo.io/ip
```

如果输出是 VPS IP，说明 sing-box 节点可用。
按 `Control + C` 停止终端 1，即可断开 mixed 测试。

## 5. TUN 手动连接

TUN 模式会接管系统流量。
不要和 Shadowrocket 同时开启。

先关闭 Shadowrocket 的连接，然后运行：

```bash
sudo "$SING_BOX_BIN" run -c configs/client/macos_singbox.json
```

macOS 会要求输入本机管理员密码。
连接后访问：

```text
https://ipinfo.io
```

如果出口 IP 是 VPS IP，说明 TUN 模式可用。
按 `Control + C` 停止，即可断开。

## 6. 停止连接

- mixed 和 TUN 都在运行命令所在终端按 `Control + C` 停止。
- mixed 停止后，如果你曾在其他应用或系统中手动设置 `127.0.0.1:2080` 代理，还需清除该代理设置。
- TUN 进程停止后会退出系统流量接管；如仍无法上网，先确认 Shadowrocket 和其他 VPN 状态。

## 7. 分流规则

当前配置是分流模式：

1. OpenAI / ChatGPT / OpenRouter / Cursor / Claude / Google / GitHub 显式走代理。
2. 大陆域名和大陆 IP 直连。
3. 局域网和私有地址直连。
4. 其他未匹配流量默认走代理。

## 8. 与 Shadowrocket 的关系

日常可以继续使用 Shadowrocket。
sing-box 只是本地备用方案。

可以同时保留两套配置，但不要同时让 Shadowrocket 和 sing-box TUN 接管系统流量。
