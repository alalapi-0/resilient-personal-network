"""Synthetic account/service traps and private Linux file-exchange fixtures only."""
import errno
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('backup_adoption', ROOT / 'scripts/adopt_backup_ssh_account.py')
adopt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adopt)
PRODUCTION_PIN = adopt.PinnedDirectory


class AdoptionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='rpn-safety-test-',
            dir=os.environ.get('RPN_TEST_TMPDIR', str(Path.home())))
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.root.chmod(0o700)
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        self.addCleanup(patch.stopall)
        patch.object(adopt.subprocess, 'run', side_effect=AssertionError('real external command forbidden')).start()
        patch.object(adopt, 'uid_process_present', return_value=False).start()
        patch.object(adopt, 'event').start()
        self.config = self.root / 'sshd_config'
        self.original = b'# synthetic existing policy\n'
        self.candidate = self.original + b'# synthetic restricted Match policy\n'
        self.config.write_bytes(self.original)
        self.config.chmod(0o600)
        self.metadata = self.config.stat()
        self.home = self.root / 'account'
        for name, value in [('CONFIG', self.config), ('HOME', self.home), ('USER', 'fixture_backup'),
                            ('BASELINE', adopt.digest(self.original))]:
            patch.object(adopt, name, value, create=True).start()
        self.backup = self.root / 'backup'
        self.backup.mkdir(mode=0o700)
        self.journal = adopt.RecoveryJournal(self.backup)
        self.users, self.groups, self.calls = {}, {}, []
        patch.object(adopt.pwd, 'getpwnam', side_effect=self.user_lookup).start()
        patch.object(adopt.grp, 'getgrnam', side_effect=self.group_lookup).start()
        patch.object(adopt, 'run', side_effect=self.fake_run).start()
        patch.object(adopt.select, 'select', return_value=([], [], [])).start()
        self.payload = {'listen_port': 12345, 'service': 'fixture.service', 'verification_timeout': 1}
        self.auth = b'synthetic public authorization\n'

    def user_lookup(self, name):
        if name not in self.users:
            raise KeyError(name)
        return self.users[name]

    def group_lookup(self, name):
        if name not in self.groups:
            raise KeyError(name)
        return self.groups[name]

    def add_account(self, marker=None):
        self.users[adopt.USER] = SimpleNamespace(pw_uid=21001, pw_gid=21002, pw_dir=str(self.home),
            pw_gecos=self.journal.marker if marker is None else marker, pw_name=adopt.USER,
            pw_shell='/usr/sbin/nologin')
        self.groups[adopt.USER] = SimpleNamespace(gr_name=adopt.USER, gr_gid=21002, gr_mem=[])

    def fake_run(self, argv, data=None):
        self.calls.append(tuple(argv))
        if argv[0] == '/usr/sbin/useradd':
            self.assertIn('--comment', argv)
            self.assertEqual(argv[argv.index('--comment') + 1], self.journal.marker)
            self.add_account()
        elif argv[0] == '/usr/sbin/userdel':
            self.users.pop(adopt.USER, None)
        elif argv[0] == '/usr/sbin/groupdel':
            self.groups.pop(adopt.USER, None)
        elif argv[0] not in ('/usr/bin/ss', '/usr/sbin/sshd', '/usr/bin/systemctl'):
            raise AssertionError('unexpected external operation')
        return b''

    def execute(self):
        return adopt.execute_adoption(self.payload, self.original, self.metadata, {},
                                      self.candidate, self.auth, self.journal)

    def transaction(self):
        return dict(payload=self.payload, original=self.original, metadata=self.metadata,
                    attributes={}, candidate=self.candidate, auth=self.auth, journal=self.journal,
                    created=None, auth_identity=None, directories={}, published=None, config_conflict=False)

    def test_root_approval_gate(self):
        with patch.object(adopt.os, 'geteuid', return_value=1000), self.assertRaisesRegex(RuntimeError, 'approved root'):
            adopt.main()
        self.assertEqual(self.calls, [])

    def test_production_pin_rejects_writable_ancestor(self):
        writable = self.root / 'writable'
        writable.mkdir(mode=0o700)
        writable.chmod(0o777)
        with self.assertRaisesRegex(RuntimeError, 'owner/permissions'):
            PRODUCTION_PIN(writable)
        with self.assertRaisesRegex(RuntimeError, 'owner/permissions'):
            adopt.PinnedDirectory(writable)

    def test_pin_rejects_foreign_directory_owner(self):
        original = os.fstat
        def foreign(fd):
            info = original(fd)
            values = {name: getattr(info, name) for name in ('st_dev','st_ino','st_mode','st_uid')}
            values['st_uid'] = 987654
            return SimpleNamespace(**values)
        with patch.object(adopt.os, 'fstat', side_effect=foreign), self.assertRaisesRegex(RuntimeError, 'owner/permissions'):
            adopt.PinnedDirectory(self.root)

    def test_creation_intent_fsynced_before_useradd_effect_timeout(self):
        synced_intent = []
        real_fsync = os.fsync
        def sync(fd):
            real_fsync(fd)
            if (os.fstat(fd).st_dev, os.fstat(fd).st_ino) == self.journal.inode:
                if b'account-create-intent' in self.journal.path.read_bytes():
                    synced_intent.append(True)
        def timeout(argv, data=None):
            if argv[0] == '/usr/sbin/useradd':
                self.assertTrue(synced_intent)
                self.assertEqual(stat.S_IMODE(self.journal.path.stat().st_mode), 0o600)
                self.fake_run(argv, data)
                raise subprocess.TimeoutExpired('synthetic-useradd', 20)
            return self.fake_run(argv, data)
        with patch.object(adopt.os, 'fsync', side_effect=sync), patch.object(adopt, 'run', side_effect=timeout):
            with self.assertRaises(adopt.AdoptionFailure) as caught:
                self.execute()
        self.assertIsInstance(caught.exception.primary, subprocess.TimeoutExpired)
        self.assertEqual(self.users, {})
        self.assertEqual(self.groups, {})
        self.assertIn(b'marked-account-recovered', self.journal.path.read_bytes())
        self.assertEqual(self.config.read_bytes(), self.original)

    def test_group_only_partial_creation_is_preserved_pending(self):
        def partial(argv, data=None):
            if argv[0] == '/usr/sbin/useradd':
                self.groups[adopt.USER] = SimpleNamespace(gr_name=adopt.USER, gr_gid=21002, gr_mem=[])
                raise subprocess.TimeoutExpired('synthetic-useradd', 20)
            return self.fake_run(argv, data)
        with patch.object(adopt, 'run', side_effect=partial), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertIn(adopt.USER, self.groups)
        self.assertTrue(any(r['step']=='partial-group' and r['status']=='pending' for r in caught.exception.recovery))
        self.assertFalse(any(c[0]=='/usr/sbin/groupdel' for c in self.calls))

    def test_unmarked_account_and_group_are_preserved(self):
        def unknown(argv, data=None):
            if argv[0] == '/usr/sbin/useradd':
                self.add_account(marker='foreign-marker')
                raise subprocess.TimeoutExpired('synthetic-useradd', 20)
            return self.fake_run(argv, data)
        with patch.object(adopt, 'run', side_effect=unknown), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertIn(adopt.USER, self.users)
        self.assertIn(adopt.USER, self.groups)
        self.assertIn('restrictions-and-account', [r['step'] for r in caught.exception.recovery])
        self.assertFalse(any(c[0] in ('/usr/sbin/userdel','/usr/sbin/groupdel') for c in self.calls))

    def test_nss_failure_is_pending_and_does_not_infer_ownership(self):
        with patch.object(adopt.pwd, 'getpwnam', side_effect=OSError('synthetic NSS unavailable')):
            with self.assertRaises(adopt.AdoptionFailure) as caught:
                self.execute()
        self.assertIsInstance(caught.exception.primary, OSError)
        self.assertIn(adopt.USER, self.users)
        self.assertTrue(any(r['step']=='account-identity' and r['status']=='pending' for r in caught.exception.recovery))
        self.assertFalse(any(c[0]=='/usr/sbin/userdel' for c in self.calls))

    def test_marked_account_requires_name_shell_and_full_identity(self):
        for field, value in [('pw_name','other'), ('pw_shell','/bin/sh'), ('pw_uid',0), ('pw_gid',0)]:
            with self.subTest(field=field):
                self.add_account()
                setattr(self.users[adopt.USER], field, value)
                with self.assertRaisesRegex(RuntimeError, 'unknown'):
                    adopt.resolve_account(self.transaction())
        self.add_account()
        tx = self.transaction()
        adopt.resolve_account(tx)
        self.users[adopt.USER].pw_uid += 1
        with self.assertRaisesRegex(RuntimeError, 'changed'):
            adopt.resolve_account(tx)

    def test_primary_and_multiple_cleanup_errors_are_preserved(self):
        def fail_create(tx):
            raise ValueError('synthetic primary failure')
        def record(step, **fields):
            if step == 'recovery-step':
                raise OSError('synthetic journal failure')
        with patch.object(adopt, 'create_home', side_effect=fail_create), \
             patch.object(adopt, 'restore_config', side_effect=OSError('synthetic config failure')) as restored, \
             patch.object(adopt, 'remove_home', side_effect=OSError('synthetic home failure')) as home, \
             patch.object(self.journal, 'record', side_effect=record):
            with self.assertRaises(adopt.AdoptionFailure) as caught:
                self.execute()
        self.assertIsInstance(caught.exception.primary, ValueError)
        self.assertIn('synthetic primary failure', str(caught.exception))
        self.assertIn('journal-', str(caught.exception))
        restored.assert_called_once()
        home.assert_called_once()
        self.assertEqual(self.users, {})
        self.assertEqual(self.groups, {})

    def test_active_session_keeps_restricting_policy_and_account(self):
        with patch.object(adopt, 'uid_process_present', return_value=True), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertEqual(self.config.read_bytes(), self.candidate)
        self.assertIn(adopt.USER, self.users)
        self.assertFalse((self.home/'.ssh/authorized_keys').exists())
        self.assertTrue(any(r['step']=='restrictions-and-account' for r in caught.exception.recovery))
        self.assertEqual(sum(c[0]=='/usr/bin/systemctl' for c in self.calls), 1)

    def test_quarantine_disappearance_is_pending_and_keeps_restrictions(self):
        real = adopt.rename_at
        def disappear(fd, source, target, flags):
            result = real(fd, source, target, flags)
            if target.startswith('.lab-auth-revoked-'):
                os.unlink(target, dir_fd=fd)
            return result
        with patch.object(adopt,'rename_at',side_effect=disappear), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertTrue(any(r['step']=='authorization' and r['status']=='pending' for r in caught.exception.recovery))
        self.assertEqual(self.config.read_bytes(),self.candidate)
        self.assertIn(adopt.USER,self.users)
        self.assertIn(b'authorization-recovery-pending',self.journal.path.read_bytes())
        self.assertEqual(sum(c[0]=='/usr/bin/systemctl' for c in self.calls),1)

    def test_normal_uncommitted_recovery_restores_and_removes_owned_objects(self):
        with self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertIn('independent verification not committed', str(caught.exception))
        self.assertTrue(all(r['status']=='ok' for r in caught.exception.recovery), caught.exception.recovery)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertFalse(self.home.exists())
        self.assertEqual(self.users, {})
        self.assertEqual(self.groups, {})
        self.assertEqual(sum(c[0]=='/usr/bin/systemctl' for c in self.calls), 2)
        self.assertIn(b'config-exchange-verified', self.journal.path.read_bytes())

    def test_journal_failure_before_intent_prevents_useradd(self):
        with patch.object(self.journal, 'record', side_effect=OSError('no durable intent')), self.assertRaises(OSError):
            self.execute()
        self.assertEqual(self.calls, [])

    def test_journal_named_inode_replacement_prevents_useradd(self):
        real_fsync = os.fsync
        changed = []
        def replace_named(fd):
            real_fsync(fd)
            if not changed and (os.fstat(fd).st_dev,os.fstat(fd).st_ino)==self.journal.inode:
                if b'account-create-intent' in self.journal.path.read_bytes():
                    old = self.journal.path.with_name('displaced-journal')
                    self.journal.path.rename(old)
                    self.journal.path.write_bytes(b'foreign-journal')
                    self.journal.path.chmod(0o600)
                    changed.append(True)
        with patch.object(adopt.os, 'fsync', side_effect=replace_named), self.assertRaisesRegex(RuntimeError, 'journal replaced'):
            self.execute()
        self.assertEqual(self.calls, [])
        self.assertEqual(self.journal.path.read_bytes(), b'foreign-journal')

    def test_real_exchange_retains_original_and_validates_receipt(self):
        receipt = adopt.replace_config(self.candidate, adopt.BASELINE, self.metadata, {},
                                       adopt.identity(self.metadata), self.journal)
        self.assertEqual(Path(receipt['retained']).read_bytes(), self.original)
        self.assertEqual(self.config.read_bytes(), self.candidate)
        adopt.verify_publication(receipt, self.candidate)
        entries = [json.loads(line) for line in self.journal.path.read_text().splitlines()]
        self.assertEqual(entries[0]['step'], 'config-exchange-intent')
        self.assertIn('directory_identity',entries[0])
        self.assertEqual(entries[-1]['step'], 'config-exchange-verified')

    def test_writer_between_snapshot_and_exchange_is_retained_and_not_rolled_back(self):
        real_rename = adopt.rename_at
        concurrent = b'synthetic concurrent config'
        def race(fd, source, target, flags):
            if flags == 2:
                self.config.write_bytes(concurrent)
            return real_rename(fd, source, target, flags)
        with patch.object(adopt, 'rename_at', side_effect=race), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        error = caught.exception.primary
        self.assertIsInstance(error, adopt.PublicationConflict)
        self.assertTrue(error.exchanged)
        self.assertEqual(self.config.read_bytes(), self.candidate)
        retained = Path(error.locations[1])
        self.assertEqual(retained.read_bytes(), concurrent)
        self.assertIn(str(retained),str(error))
        self.assertFalse(any(c[0]=='/usr/bin/systemctl' for c in self.calls))
        records = self.journal.path.read_text()
        self.assertIn(str(retained), records)
        self.assertIn('config-exchange-pending', records)

    def test_exchange_unsupported_refuses_without_fallback(self):
        with patch.object(adopt, 'rename_at', side_effect=OSError(errno.ENOSYS,'unsupported')):
            with self.assertRaises(OSError):
                adopt.replace_config(self.candidate, adopt.BASELINE, self.metadata, {})
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertEqual(list(self.root.glob('.lab-ssh-backup-retained-*')), [])

    def test_prepare_failure_before_candidate_stamp_removes_owned_temporary(self):
        with patch.object(adopt.os, 'fchmod', side_effect=OSError('synthetic preparation failure')):
            with self.assertRaisesRegex(OSError, 'preparation'):
                adopt.replace_config(self.candidate, adopt.BASELINE, self.metadata, {})
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertEqual(list(self.root.glob('.lab-ssh-backup-retained-*')), [])

    def test_prepare_and_cleanup_failure_keep_primary_and_recovery_location(self):
        with patch.object(adopt.os, 'fchmod', side_effect=OSError('synthetic preparation failure')), \
             patch.object(adopt.os, 'unlink', side_effect=PermissionError('synthetic cleanup failure')):
            with self.assertRaises(adopt.PublicationConflict) as caught:
                adopt.replace_config(self.candidate, adopt.BASELINE, self.metadata, {})
        error = caught.exception
        self.assertIsInstance(error.preparation_error, OSError)
        self.assertIsInstance(error.cleanup_error, PermissionError)
        self.assertIs(error.__cause__,error.preparation_error)
        self.assertTrue(Path(error.locations[0]).exists())
        self.assertEqual(self.config.read_bytes(), self.original)

    def test_xattr_race_is_detected_after_exchange_and_displaced_retained(self):
        os.setxattr(self.config,'user.fixture',b'original')
        self.metadata = self.config.stat()
        real_rename = adopt.rename_at
        def race(fd, source, target, flags):
            os.setxattr(self.config,'user.fixture',b'concurrent')
            return real_rename(fd, source, target, flags)
        with patch.object(adopt,'rename_at',side_effect=race), self.assertRaises(adopt.PublicationConflict) as caught:
            adopt.replace_config(self.candidate, adopt.BASELINE, self.metadata, {'user.fixture':b'original'})
        self.assertEqual(os.getxattr(caught.exception.locations[1],'user.fixture'),b'concurrent')
        self.assertEqual(os.getxattr(self.config,'user.fixture'),b'original')

    def test_snapshot_detects_same_inode_xattr_mutation(self):
        original_list = os.listxattr
        def mutate(fd):
            os.setxattr(fd,'user.fixture',b'changed-during-read')
            return original_list(fd)
        with patch.object(adopt.os,'listxattr',side_effect=mutate), self.assertRaisesRegex(RuntimeError,'during snapshot'):
            adopt.file_snapshot(self.config)

    def test_successful_exchange_journal_failure_stops_reload_and_retains_both(self):
        real_record = self.journal.record
        def fail_verified(step, **fields):
            if step=='config-exchange-verified':
                raise OSError('synthetic verified-receipt failure')
            return real_record(step, **fields)
        with patch.object(self.journal,'record',side_effect=fail_verified), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertIsInstance(caught.exception.primary,adopt.PublicationConflict)
        self.assertEqual(self.config.read_bytes(),self.candidate)
        self.assertTrue(Path(caught.exception.primary.locations[1]).exists())
        self.assertFalse(any(c[0]=='/usr/bin/systemctl' for c in self.calls))

    def test_commit_receipt_failure_keeps_runtime_and_reports_pending(self):
        real_record = self.journal.record
        def fail_commit(step, **fields):
            if step=='committed':
                raise OSError('synthetic commit receipt failure')
            return real_record(step, **fields)
        stream = SimpleNamespace(buffer=io.BytesIO(('commit '+adopt.digest(self.candidate)+'\n').encode()))
        with patch.object(self.journal,'record',side_effect=fail_commit), \
             patch.object(adopt.select,'select',return_value=([stream.buffer],[],[])), \
             patch.object(adopt.sys,'stdin',stream), self.assertRaises(adopt.AdoptionFailure) as caught:
            self.execute()
        self.assertEqual(self.config.read_bytes(),self.candidate)
        self.assertIn(adopt.USER,self.users)
        self.assertTrue((self.home/'.ssh/authorized_keys').exists())
        self.assertTrue(any(r['step']=='commit-receipt' and r['status']=='pending' for r in caught.exception.recovery))
        self.assertNotIn('recovery complete',str(caught.exception))

    def test_accepted_commit_keeps_owned_restricted_account(self):
        stream = SimpleNamespace(buffer=io.BytesIO(('commit '+adopt.digest(self.candidate)+'\n').encode()))
        with patch.object(adopt.select,'select',return_value=([stream.buffer],[],[])), patch.object(adopt.sys,'stdin',stream):
            self.execute()
        self.assertEqual(self.config.read_bytes(),self.candidate)
        self.assertIn(adopt.USER,self.users)
        self.assertIn(b'"step": "committed"', self.journal.path.read_bytes())


if __name__=='__main__':
    unittest.main()
