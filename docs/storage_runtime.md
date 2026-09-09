# 本机外盘运行时

本地 sing-box 程序存放在 `/Volumes/AI_WORK_SSD/Runtimes/resilient-personal-network/sing-box`。当前仓库状态摘要为 README 的“当前阶段”；活跃 VPS 配置仍是独立敏感运行状态，不由 Hub 读取或替代。

```bash
bash scripts/external-sing-box version
bash scripts/external-sing-box help
env -i PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bash scripts/test_client_generation.sh
```

三个本地校验入口共用 `scripts/lib/storage_runtime.sh`。守卫验证外盘 Volume/Container 身份后才选用固定程序，临时文件指向本项目外盘 Temp 根。缺盘、错盘、路径别名或程序缺失退出非零，不回退 PATH 或内盘。`SING_BOX_BIN` 只接纳登记程序或守卫入口。原 tools/sing-box/sing-box 只是指向该入口的兼容链接，没有第二份内盘程序。

这是所有者当前存储治理“禁止内盘静默回退”要求对旧二进制发现顺序的明确覆盖；不改全局 PATH、代理或 Codex/Cursor 配置。旧文档及 AGENTS 中的 PATH fallback 描述不适用于本机受治理的入口。其他机器应显式配置自己的运行时，不能把本机绝对路径当成通用安装器。

验证仅运行实际程序 version/help 和项目现有的占位客户端生成/只读 check，不执行 sing-box run，不启用 TUN、mixed 连接或系统代理，不访问 VPS。输出中的版本只是实际搬迁程序的观察结果，不表示已更新到最新版。

真实 configs、连接密钥、backups、logs、exports、nodes 原位保护，未读取、迁移或删除；源码与 Git 留内盘。外盘是已搬迁程序的恢复来源；可从迁移证据核对该单文件的 SHA-256。维护时先恢复正确外盘，再使用上面的入口；不要自动下载程序或重建内盘副本。
