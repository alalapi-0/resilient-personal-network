#!/usr/bin/env bash
set -euo pipefail

# 扫描 Git 候选文件；受保护运行时凭据比对默认关闭。
# 命中时只报告类别和候选文件路径，不回显疑似敏感值或引用值。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SCOPE="tracked"
if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--scope" ]; then
    echo "[error] 用法：bash scripts/scan_tracked_secrets.sh [--scope tracked|worktree|staged]"
    exit 2
  fi
  SCOPE="$2"
fi

if [ "$SCOPE" != "tracked" ] && [ "$SCOPE" != "worktree" ] && [ "$SCOPE" != "staged" ]; then
  echo "[error] scope 只能是 tracked、worktree 或 staged"
  exit 2
fi

RUNTIME_REFERENCE_SCAN="${RUNTIME_REFERENCE_SCAN:-no}"
if [ "$RUNTIME_REFERENCE_SCAN" != "yes" ] && [ "$RUNTIME_REFERENCE_SCAN" != "no" ]; then
  echo "[error] RUNTIME_REFERENCE_SCAN 只能是 yes 或 no"
  exit 2
fi

python3 - "$REPO_ROOT" "$SCOPE" "$RUNTIME_REFERENCE_SCAN" <<'PY'
from pathlib import Path
import ipaddress
import json
import os
import re
import subprocess
import sys
from urllib.parse import parse_qs, urlsplit

root = Path(sys.argv[1]).resolve()
scope = sys.argv[2]
runtime_reference_scan = sys.argv[3] == "yes"


def git_output(*args):
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return result.stdout


def git_paths(*args):
    output = git_output(*args, "-z")
    return {
        item.decode("utf-8", errors="surrogateescape")
        for item in output.split(b"\0")
        if item
    }


paths = set()
staged_path_bytes = []
if scope == "staged":
    staged_path_bytes = [
        item
        for item in git_output(
            "diff",
            "--cached",
            "--no-ext-diff",
            "--no-textconv",
            "--name-only",
            "--diff-filter=ACMR",
            "--find-renames",
            "--find-copies",
            "-z",
            "--",
        ).split(b"\0")
        if item
    ]
else:
    paths = git_paths("ls-files")
    if scope == "worktree":
        paths.update(git_paths("ls-files", "--others", "--exclude-standard"))

full_link = re.compile(
    "vless:" + r"//[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}@"
)
uuid_value = re.compile(
    r"(?<![A-Za-z0-9])"
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    r"(?![A-Za-z0-9])"
)
sensitive_assignment = re.compile(
    r"""(?ix)
    ["']?
    (?:private[_-]?key|public[_-]?key|short[_-]?id|pbk|api[_-]?key|
       access[_-]?token|refresh[_-]?token|ssh[_-]?password)
    ["']?\s*[:=]\s*["']?
    ([A-Za-z0-9_+/=-]{16,})
    """
)
host_assignment = re.compile(
    r"""(?ix)
    \b(?:VPS_HOST|NODE_HOST|SERVER_HOST)\s*=\s*["']?
    ([A-Za-z0-9][A-Za-z0-9._:-]*)
    """
)
private_key_block = re.compile(r"-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----")
known_token = re.compile(
    r"(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,})"
)

allowed_hosts = {
    "example.com",
    "fixture.example",
    "localhost",
}
allowed_uuid = "00000000-0000-4000-8000-000000000001"
findings = []
candidate_text = {}


def scan_candidate_data(relative, data):
    if b"\0" in data:
        return
    text = data.decode("utf-8", errors="replace")
    candidate_text[relative] = text

    if full_link.search(text):
        findings.append((relative, "完整 VLESS 链接"))
    if private_key_block.search(text):
        findings.append((relative, "SSH 私钥"))
    if known_token.search(text):
        findings.append((relative, "访问令牌"))

    for match in uuid_value.finditer(text):
        if match.group(0) != allowed_uuid:
            findings.append((relative, "真实格式 UUID"))
            break

    if sensitive_assignment.search(text):
        findings.append((relative, "敏感字段字面值"))

    for match in host_assignment.finditer(text):
        host = match.group(1).rstrip(".")
        if host in allowed_hosts:
            continue
        try:
            address = ipaddress.ip_address(host.strip("[]"))
        except ValueError:
            findings.append((relative, "真实格式主机名"))
            break
        if not (address.is_loopback or address.is_unspecified or address.is_reserved):
            findings.append((relative, "真实格式主机地址"))
            break


if scope == "staged":
    index_entries = {}
    for record in git_output("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        try:
            metadata, indexed_path = record.split(b"\t", 1)
            mode, object_id, stage = metadata.split()
        except ValueError:
            continue
        index_entries.setdefault(indexed_path, []).append((mode, object_id, stage))

    for path_bytes in sorted(staged_path_bytes):
        relative = path_bytes.decode("utf-8", errors="surrogateescape")
        entries = index_entries.get(path_bytes, [])
        if len(entries) != 1 or entries[0][2] != b"0":
            findings.append((relative, "暂存索引条目异常"))
            continue

        mode, object_id, _ = entries[0]
        if mode == b"120000":
            findings.append((relative, "候选符号链接"))
            continue
        if mode not in {b"100644", b"100755"}:
            findings.append((relative, "暂存索引文件模式不受支持"))
            continue

        try:
            data = git_output("cat-file", "blob", object_id.decode("ascii"))
        except (subprocess.CalledProcessError, UnicodeDecodeError):
            findings.append((relative, "暂存 blob 无法读取"))
            continue
        scan_candidate_data(relative, data)
else:
    for relative in sorted(paths):
        candidate_path = root / relative
        candidate = candidate_path.resolve()
        try:
            if os.path.commonpath([str(root), str(candidate)]) != str(root):
                findings.append((relative, "仓库外符号链接"))
                continue
        except ValueError:
            findings.append((relative, "仓库外路径"))
            continue

        if candidate_path.is_symlink():
            findings.append((relative, "候选符号链接"))
            continue
        if not candidate.is_file():
            continue
        scan_candidate_data(relative, candidate.read_bytes())


def usable_reference(value, minimum_length=8):
    if not isinstance(value, str):
        return False
    value = value.strip()
    if len(value) < minimum_length:
        return False
    lowered = value.lower()
    if any(marker in lowered for marker in ("example", "<your", "${", "xxxx")):
        return False
    if len(set(value)) <= 2:
        return False
    return True


runtime_references = set()
if runtime_reference_scan:
    runtime_paths = [
        root / ".env",
        root / "configs/server/config.json",
        root / "configs/client/singbox.json",
        root / "configs/client/macos_singbox.json",
        root / "configs/client/macos_singbox_mixed.json",
        root / "configs/client/singbox-ios-legacy-1.11.4.json",
        root / "configs/client/shadowrocket_link.txt",
        root / "configs/client/ios_shadowrocket_vless_link.txt",
        root / "configs/client/android_v2rayng_vless_link.txt",
        root / "configs/client/shadowrocket.conf",
        root / "configs/client/shadowrocket-macos.conf",
    ]

    for runtime_path in runtime_paths:
        if not runtime_path.is_file() or runtime_path.is_symlink():
            continue
        try:
            runtime_text = runtime_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue

        if runtime_path.name == ".env":
            for line in runtime_text.splitlines():
                if line.startswith(("VPS_HOST=", "NODE_HOST=", "SERVER_HOST=")):
                    _, value = line.split("=", 1)
                    value = value.strip().strip("\"'")
                    if usable_reference(value):
                        runtime_references.add(value)
            continue

        if runtime_path.suffix == ".json":
            try:
                data = json.loads(runtime_text)
            except json.JSONDecodeError:
                continue

            def collect_json(item):
                if isinstance(item, dict):
                    item_type = item.get("type")
                    for key, value in item.items():
                        normalized = key.lower().replace("-", "").replace("_", "")
                        if normalized in {"id", "uuid", "privatekey", "publickey", "shortid"}:
                            values = value if isinstance(value, list) else [value]
                            for candidate in values:
                                if usable_reference(candidate):
                                    runtime_references.add(candidate)
                        if key == "server" and item_type == "vless" and usable_reference(value, 4):
                            runtime_references.add(value)
                        collect_json(value)
                elif isinstance(item, list):
                    for child in item:
                        collect_json(child)

            collect_json(data)
            continue

        for line in runtime_text.splitlines():
            stripped = line.strip()
            if stripped.startswith("vless://"):
                try:
                    parsed = urlsplit(stripped)
                    query = parse_qs(parsed.query)
                except ValueError:
                    continue
                if usable_reference(parsed.hostname, 4):
                    runtime_references.add(parsed.hostname)
                for value in (
                    parsed.username,
                    query.get("pbk", [""])[0],
                    query.get("sid", [""])[0],
                ):
                    if usable_reference(value):
                        runtime_references.add(value)
            elif " = vless, " in stripped and not stripped.startswith(("#", ";")):
                _, fields = stripped.split(" = ", 1)
                parts = [part.strip() for part in fields.split(",")]
                if len(parts) >= 3 and usable_reference(parts[1], 4):
                    runtime_references.add(parts[1])
                for option in parts[3:]:
                    if "=" not in option:
                        continue
                    key, value = option.split("=", 1)
                    if key.strip() in {"username", "public-key", "short-id"} and usable_reference(value.strip()):
                        runtime_references.add(value.strip())

    for relative, text in candidate_text.items():
        if any(reference in text for reference in runtime_references):
            findings.append((relative, "与本地运行时凭据相同的字面值"))

if findings:
    seen = set()
    for path, category in findings:
        item = (path, category)
        if item in seen:
            continue
        seen.add(item)
        print(f"[error] {category}：{path}")
    print("[failed] candidate secret scan failed")
    raise SystemExit(1)

print("[ok] 候选文件未发现连接凭据或完整导入链接")
print("[done] candidate secret scan passed")
PY
