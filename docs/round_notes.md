# Round Notes

## Round 0 目标
- 建立长期维护型工程仓库骨架；
- 创建基础目录、脚本与初版文档；
- 建立敏感信息管理边界；
- 为后续多轮开发打基础。

## Round 0 完成内容
- 已创建 `docs/`、`scripts/`、`configs/`、`templates/`、`nodes/`、`logs/`、`backups/` 等核心目录。
- 已创建 `scripts/init_project.sh` 与 `scripts/snapshot_tree.sh`。
- 已创建项目总览、术语、架构、安全说明文档。
- 已提供 `.env.example` 与 `.gitignore` 约束。

## Round 0 不包含内容
- 不安装真实服务端软件。
- 不生成真实可连接配置。
- 不执行任何生产环境部署。
- 不进行真实节点连通性测试。

## Round 0.5：托管订阅服务策略

### 本轮目标
在现有“自建 VPS 节点 + 自维护配置”路线之外，加入 Shadowrocket + 机场订阅这一现实可用路线，形成可长期维护的策略框架。

### 完成内容
- 新增 `docs/05_managed_provider_strategy.md`，系统分析自建、托管订阅、混合模式。
- 更新 `README.md`，补充路线选择说明与文档入口。
- 在项目文档中明确敏感信息处理边界与后续迭代计划。

### 不包含内容
- 不推荐具体机场。
- 不写真实订阅链接。
- 不部署服务端。
- 不生成真实客户端配置。

### 下一轮计划
Round 0.6：建立 `subscriptions/` 目录与服务质量评估模板。

## 下一轮 Round 1 目标
创建 VPS 初始化脚本与文档，让用户在准备好 VPS 后，可以按步骤完成基础依赖安装、目录创建和初始安全设置。

## Round 1 计划任务
1. 生成 `scripts/vps_init.sh`，包含基础依赖安装、项目目录创建和日志目录创建。
2. 生成 `docs/10_vps_init.md`，用初学者能理解的方式说明 VPS 初始化步骤。
3. 更新 `README.md`，加入如何准备 VPS、域名注册和 DNS 配置提示。
4. 更新本文件，记录 Round 1 完成内容和 Round 2 计划。

## Round 1 开始前需要用户提供的信息
1. VPS 公网 IP 或绑定域名。
2. SSH 登录用户，通常是 `root` 或云厂商创建的管理员用户。
3. SSH 端口，默认通常是 `22`。
4. 是否已经拥有一个可解析到 VPS 的域名。

## Round 1 已收到的信息
1. VPS 已创建。
2. SSH 已配置完成。
3. SSH 用户为 `root`。
4. SSH 端口为默认 `22`。
5. 暂无域名。
6. 本机登录时可能需要输入一次私钥密码或系统钥匙串密码，此信息不会写入仓库。

## Round 1 完成内容
1. 新增 `scripts/vps_init.sh`，用于通过 SSH 初始化 VPS。
2. 新增 `docs/10_vps_init.md`，说明 VPS 初始化步骤和验收方式。
3. 更新 `README.md`，加入 VPS 准备、初始化方式、域名和 DNS 提示。
4. 更新 `.env.example`，加入 Round 1 所需占位符。

## Round 1 验收标准
1. 执行 `bash scripts/vps_init.sh`。
2. SSH 能连上 VPS。
3. VPS 上存在 `/opt/resilient-personal-network`。
4. VPS 上存在 `/opt/resilient-personal-network/logs/vps_init.log`。

## Round 1 验收结果
1. 已确认可以通过 SSH 登录 VPS。
2. 已确认 `/opt/resilient-personal-network` 存在。
3. 已确认 `/opt/resilient-personal-network/logs/vps_init.log` 存在。
4. Round 1 验收通过。

## Round 2 计划
1. 生成 `scripts/install_xray.sh`。
2. 生成 `templates/xray_server_vless_reality.json.template`。
3. 生成 `docs/11_install_xray.md`。
4. 更新 README，说明如何上传配置到 VPS 并启动服务端。

## Round 2 完成内容
1. 新增 `scripts/install_xray.sh`，用于安装 Xray-core 和 systemd 服务文件。
2. 新增 `templates/xray_server_vless_reality.json.template`，提供 VLESS + REALITY 服务端配置模板。
3. 新增 `docs/11_install_xray.md`，解释安装、占位符、配置上传和服务启动方法。
4. 更新 `.env.example`，加入 Round 2 所需占位符。
5. 更新 `README.md`，加入 Xray 安装、配置上传和服务启动说明。

## Round 2 当前状态
1. 本地文件生成完成。
2. 脚本语法检查通过。
3. 配置模板在替换示例占位符后可通过 JSON 校验。
4. 远程 Xray 安装需要用户在终端输入 SSH 私钥密码后执行。
5. 已根据实际启动报错修正文档：`xray.service` 以 `xray` 用户运行，配置文件权限应为 `root:xray` + `640`，不能使用 `root:root` + `600`。
6. 已补充服务端配置字段解释，明确 `${XRAY_LOG_LEVEL}`、`${XRAY_PORT}`、`${XRAY_FLOW}`、`${XRAY_CLIENT_NAME}`、`${XRAY_REALITY_DEST}`、`${XRAY_SERVER_NAME}` 的填写方式。
7. 已新增 `scripts/validate_xray_config.sh`，用于在上传前校验服务端配置，不打印真实敏感值。
8. 已验证当前本地 `configs/server/config.json` 仍未通过校验，不能上传覆盖远程 VPS。
9. 已新增 `scripts/deploy_xray_config.sh`，用于把已校验的本地配置安全部署到 VPS，并自动备份旧配置、设置权限、重启服务。

## Round 2 验收结果
1. 已确认 Xray 服务端安装完成。
2. 已确认 `/usr/local/etc/xray/config.json` 权限修复为 `root:xray` + `640` 后可被 `xray` 用户读取。
3. 已确认 `systemctl status xray --no-pager -l` 显示 `active (running)`。
4. 已执行 `scripts/deploy_xray_config.sh`，完成本地校验、远程临时上传、旧配置备份、权限设置和服务重启。
5. 已确认部署后 `xray.service` 为 `active (running)`。
6. Round 2 服务端启动验收通过。

## Round 2 验收标准
1. 执行 `bash scripts/install_xray.sh`。
2. VPS 上存在 `/usr/local/bin/xray`。
3. VPS 上存在 `/etc/systemd/system/xray.service`。
4. VPS 上存在 `/opt/resilient-personal-network/logs/xray_install.log`。
5. 使用模板生成真实 `config.json` 前，不要求 Xray 服务处于运行状态。

## 下一轮 Round 3 计划
1. 生成 `templates/singbox_client_template.json`。
2. 生成 `templates/client_link_template.txt`。
3. 生成 `docs/12_client_config_explained.md`。
4. 更新 README，说明客户端配置导入和初次连接检查。

## Round 3 完成内容
1. 新增 `templates/singbox_client_template.json`，提供 sing-box 单节点客户端配置模板。
2. 新增 `templates/client_link_template.txt`，提供 Shadowrocket / 通用 VLESS 导入链接模板。
3. 新增 `docs/12_client_config_explained.md`，说明字段含义、占位符替换、导入方式和初次连接检查。
4. 更新 `.env.example`，加入客户端配置所需占位符。
5. 更新 `README.md`，加入客户端导入方法和初次连接检查。

## Round 3 当前状态
1. 客户端模板和文档生成完成。
2. sing-box 模板在替换示例占位符后可通过 JSON 校验。
3. 真实客户端连接需要用户填入服务端 UUID、REALITY 公钥、shortId、serverName、端口和节点地址后验收。
4. 不建议把真实客户端链接提交到 Git 或公开分享。
5. 已修正占位符检查命令为 `grep -nF '${'`，避免旧版正则写法误判。
6. 已补充 `${SINGBOX_MIXED_PORT}`、`${NODE_PORT}` 等数字占位符的详细填写说明。
7. 已补充 Shadowrocket 主流程：App 辨别、参数说明、链接生成、导入步骤、初次连接检查。
8. 已新增 `scripts/generate_shadowrocket_link.sh`，用于从已校验的服务端配置生成 Shadowrocket 导入链接。
9. 已补充 Mac 端使用说明：Mac 可使用本项目，客户端优先 sing-box，也可尝试 Shadowrocket Mac 版本。
10. 已新增 `scripts/validate_shadowrocket_link.sh`，用于检查 Shadowrocket 链接字段是否与服务端配置一致。
11. 已新增 `scripts/check_xray_health.sh`，用于检查本地配置、Shadowrocket 链接、本机到 VPS 端口、远程 Xray 状态和近期日志。
12. 已补充 Shadowrocket 节点详情逐项核对说明，重点说明 REALITY 字段位于 `TLS` 页面，以及“使用中的配置无法删除”的处理方式。
13. 已新增 `scripts/generate_singbox_config.sh`，用于从已校验的服务端配置生成 sing-box 客户端配置。
14. 已补充 sing-box VT App 辨别和 Mac/iPhone 导入流程。
15. 已升级 sing-box 客户端生成逻辑：默认生成 `tun` 模式，移除旧 `block` 特殊出站，并使用 `action: "sniff"` / `action: "hijack-dns"` 避免 sing-box 1.11+ 弃用警告。
16. 已补充 sing-box `dial tcp <VPS_IP>:443: i/o timeout` 日志解释和 VPS `tcpdump` 抓包判断流程。
17. 已补充 tcpdump 只看到 `In Flags [S]`、没有 `Out Flags [S.]` 时的含义：TCP 握手未完成，优先检查 Xray 监听和 VPS/云厂商防火墙。
18. 已根据实际排障结果确认：Xray 正在监听 443，但 UFW 只放行 22，导致 443 入站被本机防火墙丢弃。
19. 已更新部署脚本：当 VPS 启用 UFW 时，自动放行 Xray 配置中的 TCP 监听端口。
20. 已更新健康检查脚本：远程检查会显示 UFW 状态，并提示当前端口是否已放行。
21. 已完成 iPhone sing-box VT 实机验收：Wi-Fi 和蜂窝网络均可连接，出口 IP 已显示为当前 VPS，客户端有入站/出站连接与流量统计。

## Round 3 验收标准
1. 复制 `templates/singbox_client_template.json` 到 `configs/client/singbox.json`。
2. 替换所有 `${...}` 占位符。
3. 执行 `jq empty configs/client/singbox.json` 不报错。
4. Shadowrocket 导入链接后能看到节点。
5. 客户端连接后可以完成基础网络访问测试。当前 iPhone sing-box VT 已通过该验收。

## 下一轮 Round 4 计划
1. 增加服务端健康检查脚本。
2. 增加客户端连接故障排查文档。
3. 增加节点变更日志模板。
4. 增加备份当前 VPS 配置的脚本。

## Round 4 目标
1. 让已经跑通的节点具备稳定运维能力。
2. 在修改配置前可以一键备份。
3. 在配置损坏时可以从备份恢复。
4. 在连接异常时可以采集诊断信息，便于快速定位问题。

## Round 4 完成内容
1. 新增 `scripts/backup_remote_xray.sh`，用于备份 VPS 上的 Xray 配置、systemd 服务文件、防火墙状态和近期脱敏日志。
2. 新增 `scripts/restore_remote_xray_config.sh`，用于从本地备份包恢复远程 Xray 配置，并自动备份当前配置。
3. 新增 `scripts/collect_remote_diagnostics.sh`，用于采集远程非敏感诊断信息到本地 `logs/`。
4. 新增 `docs/20_operations_runbook.md`，说明健康检查、备份、恢复、诊断采集和故障处理顺序。
5. 更新 `README.md`，加入 Round 4 常用命令入口。
6. 更新 `.env.example`，加入备份与恢复相关占位符。

## Round 4 当前状态
1. iPhone sing-box VT 已完成实机连接验收，节点进入稳定维护阶段。
2. 本轮脚本只保存备份或诊断文件到 `.gitignore` 已忽略的目录。
3. 备份包包含真实服务端配置，应只在本机或可信存储中保存。
4. 恢复脚本需要用户明确输入 `RESTORE`，避免误覆盖远程配置。
5. 用户已完成远程备份实机验收，备份流程可用。

## Round 4 验收标准
1. `bash -n scripts/*.sh` 不报错。
2. `bash scripts/snapshot_tree.sh` 能生成快照。
3. `scripts/check_xray_health.sh` 能检查当前节点状态。
4. `scripts/backup_remote_xray.sh` 能生成远程和本地备份。
5. `scripts/collect_remote_diagnostics.sh` 能生成本地诊断日志。

## 下一轮 Round 5 计划
1. 整理 Mac 端 sing-box VT 导入配置流程。
2. 说明 Mac 上 TUN/VPN Profile 权限授权方式。
3. 增加 Mac 端连接验收步骤。
4. 说明 iPhone 与 Mac 共用同一节点配置时的注意事项。

## Round 5 目标
1. 让 Mac 电脑复用当前已跑通的 sing-box 节点配置。
2. 说明 Mac sing-box VT 的导入、启用和系统授权流程。
3. 提供本地检查脚本，确认配置格式、端口连通和出口 IP。
4. 给出 Mac 端常见故障的排查顺序。

## Round 5 完成内容
1. 新增 `scripts/check_macos_singbox.sh`，用于检查 Mac 本地 sing-box 配置、节点端口和当前公网出口 IP。
2. 新增 `docs/21_macos_client_setup.md`，说明 Mac sing-box VT 导入、VPN Profile 授权、启用验收和 mixed 备用方案。
3. 更新 `README.md`，加入 Mac 电脑端接入入口和 Round 5 验收命令。
4. 更新 `.env.example`，加入 Mac 端检查脚本所需占位符。
5. 新增 `scripts/copy_shadowrocket_link_macos.sh`，用于把已校验的 Shadowrocket 链接复制到 macOS 剪贴板且不打印敏感链接。
6. 已补充 Shadowrocket Mac 备用方案：当 App Store 暂时无法下载 sing-box VT 时，可直接重新导入 Shadowrocket 链接。

## Round 5 当前状态
1. iPhone 端已验证节点可用，Mac 端使用同一服务端配置即可。
2. 默认推荐 `SINGBOX_MODE=tun`，适合 sing-box VT 作为 macOS VPN Profile 使用。
3. 若 Mac 上 TUN/VPN 授权失败，可临时使用 `SINGBOX_MODE=mixed` 作为备用方案。
4. 若 Mac App Store 的 sing-box VT 下载入口卡住，可先使用已安装的 Shadowrocket。

## Round 5 验收标准
1. `bash -n scripts/*.sh` 不报错。
2. `jq empty configs/client/singbox.json` 不报错。
3. Mac 未启用 sing-box 时，`scripts/check_macos_singbox.sh` 至少应通过配置和端口检查。
4. Mac 启用 sing-box 后，`EXPECTED_EXIT_IP="<你的_VPS_IP>" bash scripts/check_macos_singbox.sh` 应显示出口 IP 与 VPS IP 一致。
5. 如果使用 Shadowrocket，`scripts/copy_shadowrocket_link_macos.sh` 应能把已校验链接复制到剪贴板。

## 下一轮 Round 6 计划
1. 建立节点资产档案模板。
2. 记录 VPS 供应商、地区、IP、端口、创建时间、续费日期和费用。
3. 记录客户端设备清单，但不记录真实密钥。
4. 增加节点变更日志模板。

## 待确认问题
1. 节点命名规则是否采用“地区-城市-序号”固定格式？
2. 后续 CLI 倾向 Bash 还是 Python 实现？
3. 客户端主力是否固定为 sing-box，是否保留多客户端兼容？
4. 配置模板优先支持哪些协议组合（VLESS+REALITY 是否第一优先）？
