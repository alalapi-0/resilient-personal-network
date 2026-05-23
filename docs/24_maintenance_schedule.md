# 24 稳定节点维护计划

本文件回答一个常见问题：节点已经稳定运行一个月，还需要定期更新吗？

结论：
稳定节点不需要频繁折腾配置，但需要有节奏地做健康检查、备份、安全更新和续费检查。

本文件里的定期检查命令是 Bash 写法，适用于 macOS / Linux / Git Bash / WSL。
Windows PowerShell 请看 `docs/25_cross_platform_command_guide.md`，不要直接复制末尾带 `\` 的多行命令。

## 1. 不建议频繁改什么

如果节点稳定，不建议频繁改这些内容：

1. UUID。
2. REALITY 私钥 / 公钥。
3. shortId。
4. SNI / serverName。
5. flow。
6. 服务端端口。
7. Xray 主版本。

这些参数一改，所有客户端都要同步更新。
没有明确原因时，稳定优先。

## 2. 建议定期做什么

### 每周

1. 用手机或电脑访问 `https://ipinfo.io`，确认出口 IP 正常。
2. 简单确认常用网站能打开。
3. 如果发现异常，先运行健康检查脚本：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/check_xray_health.sh
```

### 每月

1. 备份一次当前远程配置：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/backup_remote_xray.sh
```

2. 检查 VPS 磁盘、内存、服务状态。
3. 检查 VPS 账单和续费日期。
4. 检查 UFW 是否仍然只开放必要端口。

### 每 1 到 3 个月

1. 查看 Xray-core 是否有重要安全更新。
2. 查看客户端是否提示协议或配置弃用。
3. 如果没有安全更新、没有异常、没有兼容问题，可以暂时不升级。

### 每 6 到 12 个月

1. 评估是否需要轮换 UUID 和 REALITY 密钥。
2. 检查是否需要新增备用 VPS。
3. 清理旧备份，只保留可信、可恢复的版本。

## 3. 什么时候必须更新

出现这些情况时，应考虑更新：

1. Xray-core 发布明确安全修复。
2. 客户端提示当前配置字段即将废弃。
3. 节点突然大面积无法连接，且不是防火墙或网络问题。
4. 怀疑配置文件、链接、截图泄露。
5. VPS 系统存在高危安全更新。

## 4. 更新前必须做什么

更新前先备份：

```bash
VPS_HOST="<你的_VPS_IP>" \
SSH_USER="root" \
SSH_PORT="22" \
bash scripts/backup_remote_xray.sh
```

确认备份包已经下载到本机 `backups/` 后，再执行升级或配置修改。

## 5. 系统更新建议

Ubuntu 上可以定期安装安全补丁，但不要随手做大版本升级。

可以做：

```bash
apt-get update
apt-get upgrade
```

谨慎做：

```bash
do-release-upgrade
```

大版本升级可能改变系统服务、内核、防火墙行为。
如果节点稳定，不建议在没有备份和恢复窗口的情况下升级系统大版本。

## 6. Xray 更新建议

如果当前 Xray 稳定，不需要每周更新。
建议在这些情况下更新：

1. 有安全修复。
2. 新客户端要求较新版本。
3. 当前版本存在已知连接问题。
4. 你准备做一次有备份的维护窗口。

更新后必须验证：

1. `systemctl status xray --no-pager -l`
2. `ss -lntp | grep ':443'`
3. `ufw status verbose`
4. 手机或电脑访问 `https://ipinfo.io`

## 7. 密钥轮换建议

如果没有泄露迹象，UUID、REALITY 密钥和 shortId 不需要频繁轮换。
如果发生以下情况，应立即轮换：

1. 配置文件发给了不可信的人。
2. `vless://...` 链接发到了公开环境。
3. 截图包含完整 UUID、公钥、shortId。
4. 电脑或手机丢失，且里面保存了完整节点配置。

轮换后要重新部署服务端，并重新生成所有客户端配置。
