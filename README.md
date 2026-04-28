# resilient-personal-network

## 项目名称
**resilient-personal-network**（个人网络通道韧性管理仓库）

## 项目定位
这是一个长期维护型工程仓库，用于管理个人多节点网络通道的**文档、配置模板、脚本与运维流程**。  
本项目强调“工程化管理”，而不是“一次性脚本执行后就不再维护”。

## 当前阶段
当前处于 **Round 0（项目骨架阶段）**：
- 已建立目录结构与基础文档。
- 已准备初始化脚本与结构快照脚本。
- 尚未进行真实代理协议部署与服务端安装。

## 本项目不做什么（Round 0）
为了保证后续可控迭代，本轮明确不做以下事情：
1. 不安装任何真实服务端软件。
2. 不生成真实可用的代理配置。
3. 不写入真实服务器 IP、域名、UUID、私钥、订阅链接。
4. 不执行任何生产环境变更。

## 目录结构说明
```text
resilient-personal-network/
├── README.md
├── .gitignore
├── .env.example
├── docs/
│   ├── 00_project_overview.md
│   ├── 01_terms.md
│   ├── 02_architecture.md
│   ├── 03_security_notes.md
│   └── round_notes.md
├── scripts/
│   ├── init_project.sh
│   └── snapshot_tree.sh
├── configs/
│   ├── server/
│   │   └── .gitkeep
│   └── client/
│       └── .gitkeep
├── templates/
│   └── .gitkeep
├── nodes/
│   └── .gitkeep
├── logs/
│   └── .gitkeep
└── backups/
    └── .gitkeep
```

## 初始化方式
在仓库根目录执行：

```bash
bash scripts/init_project.sh
```

该脚本会：
- 按需创建标准目录与基础文件；
- 遇到已存在文件/目录时仅提示，不覆盖；
- 最后输出初始化完成信息。

## 快照生成方式
在仓库根目录执行：

```bash
bash scripts/snapshot_tree.sh
```

然后查看快照：

```bash
cat docs/tree_snapshot.txt
```

## 后续开发路线（建议）
1. **Round 1：节点清单与配置模板规范**
   - 约定 nodes 下每个节点的元数据模板。
   - 明确 configs/server 与 configs/client 模板字段。
2. **Round 2：配置生成 CLI 原型**
   - 实现本地命令行工具（仅生成模板，不部署）。
3. **Round 3：备份与回滚机制**
   - 为关键配置增加快照与恢复脚本。
4. **Round 4：状态检查与故障排查脚本**
   - 统一日志采集、连通性检查、常见故障定位。
5. **Round 5：多节点故障切换策略文档化与演练**
   - 编写切换策略、应急 SOP 和演练记录模板。

## 安全提醒
- 真实敏感数据只允许通过 `.env`（本地）或安全凭据系统管理。
- 仓库中仅保留模板与占位符。
- 提交前务必检查 `git diff`，避免泄露真实地址、密钥和链接。

## Round 0 验收命令
请按顺序执行以下命令：

```bash
bash scripts/init_project.sh
bash scripts/snapshot_tree.sh
cat docs/tree_snapshot.txt
```

若命令均成功，且 `docs/tree_snapshot.txt` 可读，则 Round 0 骨架验收通过。
