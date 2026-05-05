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

## Round 2 验收结果
1. 已确认 Xray 服务端安装完成。
2. 已确认 `/usr/local/etc/xray/config.json` 权限修复为 `root:xray` + `640` 后可被 `xray` 用户读取。
3. 已确认 `systemctl status xray --no-pager -l` 显示 `active (running)`。
4. Round 2 服务端启动验收通过。

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

## Round 3 验收标准
1. 复制 `templates/singbox_client_template.json` 到 `configs/client/singbox.json`。
2. 替换所有 `${...}` 占位符。
3. 执行 `jq empty configs/client/singbox.json` 不报错。
4. Shadowrocket 导入链接后能看到节点。
5. 客户端连接后可以完成基础网络访问测试。

## 下一轮 Round 4 计划
1. 增加服务端健康检查脚本。
2. 增加客户端连接故障排查文档。
3. 增加节点变更日志模板。
4. 增加备份当前 VPS 配置的脚本。
