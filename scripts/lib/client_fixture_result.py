#!/usr/bin/env python3
"""Safe, optional result adapter for the existing placeholder fixture run."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path('/Volumes/AI_WORK_SSD/Runtimes/resilient-personal-network/sing-box')
SOURCES = (
    'scripts/test_client_generation.sh', 'scripts/lib/client_fixture_result.py',
    'scripts/lib/storage_runtime.sh', 'scripts/external-sing-box',
    'scripts/generate_singbox_config.sh', 'scripts/generate_shadowrocket_link.sh',
    'scripts/generate_shadowrocket_config.sh', 'scripts/generate_shadowrocket_macos_config.sh',
    'scripts/validate_client_artifacts.sh', 'scripts/validate_xray_config.sh',
    'scripts/validate_shadowrocket_link.sh', 'scripts/lib/check_ai_workflow_domains.sh',
    'templates/singbox_client_template.json',
    'templates/singbox_client_ios_legacy_1.11.4_template.json',
    'templates/shadowrocket_client.conf.template',
    'templates/shadowrocket_macos_ai_workflow.conf.template',
)
POSITIVE = ('modern_template', 'legacy_schema', 'artifact_validation', 'transaction_backup')
NEGATIVE = ('duplicate_manifest', 'invalid_dns_style', 'unauthorized_external_output',
            'legacy_mixed', 'symlink_output', 'symlink_ancestor', 'dangling_symlink',
            'misindexed_artifacts', 'unsafe_permissions', 'missing_artifact',
            'unexpected_artifact', 'unapproved_transaction_backup')
STAGES = ('prerequisites', 'storage', 'modern_version', 'fixture_setup', 'generation',
          'modern_template', 'legacy_schema', 'artifact_validation', 'transaction_backup',
          'complete') + NEGATIVE


def sha_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def code_snapshot(root):
    files = {name: sha_file(root / name) for name in SOURCES}
    digest = hashlib.sha256()
    for name in SOURCES:
        digest.update(name.encode() + b'\0' + files[name].encode() + b'\n')
    return files, digest.hexdigest()


def optional_hash(path):
    try:
        return sha_file(path)
    except OSError:
        return None


def parse_events(raw):
    result = dict(stage='adapter', manifest_count=None, artifact_count=0,
                  positive=[], negative=[], cleanup='not_created', version=None)
    valid = True
    for line in raw.splitlines():
        key, sep, value = line.partition(':')
        if key == 'stage' and value in STAGES:
            result['stage'] = value
        elif key == 'manifest_count' and value.isascii() and value.isdigit() and int(value) < 1000:
            result['manifest_count'] = int(value)
        elif line == 'artifact:complete':
            result['artifact_count'] += 1
        elif key in ('positive', 'negative') and value in (POSITIVE if key == 'positive' else NEGATIVE):
            if value in result[key]:
                valid = False
            else:
                result[key].append(value)
        elif key == 'cleanup' and value in ('not_created', 'pending', 'pass', 'fail'):
            result['cleanup'] = value
        elif key == 'version':
            match = re.fullmatch(r'sing-box version ([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)', value)
            if match:
                result['version'] = match[1]
            else:
                valid = False
        else:
            valid = False
    return result, valid


def build_result(events, valid, exit_code, before, after, binary_before, binary_after, run_id, started):
    unchanged = before is not None and before == after
    binary_unchanged = binary_before is not None and binary_before == binary_after
    complete = (events['stage'] == 'complete' and events['cleanup'] == 'pass'
                and events['manifest_count'] is not None and events['manifest_count'] > 0
                and events['artifact_count'] == events['manifest_count']
                and set(events['positive']) == set(POSITIVE)
                and set(events['negative']) == set(NEGATIVE) and events['version'] is not None)
    passed = exit_code == 0 and valid and unchanged and binary_unchanged and complete
    return {
        'schema_version': 'rpn.client-fixture-result.v1', 'test_id': 'client-generation-placeholder',
        'run_id': run_id, 'status': 'pass' if passed else 'fail', 'exit_code': exit_code,
        'started_at': started, 'finished_at': datetime.now(timezone.utc).isoformat(),
        'stage': events['stage'], 'environment': 'clean_PATH_only',
        'manifest_count': events['manifest_count'], 'artifact_count': events['artifact_count'],
        'count_basis': 'manifest entries; successfully generated existing files; completed named test cases (not validator assertions)',
        'positive': {'expected': len(POSITIVE), 'completed_count': len(events['positive']), 'completed': events['positive']},
        'negative': {'expected': len(NEGATIVE), 'completed_count': len(events['negative']), 'completed': events['negative']},
        'modern': {'binary_validation': 'pass' if {'modern_template', 'artifact_validation'}.issubset(events['positive']) else 'not_completed',
                   'version': events['version'], 'binary': str(BINARY),
                   'sha256_before': binary_before, 'sha256_after': binary_after,
                   'unchanged': binary_unchanged},
        'legacy': {'target': '1.11.4', 'schema': 'pass' if 'legacy_schema' in events['positive'] else 'not_completed',
                   'binary_validation': 'not_run'},
        'cleanup': events['cleanup'],
        'code': {'algorithm': 'sha256(path NUL file_sha256 LF, ordered)',
                         'sha256': before, 'sha256_after': after,
                         'stable': unchanged, 'scope': 'listed repository sources only; external guard and toolchain excluded'},
        'event_stream_valid': valid,
    }


def main():
    started = datetime.now(timezone.utc).isoformat()
    run_id = str(uuid4())
    before = after = binary_before = binary_after = None
    files = {}
    raw = ''
    exit_code = 1
    valid = False
    try:
        files, before = code_snapshot(ROOT)
        binary_before = optional_hash(BINARY)
        # Discard all human output; only bounded explicit fixture events are read.
        with tempfile.TemporaryFile() as events_file:
            env = {'PATH': os.environ.get('PATH', '/usr/bin:/bin'),
                   'RPN_RESULT_FD': str(events_file.fileno())}
            proc = subprocess.run(['bash', str(ROOT / SOURCES[0])], cwd=ROOT,
                                  env=env, pass_fds=(events_file.fileno(),),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            exit_code = proc.returncode if proc.returncode >= 0 else 128 - proc.returncode
            events_file.seek(0)
            data = events_file.read(8193)
            raw = data[:8192].decode('ascii', errors='replace')
            valid = len(data) <= 8192
    except (OSError, ValueError):
        exit_code = 1
    finally:
        try:
            _, after = code_snapshot(ROOT)
        except OSError:
            pass
        binary_after = optional_hash(BINARY)
    events, parsed = parse_events(raw)
    result = build_result(events, valid and parsed, exit_code, before, after,
                          binary_before, binary_after, run_id, started)
    result['code']['files'] = files
    # A successful fixture with incomplete/unbound evidence is still a failed result.
    if result['status'] != 'pass' and exit_code == 0:
        exit_code = result['exit_code'] = 1
    output = json.dumps(result, ensure_ascii=True, separators=(',', ':'))
    assert len(output.encode()) + 1 <= 8192
    print(output)
    return exit_code


if __name__ == '__main__':
    sys.exit(main())
