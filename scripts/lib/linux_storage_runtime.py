#!/usr/bin/env python3
"""Read-only identity guard; never selects a fallback or creates runtime data."""
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys
from uuid import UUID

PROJECT = Path('/home/alalapi/Projects/resilient-personal-network')
RUNTIME = Path('/home/alalapi/Runtimes/resilient-personal-network')
TEMP = Path('/home/alalapi/Temp/resilient-personal-network')
CACHE = Path('/home/alalapi/Caches/resilient-personal-network')
BINARY = RUNTIME / 'sing-box'
EXPECTED_UUID = str(UUID(hex='9d258b70f3134a5d9cf6c715c5edca3d'))
EXPECTED_SHA = '0c3a9990ba286e72afcdbec3b87c178ae421a42bfa4c6df228f9e64fc78bc00a'


def canonical(path, *, executable=False, private=False):
    if path.resolve(strict=True) != path or path.is_symlink():
        raise ValueError('redirected path')
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise ValueError('redirected ancestor')
    info = path.stat()
    if info.st_uid != 1000 or info.st_mode & 0o022:
        raise ValueError('ownership or permissions')
    if private and stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('private root permissions')
    if executable:
        if not stat.S_ISREG(info.st_mode) or not os.access(path, os.X_OK):
            raise ValueError('binary type or execution permission')
    elif not stat.S_ISDIR(info.st_mode):
        raise ValueError('root type')
    result = subprocess.run(['/usr/bin/findmnt', '-T', str(path), '-n', '-o', 'UUID,FSTYPE'],
                            check=True, capture_output=True, text=True, timeout=5)
    if result.stdout.strip().split() != [EXPECTED_UUID, 'ext4']:
        raise ValueError('filesystem identity')


def verify(script_root, requested):
    if os.getuid() != 1000 or sys.platform != 'linux':
        raise ValueError('platform or caller identity')
    if script_root != str(PROJECT / 'scripts'):
        raise ValueError('project route')
    allowed = ('', str(BINARY), str(PROJECT / 'scripts/external-sing-box'))
    if requested not in allowed:
        raise ValueError('unregistered binary override')
    for root in (PROJECT, PROJECT / 'scripts', RUNTIME):
        canonical(root)
    for root in (TEMP, CACHE):
        canonical(root, private=True)
    canonical(BINARY, executable=True)
    with BINARY.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != EXPECTED_SHA:
            raise ValueError('runtime fingerprint')


def main():
    try:
        if len(sys.argv) != 3:
            raise ValueError('arguments')
        verify(sys.argv[1], sys.argv[2])
    except (OSError, ValueError, subprocess.SubprocessError):
        print('[error] Linux runtime identity check failed', file=sys.stderr)
        return 78
    return 0


if __name__ == '__main__':
    sys.exit(main())
