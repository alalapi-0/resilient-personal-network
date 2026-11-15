#!/usr/bin/python3
"""Run by Root via a dedicated SSH session; stdin carries only public material."""
import base64
import ctypes
import errno
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
import uuid

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


class PublicationConflict(RuntimeError):
    """Both objects are retained after exchange; never exchange blindly back."""
    def __init__(self, message, locations=(), exchanged=False):
        self.locations = tuple(locations)
        super().__init__(message + ('; recovery objects: ' + json.dumps(self.locations) if self.locations else ''))
        self.exchanged = exchanged


def identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid,
            info.st_gid, info.st_nlink, info.st_size, info.st_mtime_ns)


class PinnedDirectory:
    def __init__(self, path):
        path = Path(path)
        if not path.is_absolute() or '..' in path.parts:
            raise ValueError('absolute directory required')
        self.fds, self.names = [], []
        try:
            self.fds.append(os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW))
            for name in path.parts[1:]:
                self.fds.append(os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                        dir_fd=self.fds[-1]))
                self.names.append(name)
            self.verify()
        except BaseException:
            self.close()
            raise

    @property
    def fd(self):
        return self.fds[-1]

    def verify(self):
        for fd in self.fds:
            info = os.fstat(fd)
            if (not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, os.geteuid())
                    or stat.S_IMODE(info.st_mode) & 0o022):
                raise RuntimeError('unsafe directory owner/permissions')
        for index, name in enumerate(self.names):
            actual = os.stat(name, dir_fd=self.fds[index], follow_symlinks=False)
            pinned = os.fstat(self.fds[index + 1])
            if (actual.st_dev, actual.st_ino, actual.st_mode) != (pinned.st_dev, pinned.st_ino, pinned.st_mode):
                raise RuntimeError('pinned directory changed')

    def close(self):
        for fd in reversed(self.fds):
            os.close(fd)
        self.fds = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def snapshot_at(directory, name, limit=8 * 1024 * 1024):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory.fd)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
            raise RuntimeError('unsafe file object')
        chunks, length = [], 0
        while True:
            chunk = os.read(fd, min(65536, limit + 1 - length))
            if not chunk:
                break
            chunks.append(chunk)
            length += len(chunk)
            if length > limit:
                raise RuntimeError('file exceeds bound')
        attributes = {key: os.getxattr(fd, key) for key in os.listxattr(fd)}
        after = os.fstat(fd)
        named = os.stat(name, dir_fd=directory.fd, follow_symlinks=False)
        directory.verify()
        if (identity(before) != identity(after) or identity(after) != identity(named)
                or before.st_ctime_ns != after.st_ctime_ns or after.st_ctime_ns != named.st_ctime_ns
                or length != after.st_size):
            raise RuntimeError('file changed during snapshot')
        return b''.join(chunks), after, attributes
    finally:
        os.close(fd)


def file_snapshot(path):
    path = Path(path)
    with PinnedDirectory(path.parent) as directory:
        return snapshot_at(directory, path.name)


def rename_at(directory_fd, source, target, flags):
    """Linux only. No fallback to an unconditional replacement."""
    libc = ctypes.CDLL(None, use_errno=True)
    method = getattr(libc, 'renameat2', None)
    if method is None:
        raise OSError(errno.ENOSYS, 'renameat2 unavailable')
    method.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    method.restype = ctypes.c_int
    if method(directory_fd, os.fsencode(source), directory_fd, os.fsencode(target), flags):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def attributes_digest(attributes):
    result = hashlib.sha256()
    for name, value in sorted(attributes.items()):
        key = os.fsencode(name)
        result.update(len(key).to_bytes(8, 'big') + key)
        result.update(len(value).to_bytes(8, 'big') + value)
    return result.hexdigest()


def replace_config(data, expected, metadata, attributes, expected_identity=None, journal=None):
    """Exchange, preserve, validate; never claim CAS against uncooperative writers.

    A conflicting displaced object remains at the unique retained path. No
    automatic exchange-back or reload is allowed after a preimage conflict.
    """
    temporary = '.lab-ssh-backup-retained-' + uuid.uuid4().hex
    exchanged, owned_inode = False, None
    with PinnedDirectory(CONFIG.parent) as directory:
        before, current, current_attributes = snapshot_at(directory, CONFIG.name)
        if (digest(before) != expected or current_attributes != attributes
                or (current.st_mode, current.st_uid, current.st_gid) !=
                   (metadata.st_mode, metadata.st_uid, metadata.st_gid)
                or (expected_identity is not None and identity(current) != expected_identity)):
            raise PublicationConflict('config preimage changed before exchange')
        if journal is not None:
            journal.record('config-exchange-intent', config=str(CONFIG), retained=str(CONFIG.parent / temporary),
                           candidate_sha256=digest(data), expected_sha256=expected,
                           directory_identity=identity(os.fstat(directory.fd))[:6],
                           before_identity=identity(current), attributes_sha256=attributes_digest(attributes))
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory.fd)
        try:
            # Track the exclusive object before any write, chmod or xattr can fail.
            info = os.fstat(fd)
            owned_inode = (info.st_dev, info.st_ino)
            with os.fdopen(fd, 'wb') as out:
                fd = None
                out.write(data)
                out.flush()
                os.fchmod(out.fileno(), stat.S_IMODE(metadata.st_mode))
                os.fchown(out.fileno(), metadata.st_uid, metadata.st_gid)
                for name, value in attributes.items():
                    os.setxattr(out.fileno(), name, value)
                os.fsync(out.fileno())
                candidate_identity = identity(os.fstat(out.fileno()))
            directory.verify()
            rename_at(directory.fd, temporary, CONFIG.name, 2)
            exchanged = True
            os.fsync(directory.fd)
            displaced, displaced_info, displaced_attributes = snapshot_at(directory, temporary)
            published, published_info, published_attributes = snapshot_at(directory, CONFIG.name)
            if (digest(displaced) != expected or identity(displaced_info) != identity(current)
                    or displaced_attributes != current_attributes or published_attributes != attributes
                    or published != data or identity(published_info) != candidate_identity):
                raise PublicationConflict('exchange preimage/current object conflict; both objects retained',
                                          (str(CONFIG), str(CONFIG.parent / temporary)), exchanged=True)
            receipt = {'identity': identity(published_info), 'ctime_ns': published_info.st_ctime_ns,
                       'attributes_sha256': attributes_digest(published_attributes),
                       'retained': str(CONFIG.parent / temporary)}
            if journal is not None:
                journal.record('config-exchange-verified', **receipt)
            return receipt
        except BaseException as primary:
            if exchanged:
                if journal is not None:
                    try:
                        journal.record('config-exchange-pending', config=str(CONFIG),
                                       retained=str(CONFIG.parent / temporary), error_type=type(primary).__name__)
                    except Exception:
                        pass  # The durable pre-exchange intent already names both objects.
                if isinstance(primary, PublicationConflict):
                    raise
                raise PublicationConflict('exchange outcome needs owner recovery; objects retained',
                                          (str(CONFIG), str(CONFIG.parent / temporary)), exchanged=True) from primary
            cleanup_error = None
            try:
                info = os.stat(temporary, dir_fd=directory.fd, follow_symlinks=False)
                if owned_inode is None or (info.st_dev, info.st_ino) != owned_inode or info.st_nlink != 1:
                    raise RuntimeError('unpublished candidate identity changed; preserve')
                os.unlink(temporary, dir_fd=directory.fd)
                os.fsync(directory.fd)
            except FileNotFoundError:
                pass
            except BaseException as error:
                cleanup_error = error
            if cleanup_error is not None:
                failure = PublicationConflict('candidate preparation failed (' + type(primary).__name__ +
                                              '); unpublished cleanup pending (' + type(cleanup_error).__name__ + ')',
                                              (str(CONFIG.parent / temporary),))
                failure.preparation_error = primary
                failure.cleanup_error = cleanup_error
                raise failure from primary
            raise
        finally:
            if fd is not None:
                os.close(fd)


class RecoveryJournal:
    """A private per-operation recovery record, not a project state store."""
    def __init__(self, directory):
        self.path = Path(directory) / 'account-recovery.jsonl'
        self.marker = 'lab-ssh-backup-txn-' + uuid.uuid4().hex
        with PinnedDirectory(self.path.parent) as parent:
            fd = os.open(self.path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=parent.fd)
            try:
                os.fchmod(fd, 0o600)
                self.inode = (os.fstat(fd).st_dev, os.fstat(fd).st_ino)
                os.fsync(fd)
            finally:
                os.close(fd)
            os.fsync(parent.fd)

    def record(self, step, **fields):
        raw = json.dumps({'step': step, **fields}, sort_keys=True).encode() + b'\n'
        with PinnedDirectory(self.path.parent) as parent:
            fd = os.open(self.path.name, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW, dir_fd=parent.fd)
            try:
                info = os.fstat(fd)
                if ((info.st_dev, info.st_ino) != self.inode or not stat.S_ISREG(info.st_mode)
                        or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.geteuid()
                        or info.st_nlink != 1):
                    raise RuntimeError('recovery journal identity changed')
                with os.fdopen(fd, 'ab', closefd=False) as stream:
                    stream.write(raw)
                    stream.flush()
                    os.fsync(fd)
                written = os.fstat(fd)
                named = os.stat(self.path.name, dir_fd=parent.fd, follow_symlinks=False)
                if identity(written) != identity(named) or written.st_ctime_ns != named.st_ctime_ns:
                    raise RuntimeError('recovery journal replaced while writing intent')
            finally:
                os.close(fd)
            parent.verify()
            os.fsync(parent.fd)


def account_signature(account):
    return (account.pw_uid, account.pw_gid, account.pw_dir, account.pw_gecos,
            account.pw_name, account.pw_shell)


def resolve_account(tx):
    try:
        account = pwd.getpwnam(USER)
    except KeyError:
        return 'absent'
    signature = account_signature(account)
    if (account.pw_gecos != tx['journal'].marker or account.pw_dir != str(HOME)
            or account.pw_name != USER or account.pw_shell != '/usr/sbin/nologin'
            or type(account.pw_uid) is not int or type(account.pw_gid) is not int
            or account.pw_uid <= 0 or account.pw_gid <= 0):
        raise RuntimeError('account identity unknown; preserve account and policy')
    if tx['created'] is not None and signature != tx['created']:
        raise RuntimeError('account identity changed; preserve account and policy')
    if tx['created'] is None:
        tx['created'] = signature
        tx['journal'].record('marked-account-recovered', uid=account.pw_uid, gid=account.pw_gid,
                             account_identity=list(signature))
    return 'owned'


def absent_account():
    for getter in (pwd.getpwnam, grp.getgrnam):
        try:
            getter(USER)
        except KeyError:
            continue
        raise RuntimeError('account/group exists')
    if os.path.lexists(HOME):
        raise RuntimeError('home exists')


def create_home(tx):
    for path in (HOME, HOME / '.ssh'):
        path.mkdir(mode=0o755)
        path.chmod(0o755)
        tx['directories'][str(path)] = identity(path.lstat())[:6]
    path = HOME / '.ssh/authorized_keys'
    with PinnedDirectory(path.parent) as directory:
        fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o644, dir_fd=directory.fd)
        with os.fdopen(fd, 'wb') as out:
            os.fchmod(out.fileno(), 0o644)
            tx['auth_identity'] = identity(os.fstat(out.fileno()))[:6]
            out.write(tx['auth'])
            out.flush()
            os.fsync(out.fileno())
        os.fsync(directory.fd)


def revoke_authorization(tx):
    path = HOME / '.ssh/authorized_keys'
    # Only the initial lookup can establish that no authorization is present.
    try:
        directory = PinnedDirectory(path.parent)
    except FileNotFoundError:
        return 'absent'
    with directory:
        try:
            raw, info, _ = snapshot_at(directory, path.name, 65536)
        except FileNotFoundError:
            return 'absent'
        if tx['auth_identity'] is None or identity(info)[:6] != tx['auth_identity'] or raw != tx['auth']:
            raise RuntimeError('authorization identity/content unknown; preserve')
        retained = '.lab-auth-revoked-' + uuid.uuid4().hex
        locations = (str(path), str(path.parent / retained))
        tx['journal'].record('authorization-revoke-intent', authorization=str(path),
                             retained=locations[1], before_identity=identity(info),
                             authorization_sha256=digest(raw))
        quarantined = False
        def require_absent_name():
            try:
                os.stat(path.name, dir_fd=directory.fd, follow_symlinks=False)
            except FileNotFoundError:
                return
            raise PublicationConflict('authorization recreated; preserve restrictions', locations)
        try:
            rename_at(directory.fd, path.name, retained, 1)
            quarantined = True
            os.fsync(directory.fd)
            displaced, moved, _ = snapshot_at(directory, retained, 65536)
            if identity(moved)[:6] != tx['auth_identity'] or displaced != tx['auth']:
                raise PublicationConflict('authorization conflict retained', locations)
            require_absent_name()
            os.unlink(retained, dir_fd=directory.fd)
            os.fsync(directory.fd)
            require_absent_name()
            tx['journal'].record('authorization-revoked', authorization=str(path), retained=locations[1])
            require_absent_name()
        except BaseException as primary:
            if quarantined:
                try:
                    tx['journal'].record('authorization-recovery-pending', authorization=str(path),
                                         retained=locations[1], error_type=type(primary).__name__)
                except Exception:
                    pass  # Durable pre-quarantine intent already names both objects.
                if isinstance(primary, PublicationConflict):
                    raise
                raise PublicationConflict('authorization quarantine outcome unknown; preserve restrictions',
                                          locations) from primary
            raise
    return 'removed'


def uid_process_present(uid):
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():
            continue
        try:
            if path.stat().st_uid == uid:
                return True
        except FileNotFoundError:
            continue
    return False


def no_sessions(tx):
    if tx['created'] is None:
        return True
    listening = run(['/usr/bin/ss', '-H', '-ltn',
                     '( sport = :' + str(tx['payload']['listen_port']) + ' )']).strip()
    return not listening and not uid_process_present(tx['created'][0])


def restore_config(tx):
    if tx['config_conflict']:
        raise RuntimeError('config exchange conflict; preserve both recovery objects')
    raw, info, _ = file_snapshot(CONFIG)
    if digest(raw) == BASELINE:
        if (info.st_mode, info.st_uid, info.st_gid) != (tx['metadata'].st_mode, tx['metadata'].st_uid, tx['metadata'].st_gid):
            raise RuntimeError('original config metadata changed; preserve')
        return 'already-original'
    if digest(raw) != digest(tx['candidate']) or tx['published'] is None:
        raise RuntimeError('shared config changed; preserve for owner recovery')
    receipt = replace_config(tx['original'], digest(tx['candidate']), tx['metadata'],
                             tx['attributes'], tx['published']['identity'], tx['journal'])
    tx['journal'].record('config-restored', retained=receipt['retained'])
    verify_publication(receipt, tx['original'])
    run(['/usr/sbin/sshd', '-t', '-f', str(CONFIG)])
    verify_publication(receipt, tx['original'])
    run(['/usr/bin/systemctl', 'reload', tx['payload']['service']])
    return 'restored'


def verify_publication(receipt, expected):
    raw, info, attributes = file_snapshot(CONFIG)
    if (raw != expected or identity(info) != tuple(receipt['identity'])
            or info.st_ctime_ns != receipt['ctime_ns']
            or attributes_digest(attributes) != receipt['attributes_sha256']):
        raise PublicationConflict('published config changed before reload; preserve current object',
                                  (str(CONFIG), receipt['retained']))


def remove_home(tx):
    for path in (HOME / '.ssh', HOME):
        try:
            actual = path.lstat()
        except FileNotFoundError:
            continue
        if tx['directories'].get(str(path)) != identity(actual)[:6] or not stat.S_ISDIR(actual.st_mode):
            raise RuntimeError('directory identity unknown; preserve')
        with PinnedDirectory(path.parent) as directory:
            quarantine = '.lab-empty-directory-' + uuid.uuid4().hex
            rename_at(directory.fd, path.name, quarantine, 1)
            os.fsync(directory.fd)
            moved = os.stat(quarantine, dir_fd=directory.fd, follow_symlinks=False)
            if identity(moved)[:6] != tx['directories'][str(path)]:
                raise PublicationConflict('directory conflict retained', (str(path.parent / quarantine),))
            os.rmdir(quarantine, dir_fd=directory.fd)  # No recursive removal.
            os.fsync(directory.fd)
    return 'removed'


def remove_account(tx):
    if resolve_account(tx) == 'absent':
        return 'absent'
    run(['/usr/sbin/userdel', USER])
    if resolve_account(tx) != 'absent':
        raise RuntimeError('account deletion not confirmed')
    return 'removed'


def remove_group(tx):
    try:
        group = grp.getgrnam(USER)
    except KeyError:
        return 'absent'
    if (tx['created'] is None or group.gr_name != USER
            or group.gr_gid != tx['created'][1] or group.gr_mem):
        raise RuntimeError('partial group identity unknown; preserve group')
    try:
        pwd.getpwnam(USER)
    except KeyError:
        run(['/usr/sbin/groupdel', USER])
    else:
        raise RuntimeError('account remains; preserve group')
    try:
        grp.getgrnam(USER)
    except KeyError:
        return 'removed'
    raise RuntimeError('group deletion not confirmed')


def recover(tx):
    results = []
    def attempt(step, action):
        try:
            value = action()
            result = {'step': step, 'status': 'ok', 'result': value}
        except Exception as error:
            value = None
            result = {'step': step, 'status': 'pending', 'error_type': type(error).__name__,
                      'recovery_locations': list(getattr(error, 'locations', ()))}
        results.append(result)
        try:
            tx['journal'].record('recovery-step', operation=step, **{k: v for k, v in result.items() if k != 'step'})
        except Exception as error:
            results.append({'step': 'journal-' + step, 'status': 'pending',
                            'error_type': type(error).__name__})
        return value
    state = attempt('account-identity', lambda: resolve_account(tx))
    # Revocation can be independently safe even if later account identity changed.
    revoked = attempt('authorization', lambda: revoke_authorization(tx))
    sessions = attempt('sessions', lambda: no_sessions(tx)) if state in ('owned', 'absent') else None
    safe = state in ('owned', 'absent') and revoked in ('removed', 'absent') and sessions is True
    if safe:
        attempt('config', lambda: restore_config(tx))
        # These operations do not depend on restoring a shared config successfully.
        attempt('home', lambda: remove_home(tx))
        attempt('account', lambda: remove_account(tx))
        if tx['created'] is not None:
            attempt('group', lambda: remove_group(tx))
    else:
        results.append({'step': 'restrictions-and-account', 'status': 'pending',
                        'result': 'preserved; active sessions or unknown identity/authorization'})
    # An uncertain useradd can have created only a group, without a passwd entry.
    if tx['created'] is None:
        attempt('partial-group', lambda: remove_group(tx))
    return results


class AdoptionFailure(RuntimeError):
    def __init__(self, primary, recovery):
        self.primary = primary
        self.recovery = recovery
        pending = ','.join(r['step'] for r in recovery if r['status'] != 'ok')
        super().__init__(str(primary) + ('; recovery pending: ' + pending if pending else '; recovery complete'))


def execute_adoption(payload, original, metadata, attributes, candidate, auth, journal):
    tx = dict(payload=payload, original=original, metadata=metadata, attributes=attributes,
              candidate=candidate, auth=auth, journal=journal, created=None,
              auth_identity=None, directories={}, published=None, config_conflict=False)
    # Durable intent precedes useradd; the random GECOS marker is written atomically
    # with the passwd entry, so an effect followed by timeout remains identifiable.
    journal.record('account-create-intent', marker=journal.marker, username=USER,
                   home=str(HOME), account_preimage='absent', group_preimage='absent')
    committed, primary = False, None
    try:
        run(['/usr/sbin/useradd', '--system', '--user-group', '--no-create-home',
             '--home-dir', str(HOME), '--shell', '/usr/sbin/nologin',
             '--comment', journal.marker, USER])
        if resolve_account(tx) != 'owned':
            raise RuntimeError('new marked account not found')
        create_home(tx)
        try:
            tx['published'] = replace_config(candidate, BASELINE, metadata, attributes, identity(metadata), journal)
        except PublicationConflict as error:
            tx['config_conflict'] = error.exchanged
            raise
        journal.record('config-published', **tx['published'])
        # Exact displaced/current identity was verified before any validation/reload.
        verify_publication(tx['published'], candidate)
        run(['/usr/sbin/sshd', '-t', '-f', str(CONFIG)])
        verify_publication(tx['published'], candidate)
        run(['/usr/bin/systemctl', 'reload', payload['service']])
        event('awaiting-new-tunnel-login', candidate_sha256=digest(candidate),
              original_sha256=BASELINE, original_length=len(original),
              suffix_sha256=digest(candidate[len(original):]),
              public_authorization_sha256=digest(auth), uid=tx['created'][0], gid=tx['created'][1])
        if not select.select([sys.stdin.buffer], [], [], payload['verification_timeout'])[0]:
            raise RuntimeError('independent verification not committed')
        if sys.stdin.buffer.readline(256).strip() != ('commit ' + digest(candidate)).encode():
            raise RuntimeError('independent verification not committed')
        committed = True
        journal.record('committed', candidate_sha256=digest(candidate))
        event('committed', candidate_sha256=digest(candidate))
    except BaseException as error:
        primary = error
    if primary is not None:
        notes = []
        try:
            journal.record('adoption-error', error_type=type(primary).__name__,
                           recovery_locations=list(getattr(primary, 'locations', ())))
        except Exception as error:
            notes.append({'step': 'journal-primary', 'status': 'pending', 'error_type': type(error).__name__})
        recovery = notes + ([{'step': 'commit-receipt', 'status': 'pending',
                              'result': 'commit accepted; restricted runtime preserved'}]
                            if committed else recover(tx))
        raise AdoptionFailure(primary, recovery) from primary


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
    CONFIG, HOME = Path(payload['sshd_config']), Path(payload['account_home'])
    USER, BASELINE = payload['username'], payload['expected_sha256']
    public = payload['public_key']
    if not re.fullmatch(r'ecdsa-sha2-nistp256 [A-Za-z0-9+/]+={0,2} lab-ssh-backup\n?', public):
        raise RuntimeError('unexpected public key')
    base64.b64decode(public.split()[1], validate=True)
    original, metadata, attributes = file_snapshot(CONFIG)
    if metadata.st_uid != 0 or digest(original) != BASELINE:
        raise RuntimeError('config preimage mismatch')
    backup = Path(tempfile.mkdtemp(prefix='lab-ssh-backup-preimage-', dir=Path.home()))
    os.chmod(backup, 0o700)
    with (backup / 'sshd_config').open('xb') as out:
        os.fchmod(out.fileno(), 0o600)
        out.write(original)
        out.flush()
        os.fsync(out.fileno())
    if digest((backup / 'sshd_config').read_bytes()) != BASELINE:
        raise RuntimeError('backup verification failed')
    journal = RecoveryJournal(backup)
    event('backup-verified', path=str(backup), recovery=str(journal.path))
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
    execute_adoption(payload, original, metadata, attributes, candidate, auth, journal)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        event('stopped', error=str(error))
        sys.exit(1)
