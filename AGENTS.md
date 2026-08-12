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

Never automatically push, merge, deploy, publish, release, force-push, run migrations, or delete user data. A local commit does not authorize a push.

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

### Authority and role separation

- These repository instructions are subordinate to system, developer, current-user, global, and closer-scope instructions.
- Root owns orchestration, evidence registration, repository control-plane writes, Git finalization, external effects, and user reporting.
- Governor and Judge are read-only. A bounded Repair may edit only its assigned project-content scope; Root may also implement and verify project content when the controlling workflow allows it.

### Git metadata authority

- Root alone finalizes staging, commits, and pushes. A writer may use only ordinary task-local Git metadata needed for its assigned work when explicitly authorized.
- Governor and Judge remain strictly read-only.
- Root may stage and commit a Judge-PASS/Governor-APPROVE candidate when the user has authorized committing.
- Commit and push are distinct from deployment and remote infrastructure operations. Each requires the authority applicable to that exact effect; force-push, deployment, and release are never inferred.

### Immutable task contracts and evidence

- Governor creates one immutable `TASK_CONTRACT` for exactly one highest-impact issue per governance round.
- The contract freezes the objective, protected boundaries, authorized external effects, and acceptance criteria. Implementation paths and checks remain adaptive candidate details unless the contract expressly freezes them.
- After `CREATE_TASK`, no role may relax or expand the frozen terms. A material change requires a successor contract under the controlling authority.
- Root assigns immutable evidence identifiers.
- Baseline and candidate evidence remain separate and include worktree or revision identity, scope or diff record, required-check commands, exit status, and material output.
- Repair claims are not evidence unless independently captured and registered by Root.

### Mandatory workflow

For every governed project-changing task, use this sequence exactly:

`READ_PROJECT_CONTRACT` → `GOVERNANCE_PLAN` → `BASELINE` → `REPAIR` → `VERIFY` → `INDEPENDENT_JUDGE` → `DECIDE`

1. `READ_PROJECT_CONTRACT`
   - Read the applicable project `AGENTS.override.md` or `AGENTS.md` and all explicit constraints.
   - If no project-level AGENTS file exists, prepare a project-contract draft in the conversation first; do not write it unless the user requests it.
   - Do not make broad project changes before a safe contract draft exists.
2. `GOVERNANCE_PLAN`
   - Spawn Governor with the user request, project constraints, and verified facts.
   - Governor selects exactly one highest-impact issue and returns `CREATE_TASK`, `NEEDS_HUMAN`, or `STOP`.
   - Freeze the resulting `TASK_CONTRACT` before Repair begins.
3. `BASELINE`
   - Before candidate edits, independently capture baseline behavior and required deterministic checks.
   - Register the result as `baseline_evidence_id`.
4. `REPAIR`
   - Give any bounded writer only the immutable contract and relevant factual evidence.
   - After two consecutive no-progress attempts, diagnose and change the approach before continuing; elapsed attempts alone do not require human escalation.
5. `VERIFY`
   - Root independently inspects the diff and runs the required deterministic checks.
   - Register the verified candidate as `candidate_evidence_id`.
   - Repair self-report is not verification.
6. `INDEPENDENT_JUDGE`
   - Spawn a new Judge thread for each judgment so its context is fresh.
   - Give Judge only the immutable contract, baseline evidence, candidate evidence, and their identifiers.
   - Do not pass Repair's persuasive explanation, confidence, recommendation, or self-assessment.
   - Judge checks deterministic evidence before subjective criteria and returns only `PASS`, `FAIL`, or `INCONCLUSIVE`.
7. `DECIDE`
   - Give Governor the immutable contract, attempt count, evidence identifiers, and Judge result.
   - Accept only `APPROVE`, `REQUEST_REPAIR`, `ROLLBACK`, `NEEDS_HUMAN`, or `STOP`.
   - `APPROVE` requires a matching Judge `PASS` and approves only the candidate, not merge, push, deployment, or release.
   - `REQUEST_REPAIR` is allowed while the issue remains repairable inside the immutable contract.
   - `ROLLBACK` permits only a scoped inverse of changes created by the current task. Never discard pre-existing or user-owned work; if ownership is uncertain, return `NEEDS_HUMAN`.
   - A genuine permission, protected-boundary, or owner-decision blocker must lead to `NEEDS_HUMAN`, `ROLLBACK`, or `STOP`; difficulty or elapsed attempts alone are not blockers.
   - An `INCONCLUSIVE` judgment caused only by missing evidence may return to `VERIFY` without consuming another Repair attempt; it must never be converted into PASS.

### Concurrency and write ownership

- Before spawning Repair, reserve its normalized `allowed_paths` as its write scope.
- Never run more than one Repair whose write scope overlaps another active writer.
- Unknown, glob-based, symlink-based, or ambiguous overlap counts as overlap.
- Release the reservation only after the Repair thread has stopped and its changes have been independently inspected.
- Read-only Governor and Judge never receive write ownership.

### Prohibited automatic actions

- Never automatically merge, auto-merge, deploy, publish, release, run a database migration, or delete user data. Commit and normal push are allowed only under exact current authority and after the repository's required review.
- No role may weaken tests, alter acceptance criteria, or bypass a failure to obtain approval.

Only stage or commit when the user explicitly asks. Before committing, audit the exact staged path list, run the required checks, and repeat the sensitive-value scan. Use a focused commit message. Do not push unless separately authorized.
