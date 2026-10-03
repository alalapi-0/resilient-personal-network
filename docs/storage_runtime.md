# 本机独立运行时

Linux 的程序为 `/home/alalapi/Runtimes/resilient-personal-network/sing-box`，临时和缓存根分别为 `/home/alalapi/Temp/resilient-personal-network`、`/home/alalapi/Caches/resilient-personal-network`。固定版本为官方 [sing-box 1.12.3](https://github.com/SagerNet/sing-box/releases/tag/v1.12.3)，用于保持现有生成器的版本边界；这不表示使用最新版。安装身份记录在运行时根的 `linux-runtime-manifest.json`，程序 SHA-256 同时由源码守卫固定。

在 `/home/alalapi/Projects/resilient-personal-network` 执行：

```bash
bash scripts/external-sing-box version
bash scripts/external-sing-box help
env -i PATH=/usr/bin:/bin bash scripts/test_client_generation.sh --json
```

`scripts/lib/storage_runtime.sh` 按实际系统分派。Linux 使用 Python 标准库检查正式项目路径、运行时、Temp、Cache 的真实路径、UID 1000、权限和登记的 ext4 UUID，以及程序类型、执行权限和 SHA-256。Temp/Cache 根权限必须为 700。缺失、重定向、错盘、任意 `SING_BOX_BIN` 覆盖均拒绝，退出 78；不下载、不修复、不回退 PATH 或仓库程序。

Darwin 使用 `scripts/lib/storage_runtime_macos.sh`，保留迁移前守卫的原始字节。其 `/Volumes/AI_WORK_SSD` 程序、Temp、原 Mac 全局守卫及 zsh/Ruby 要求保持原样。Linux 不执行 Mac 运行时；本次不代表重新验收真实 Mac 外盘。其他机器需要自己的明确登记路径，不能机械使用本机绝对路径。

JSON 入口记录实际所用二进制、代码与程序的前后 SHA-256、九个产物、四项正例、十二项负例以及临时目录清理。旧版 iOS 1.11.4 仍只检查 schema，实际二进制检查明确为 `not_run`，不会冒充通过。

验证使用占位数据。工作站验收在私有网络/PID 隔离中运行：源码与运行时只读，真实配置等保护位置遮蔽，仅项目 Temp/Cache 可写；隔离 `/tmp` 映射同一项目 Temp，供匿名事件文件使用，宿主 `/tmp` 不可写。命名 fixture 目录权限 700、生成文件权限 600，结束后清理。

生成和 `check` 不代表连接。恢复不运行 sing-box `run`、不启动 mixed/TUN、代理或 VPN、不访问 VPS、不读取或导入真实配置和账号数据。真实 configs、连接密钥、backups、logs、exports、nodes 继续保护。README 的“当前阶段”是仓库摘要，活跃 VPS 配置仍是另一项敏感运行状态。

运行时丢失时应先核实登记路径、官方资产与 manifest 的 SHA-256，再在独立安装步骤恢复；普通校验入口不自动重建，也不替换当前系统代理程序。源码及 Git 交付不包含程序、缓存、fixture 或真实配置。
