# Project Agent Instructions

## Scope and project model

These instructions apply to the whole repository.

This is an operations repository for a personal Xray/VLESS/REALITY network. It is not a Web application and has no local development server. The repository contains documentation, templates, and Bash/PowerShell automation; real runtime configuration is local or remote state and must not be committed.

Preserve all pre-existing working-tree changes. Treat modified and untracked files as user-owned unless the current task clearly created them. Never discard or rewrite unrelated work.

## Sensitive and protected material

The following paths contain or may contain real connection data and are protected:

- `.env`
- `configs/server/*.json`
- `configs/client/*.json`
- `configs/client/*.txt`
- `backups/`
- `logs/`
- `exports/`
- `nodes/`
- `tools/sing-box/sing-box`

Never stage or commit those files. Do not print, quote, summarize, or expose real VPS hosts, UUIDs, REALITY private/public keys, short IDs, complete `vless://` links, SSH credentials, tokens, or backup contents. Validation output must report field names and pass/fail state without values.

Keep generated sensitive files at mode `600` where supported. Temporary test directories must use mode `700` and be removed after validation.

## Configuration sources of truth

- The active server configuration is `/usr/local/etc/xray/config.json` on the VPS.
- The ignored local mirror is `configs/server/config.json`.
- Templates under `templates/` must contain placeholders only and must never become directly connectable.
- Client files are derived from the active server configuration. Do not manually invent a second UUID, REALITY key pair, short ID, SNI, flow, or port.
- Stable credentials are not rotated during routine monthly maintenance unless the user explicitly requests rotation or there is evidence of compromise.

Before changing remote state, create and verify a backup. Validate locally before upload, verify service state and listening port after a change, and retain a scoped rollback path.

## Remote and external operations

Remote reads and health checks are allowed only when they are part of the user's requested task. Remote writes, package upgrades, service restarts, firewall changes, deployment, restore, or credential rotation require explicit current-turn authorization.

Commit and normal push follow the current owner and task authorization. Review exact staged paths and verify the existing remote target. Never force-push. Deployment, release, migrations, credential changes and deletion require their own explicit authority.

Do not start a macOS TUN connection or change system proxy/VPN state merely to validate files. Prefer the mixed inbound for a low-risk connectivity test. Never run sing-box TUN and Shadowrocket network takeover at the same time.

## sing-box and Xray compatibility

Record the actual binary and version used for validation. For macOS CLI selection, use this order:

1. An explicit executable `SING_BOX_BIN`.
2. `sing-box` found in `PATH`.
3. The ignored project fallback `tools/sing-box/sing-box`.

Generated sing-box configurations must use the schema selected for their named target. Modern outputs must use the typed DNS schema accepted by the exact local binary reported at test time. A separately named `singbox-ios-legacy-1.11.4.json` output may use the official 1.11-era address/outbound schema, but it must be described as schema-targeted and not binary-validated unless an actual 1.11.4 binary check is recorded. Do not rely on deprecated compatibility environment variables.

Xray public-key parsing must tolerate current official `xray x25519` labels, including `Public key`, `PublicKey`, and `Password (PublicKey)`, without printing the key.

## Required validation

Run checks in proportion to the changed scope. For the complete maintenance/configuration workflow, the minimum deterministic checks are:

```bash
git diff --check
bash -n scripts/*.sh scripts/lib/*.sh
bash scripts/validate_xray_config.sh <server-config>
jq empty <generated-sing-box-config>
"$SING_BOX_BIN" check -c <generated-sing-box-config>
bash scripts/validate_shadowrocket_link.sh <link-file> <server-config>
```

Use placeholder-only fixtures in a protected temporary directory when testing generators. Never overwrite real files in `configs/` during a fixture test.

When applicable, also verify:

- the candidate contains no exact values extracted from ignored real configurations;
- sensitive/generated files remain ignored and untracked;
- generated Shadowrocket/VLESS links are a single line and contain the required REALITY parameters;
- server and client UUID, port, flow, SNI, short ID, and derived public key are consistent without displaying them;
- remote Xray is active, listens on the configured port, and passes the repository health check;
- `shellcheck` and PowerShell parsing are run when those tools are available, with unavailable tools reported rather than treated as passes.

Do not weaken validation, add compatibility bypasses, or edit acceptance criteria to turn a failure into a pass.

## Documentation requirements

`README.md` is the primary entry point. Keep it consistent with scripts and the detailed files under `docs/`.

Documentation must distinguish:

- macOS/Linux Bash commands from Windows PowerShell commands;
- sing-box graphical clients from the macOS CLI;
- mixed mode from TUN mode;
- preparing or checking configuration from actually connecting;
- local commit from Git push and remote deployment.

For macOS CLI instructions, document binary discovery, read-only `check`, mixed startup and test, TUN startup with `sudo`, `Control + C` shutdown, and the Shadowrocket mutual-exclusion warning.

When claiming current versions, installation methods, or removed/deprecated fields, verify against official sing-box or Xray documentation instead of relying on memory.

## Governance and Git

- One main agent owns the authorized task, source evidence, bounded changes and delivery. Use independent subtasks only when their scope is clear and parallel work helps; collect their results before closing.
- Do not restore a fixed Governor/Repair/Judge workflow, mandatory role handoffs or repeating audit loops. Necessary review follows the concrete risk and current owner instructions.
- Read the actual branch, pending files and original authority before writing. Reserve exact paths, retain unrelated work and private history, and stop overlapping edits when ownership conflicts.
- Keep implementation, isolated fixture checks, actual runtime adoption and owner acceptance separate. Preserve failed checks and recovery points; no test or acceptance weakening.
- Stage only reviewed non-sensitive paths. Apply the current owner/task Git authority to commits and normal main delivery; verify the remote afterward. A local commit or source delivery does not authorize deployment, account changes or service operations.
- Preserve the sensitive paths, source-of-truth rules and explicit remote-operation boundaries above. Use only scoped inverse changes for task-owned recovery.

## Agent 与 Hub 生命周期

创建、接手及收尾读取 `/home/alalapi/.agents/pch-project-contract.md`，契约 `1.0.1-20261114`，SHA256 `7c3a485fb71d1e555c5acb98c94b8b4858c038ba959f63e3b73c5a9cc976ec50`。

本项目稳定ID为 `resilient-personal-network`。工作前用 `pch-project begin --project-id resilient-personal-network` 读取Hub管理意图和原来源。`README.md` 继续保存原工作事实，由 `hub.connection.yaml` 映射；不新建业务State、数据库、Goal Hook或调度器。原写责者更新原来源后，按详细契约以新request ID、来源SHA与账本CAS执行finish，核对本ID的持久终态。

本次所有者PCH治理授权覆盖规则、声明、隐私保护和正常Git整合；真实VPS、账号、公钥、SSH配置、网络接管、服务及部署继续遵守原授权边界。文件写入、新会话加载和实际生命周期闭环分别验证；不声称其他活动会话热加载。
