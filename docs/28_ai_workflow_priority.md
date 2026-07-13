# 28 AI 工作流优先级策略（AI Workflow Priority）

本文件记录「resilient-personal-network」项目的 AI 工作流优先级分流策略。
目标不是维护一次性的真实配置，而是把可复用策略固化到模板、脚本和文档中。

## 1. 策略背景

用户的主要使用场景是 **AI 工作流**，包括：
- ChatGPT / OpenAI API
- OpenRouter
- Cursor
- Claude / Anthropic / Codex
- Google 搜索
- GitHub / GitHub Copilot

娱乐类服务（YouTube、TikTok 等）可以接受默认走代理，不需要特殊保护。
腾讯游戏、微信、公众平台等大陆生态必须直连，避免中国流量走 VPS 后再回中国大陆。

## 2. 优先级定义

| 优先级 | 服务类型 | 示例 | 处理方式 |
|--------|----------|------|----------|
| ★★★★★ | AI 工作流 | ChatGPT、OpenRouter、Cursor、Claude、Google 搜索、GitHub Copilot | 显式代理，放在大陆直连规则之前 |
| ★★★★☆ | 大陆生态 | 微信、公众平台、腾讯游戏、支付宝、抖音 | 直连，优先依赖 `geosite-cn` / `geoip-cn` |
| ★★★☆☆ | 日常国外网站 | GitHub、Twitter、Reddit 等 | 默认走代理；GitHub 可显式代理以保护开发工作流 |
| ★★☆☆☆ | 娱乐类 | YouTube、TikTok | 不单独维护，跟随 final proxy |

## 3. 配置原则

1. AI 工作流域名显式走代理，并放在大陆直连规则之前。
2. 大陆域名/IP 直连，避免中国 -> VPS -> 中国的回环路径。
3. 大陆生态优先依赖 `geosite-cn` / `geoip-cn`，不要维护过长且容易过期的硬编码域名清单。
4. 微信、公众平台、腾讯游戏这类高频大陆生态可以保留少量补充域名。
5. 娱乐类服务默认跟随 `final proxy`，不单独维护高优先级规则。

## 4. 已固化到仓库的位置

### sing-box

生成脚本：

```text
scripts/generate_singbox_config.sh
```

模板：

```text
templates/singbox_client_template.json
```

生成后的真实文件：

```text
configs/client/singbox.json
configs/client/macos_singbox.json
configs/client/macos_singbox_mixed.json
```

三个文件由统一刷新入口从同一来源生成，包含真实节点信息，已被 `.gitignore` 忽略，不应提交。

### Shadowrocket

通用模板与生成器：

```text
templates/shadowrocket_client.conf.template
scripts/generate_shadowrocket_config.sh
configs/client/shadowrocket.conf
```

`shadowrocket.conf` 是不含 macOS 本地监听器的通用完整配置。

### Shadowrocket macOS

模板：

```text
templates/shadowrocket_macos_ai_workflow.conf.template
```

生成脚本：

```text
scripts/generate_shadowrocket_macos_config.sh
```

生成后的真实文件：

```text
configs/client/shadowrocket-macos.conf
```

`configs/client/shadowrocket-macos.conf` 包含真实节点信息，已被 `.gitignore` 忽略，不应提交。

## 5. 显式代理域名原则

### OpenAI / ChatGPT
- `openai.com`
- `chatgpt.com`
- `oaistatic.com`
- `oaiusercontent.com`

### OpenRouter
- `openrouter.ai`

### Cursor
- `cursor.com`
- `cursor.sh`

### Anthropic / Claude / Codex
- `anthropic.com`
- `claude.ai`

### Google（搜索相关）
- `google.com`
- `googleapis.com`
- `gstatic.com`

### GitHub（开发工作流）
- `github.com`
- `githubusercontent.com`
- `githubassets.com`
- `githubcopilot.com`

## 6. 大陆直连规则原则

sing-box 使用远程 rule-set：

```text
geosite-cn
geoip-cn
```

Shadowrocket macOS 模板使用：

```text
GEOIP,CN,direct
```

并保留少量补充域名，覆盖微信、公众平台、腾讯游戏、腾讯云等常用大陆生态。

不要把大型大陆域名清单手工展开到仓库。规则集能覆盖的内容交给规则集维护。

## 7. 更新配置时的检查清单

- [ ] OpenAI 相关域名是否全部包含？
- [ ] OpenRouter 域名是否包含？
- [ ] Cursor 域名是否包含？
- [ ] Claude / Anthropic 域名是否包含？
- [ ] Google 搜索相关域名是否包含？
- [ ] GitHub / Copilot 是否按开发需要显式代理？
- [ ] 大陆域名/IP 是否直连？
- [ ] 腾讯游戏、微信、公众平台是否直连？
- [ ] 是否避免维护过长的大陆硬编码域名清单？

## 8. 维护建议

- 每月检查一次 AI 工作流域名是否有新增或变更。
- 如果发现新域名导致 AI 服务走直连或断线，立即加入显式代理规则。
- 娱乐类服务（YouTube、TikTok）不需要特殊维护。
- 如果大陆服务访问变慢或异常，优先检查 `geosite-cn` / `geoip-cn` 是否可下载、客户端是否支持对应规则。

## 9. 相关文档

- `docs/03_security_notes.md`：敏感信息管理规范
- `docs/12_client_config_explained.md`：客户端配置说明
- `docs/21_macos_client_setup.md`：Mac 端接入说明
- `docs/20_operations_runbook.md`：日常运维流程
