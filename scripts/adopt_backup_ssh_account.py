#!/usr/bin/python3
"""Run by Root via a dedicated SSH session; stdin carries only public material."""
import base64
import grp
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import select
import signal
import stat
import subprocess
import sys
import tempfile

def adoption_spec(payload):
    required = {'schema', 'sshd_config', 'account_home', 'username', 'service',
                'listen_port', 'expected_sha256', 'verification_timeout', 'public_key'}
    if set(payload) != required or type(payload['schema']) is not int or payload['schema'] != 1:
        raise ValueError('unsupported adoption specification')
    for name in ('sshd_config', 'account_home'):
        value = payload[name]
        if not isinstance(value, str) or not Path(value).is_absolute() or str(Path(value).resolve()) != value or any(c in value for c in '\r\n%'):
            raise ValueError('invalid path field')
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', payload['username']):
        raise ValueError('invalid account field')
    if not re.fullmatch(r'[a-zA-Z0-9_.@-]+\.service', payload['service']):
        raise ValueError('invalid service field')
    for field, limit in (('listen_port', 65535), ('verification_timeout', 600)):
        if type(payload[field]) is not int or not 1 <= payload[field] <= limit:
            raise ValueError('invalid bounded numeric field')
    if not re.fullmatch(r'[0-9a-f]{64}', payload['expected_sha256']):
        raise ValueError('invalid preimage')
    user, port = payload['username'], payload['listen_port']
    suffix = ('\n# BEGIN lab-ssh-backup adopted v2\n'
              f'Match User {user}\n'
              '    AuthenticationMethods publickey\n'
              '    PubkeyAuthentication yes\n'
              '    PasswordAuthentication no\n'
              '    KbdInteractiveAuthentication no\n'
              '    AllowTcpForwarding remote\n'
              '    AllowStreamLocalForwarding no\n'
              '    AllowAgentForwarding no\n'
              '    X11Forwarding no\n'
              '    PermitTTY no\n'
              '    PermitTunnel no\n'
              f'    PermitListen 127.0.0.1:{port}\n'
              '    PermitOpen none\n'
              '    GatewayPorts no\n'
              '    MaxSessions 0\n'
              'Match all\n# END lab-ssh-backup adopted v2\n')
    return suffix.encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(argv, data=None):
    result = subprocess.run(argv, input=data, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError('operation failed: ' + argv[0])
    return result.stdout


def event(name, **fields):
    print(json.dumps(dict(event=name, **fields)), flush=True)


def absent_account():
    for getter in (pwd.getpwnam, grp.getgrnam):
        try:
            getter(USER)
        except KeyError:
            continue
        raise RuntimeError('account/group exists')
    if os.path.lexists(HOME):
        raise RuntimeError('home exists')


def replace_config(data, expected, metadata, attributes):
    if CONFIG.is_symlink() or digest(CONFIG.read_bytes()) != expected:
        raise RuntimeError('shared config changed; preserving current bytes')
    fd, temporary = tempfile.mkstemp(prefix='.lab-ssh-backup-', dir=CONFIG.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(data)
            out.flush()
            os.fchmod(out.fileno(), stat.S_IMODE(metadata.st_mode))
            os.fchown(out.fileno(), metadata.st_uid, metadata.st_gid)
            os.fsync(out.fileno())
        for name, value in attributes.items():
            os.setxattr(temporary, name, value)
        if CONFIG.is_symlink() or digest(CONFIG.read_bytes()) != expected:
            raise RuntimeError('shared config changed before replacement')
        os.replace(temporary, CONFIG)
        directory = os.open(CONFIG.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    if os.geteuid() != 0 or sys.argv[1:] != ['--approved-adoption']:
        raise RuntimeError('requires approved root adoption')
    def interrupted(_number, _frame):
        raise RuntimeError('deployment session interrupted')
    signal.signal(signal.SIGHUP, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    payload = json.loads(sys.stdin.buffer.readline(32768))
    global CONFIG, HOME, USER, BASELINE
    suffix = adoption_spec(payload)
    CONFIG = Path(payload['sshd_config'])
    HOME = Path(payload['account_home'])
    USER = payload['username']
    BASELINE = payload['expected_sha256']
    public = payload['public_key']
    if not re.fullmatch(r'ecdsa-sha2-nistp256 [A-Za-z0-9+/]+={0,2} lab-ssh-backup\n?', public):
        raise RuntimeError('unexpected public key')
    base64.b64decode(public.split()[1], validate=True)
    original = CONFIG.read_bytes()
    metadata = CONFIG.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or digest(original) != BASELINE:
        raise RuntimeError('config preimage mismatch')
    attributes = {name: os.getxattr(CONFIG, name) for name in os.listxattr(CONFIG)}
    backup = Path(tempfile.mkdtemp(prefix='lab-ssh-backup-preimage-', dir=Path.home()))
    os.chmod(backup, 0o700)
    (backup / 'sshd_config').write_bytes(original)
    os.chmod(backup / 'sshd_config', 0o600)
    if digest((backup / 'sshd_config').read_bytes()) != BASELINE:
        raise RuntimeError('backup verification failed')
    event('backup-verified', path=str(backup))
    absent_account()
    if run(['/usr/bin/ss', '-H', '-ltn', '( sport = :' + str(payload['listen_port']) + ' )']).strip():
        raise RuntimeError('forwarding port already occupied')
    candidate = original + b'\n' + suffix
    parts = os.environ['SSH_CONNECTION'].split()
    context = 'user=root,host=' + parts[0] + ',addr=' + parts[0] + ',laddr=' + parts[2] + ',lport=' + parts[3]
    run(['/usr/sbin/sshd', '-t', '-f', '/dev/stdin'], candidate)
    before = run(['/usr/sbin/sshd', '-T', '-f', '/dev/stdin', '-C', context], original)
    after = run(['/usr/sbin/sshd', '-T', '-f', '/dev/stdin', '-C', context], candidate)
    if before != after:
        raise RuntimeError('existing root policy would change')
    policy = run(['/usr/sbin/sshd', '-T', '-f', '/dev/stdin', '-C', context.replace('user=root,', 'user=' + USER + ',')], candidate)
    values = dict(line.split(' ', 1) for line in policy.decode().splitlines())
    expected = {'allowtcpforwarding': 'remote', 'allowstreamlocalforwarding': 'no',
                'allowagentforwarding': 'no', 'x11forwarding': 'no', 'permittty': 'no',
                'permittunnel': 'no', 'permitlisten': '127.0.0.1:' + str(payload['listen_port']), 'permitopen': 'none',
                'gatewayports': 'no', 'maxsessions': '0', 'authenticationmethods': 'publickey'}
    if any(values.get(key) != value for key, value in expected.items()):
        raise RuntimeError('new account policy mismatch')
    auth = ('restrict,port-forwarding,permitlisten="127.0.0.1:' + str(payload['listen_port']) + '" ' + public.strip() + '\n').encode()
    created = None
    committed = False
    try:
        run(['/usr/sbin/useradd', '--system', '--user-group', '--no-create-home',
             '--home-dir', str(HOME), '--shell', '/usr/sbin/nologin', USER])
        created = pwd.getpwnam(USER)
        HOME.mkdir(mode=0o755)
        (HOME / '.ssh').mkdir(mode=0o755)
        path = HOME / '.ssh/authorized_keys'
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, 'wb') as out:
            out.write(auth)
            out.flush()
            os.fchmod(out.fileno(), 0o644)
            os.fsync(out.fileno())
        os.chmod(HOME, 0o755)
        os.chmod(HOME / '.ssh', 0o755)
        replace_config(candidate, BASELINE, metadata, attributes)
        run(['/usr/sbin/sshd', '-t', '-f', str(CONFIG)])
        run(['/usr/bin/systemctl', 'reload', payload['service']])
        event('awaiting-new-tunnel-login', candidate_sha256=digest(candidate),
              original_sha256=BASELINE, original_length=len(original), suffix_sha256=digest(b'\n' + suffix),
              public_authorization_sha256=digest(auth), uid=created.pw_uid, gid=created.pw_gid)
        # Caller verifies a NEW restricted tunnel login before committing.
        # This bounds verification, not the owner authorization or account lifetime.
        if select.select([sys.stdin.buffer], [], [], payload['verification_timeout'])[0]:
            committed = sys.stdin.buffer.readline(256).strip() == ('commit ' + digest(candidate)).encode()
        if not committed:
            raise RuntimeError('independent verification not committed')
        event('committed', candidate_sha256=digest(candidate))
    finally:
        if not committed:
            if created is not None:
                current = pwd.getpwnam(USER)
                if (current.pw_uid, current.pw_gid, current.pw_dir) != (created.pw_uid, created.pw_gid, str(HOME)):
                    raise RuntimeError('new account identity changed; preserve recovery state')
                auth_path = HOME / '.ssh/authorized_keys'
                if auth_path.exists():
                    if auth_path.is_symlink() or auth_path.read_bytes() != auth:
                        raise RuntimeError('new authorization changed; preserve recovery state')
                    auth_path.unlink()
                # Reload never retracts established sessions. Do not remove their
                # restricting Match policy or delete an account still in use.
                listening = run(['/usr/bin/ss', '-H', '-ltn',
                                 '( sport = :' + str(payload['listen_port']) + ' )']).strip()
                active = any(p.is_dir() and p.name.isdigit() and p.stat().st_uid == created.pw_uid
                             for p in Path('/proc').iterdir())
                if listening or active:
                    raise RuntimeError('validation session still present; authorization removed; preserve restricted policy for exact recovery')
            current_hash = digest(CONFIG.read_bytes())
            if current_hash == digest(candidate):
                replace_config(original, digest(candidate), metadata, attributes)
                run(['/usr/sbin/sshd', '-t', '-f', str(CONFIG)])
                run(['/usr/bin/systemctl', 'reload', payload['service']])
                event('config-rolled-back', sha256=BASELINE)
            elif current_hash != BASELINE:
                raise RuntimeError('shared config changed; preserving for inspection')
            if created is not None:
                current = pwd.getpwnam(USER)
                if (current.pw_uid, current.pw_gid, current.pw_dir) != (created.pw_uid, created.pw_gid, str(HOME)):
                    raise RuntimeError('new account identity changed; preserving')
                path = HOME / '.ssh/authorized_keys'
                if path.exists():
                    if path.is_symlink() or path.read_bytes() != auth:
                        raise RuntimeError('new authorization file changed; preserving')
                    path.unlink()
                if (HOME / '.ssh').exists():
                    (HOME / '.ssh').rmdir()
                if HOME.exists():
                    HOME.rmdir()
                run(['/usr/sbin/userdel', USER])
                try:
                    group = grp.getgrnam(USER)
                except KeyError:
                    group = None
                if group is not None:
                    if group.gr_gid != created.pw_gid or group.gr_mem:
                        raise RuntimeError('group changed; preserving')
                    run(['/usr/sbin/groupdel', USER])
                event('new-account-removed')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        event('stopped', error=str(error))
        sys.exit(1)
