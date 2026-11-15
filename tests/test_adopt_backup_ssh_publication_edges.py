"""Real unprivileged file publication tests; account/service operations are trapped."""
import errno
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/adopt_backup_ssh_account.py'
spec = importlib.util.spec_from_file_location('backup_publication_edges', SCRIPT)
adopt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adopt)


class PublicationEdges(unittest.TestCase):
    def setUp(self):
        base = Path(os.environ.get('RPN_TEST_TMPDIR', str(Path.home())))
        self.temp = tempfile.TemporaryDirectory(prefix='rpn-publication-', dir=base)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        self.config = self.root / 'sshd_config'
        self.original = b'# synthetic original\nPasswordAuthentication no\n'
        self.candidate = self.original + b'# synthetic candidate\n'
        self.config.write_bytes(self.original)
        adopt.CONFIG = self.config
        self.backup = self.root / 'recovery'
        self.backup.mkdir(mode=0o700)
        self.journal = adopt.RecoveryJournal(self.backup)
        for owner, name in [(adopt, 'run'), (subprocess, 'run'),
                            (adopt.pwd, 'getpwnam'), (adopt.grp, 'getgrnam')]:
            patch = mock.patch.object(owner, name,
                                      side_effect=AssertionError('real account/service/process operation'))
            patch.start()
            self.addCleanup(patch.stop)

    def publish(self, snapshot=None):
        before, metadata, attributes = snapshot or adopt.file_snapshot(self.config)
        return adopt.replace_config(self.candidate, adopt.digest(before), metadata, attributes,
                                    expected_identity=adopt.identity(metadata), journal=self.journal)

    def test_real_exchange_has_durable_intent_and_retains_original(self):
        real = adopt.rename_at
        intents_seen = []

        def exchange(fd, source, target, flags):
            text = self.journal.path.read_text()
            self.assertIn(str(self.config), text)
            self.assertIn(source, text)
            self.assertIn(adopt.digest(self.original), text)
            self.assertIn(adopt.digest(self.candidate), text)
            self.assertTrue(all(isinstance(json.loads(line), dict) for line in text.splitlines()))
            intents_seen.append(True)
            return real(fd, source, target, flags)

        with mock.patch.object(adopt, 'rename_at', side_effect=exchange):
            receipt = self.publish()
        self.assertEqual(intents_seen, [True])
        self.assertEqual(self.config.read_bytes(), self.candidate)
        self.assertEqual(Path(receipt['retained']).read_bytes(), self.original)
        self.assertIn(receipt['retained'], self.journal.path.read_text())
        self.assertEqual(stat.S_IMODE(self.journal.path.stat().st_mode), 0o600)

    def test_competing_writer_is_retained_and_never_exchanged_back(self):
        real = adopt.rename_at
        competing = b'# synthetic concurrent owner update\n'
        exchanges = []

        def race(fd, source, target, flags):
            self.config.write_bytes(competing)
            exchanges.append((source, target, flags))
            return real(fd, source, target, flags)

        with mock.patch.object(adopt, 'rename_at', side_effect=race):
            with self.assertRaises(adopt.PublicationConflict) as stopped:
                self.publish()
        self.assertEqual(len(exchanges), 1)
        self.assertEqual(self.config.read_bytes(), self.candidate)
        retained = [p for p in self.root.iterdir() if p.is_file() and p != self.config]
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0].read_bytes(), competing)
        self.assertIn(str(retained[0]), self.journal.path.read_text())
        self.assertIn(str(retained[0]), stopped.exception.locations)

    def test_changed_xattr_preimage_is_not_published_over(self):
        before = adopt.file_snapshot(self.config)
        try:
            os.setxattr(self.config, 'user.rpn_fixture', b'concurrent metadata')
        except OSError as error:
            if error.errno in (errno.ENOTSUP, errno.EOPNOTSUPP):
                self.skipTest('fixture filesystem has no user xattrs')
            raise
        with self.assertRaises(adopt.PublicationConflict):
            self.publish(before)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertEqual(os.getxattr(self.config, 'user.rpn_fixture'), b'concurrent metadata')
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['recovery', 'sshd_config'])

    def test_attribute_write_failure_cleans_only_unpublished_candidate(self):
        try:
            os.setxattr(self.config, 'user.rpn_fixture', b'fixture')
        except OSError as error:
            if error.errno in (errno.ENOTSUP, errno.EOPNOTSUPP):
                self.skipTest('fixture filesystem has no user xattrs')
            raise
        before = adopt.file_snapshot(self.config)
        with mock.patch.object(adopt.os, 'setxattr', side_effect=OSError('synthetic attribute write failure')):
            with self.assertRaisesRegex(OSError, 'synthetic attribute write failure'):
                self.publish(before)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['recovery', 'sshd_config'])

    def test_exchange_unavailable_refuses_without_fallback(self):
        with mock.patch.object(adopt, 'rename_at', side_effect=OSError(errno.ENOSYS, 'synthetic unavailable')):
            with self.assertRaises(OSError) as stopped:
                self.publish()
        self.assertEqual(stopped.exception.errno, errno.ENOSYS)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['recovery', 'sshd_config'])

    def test_journal_name_swap_is_detected_before_caller_continues(self):
        original_inode = self.journal.path.stat().st_ino
        real_fsync = os.fsync
        swapped = []

        def swap(fd):
            if os.fstat(fd).st_ino == original_inode and not swapped:
                replacement = self.backup / 'replacement'
                replacement.write_text('{"step":"synthetic replacement"}\n')
                os.chmod(replacement, 0o600)
                os.replace(replacement, self.journal.path)
                swapped.append(True)
            return real_fsync(fd)

        with mock.patch.object(adopt.os, 'fsync', side_effect=swap):
            with self.assertRaises(RuntimeError):
                self.journal.record('account-create-intent', marker='synthetic')
        self.assertEqual(swapped, [True])
        self.assertNotEqual(self.journal.path.stat().st_ino, original_inode)

    def test_recreated_authorization_is_pending_and_preserved(self):
        adopt.HOME = self.root / 'synthetic-account-home'
        tx = {'directories': {}, 'auth_identity': None, 'auth': b'synthetic first key\n',
              'journal': self.journal}
        adopt.create_home(tx)
        authorization = adopt.HOME / '.ssh/authorized_keys'
        competing = b'synthetic concurrent authorization\n'
        real_unlink = os.unlink
        recreated = []

        def recreate(name, *args, **kwargs):
            result = real_unlink(name, *args, **kwargs)
            if str(name).startswith('.lab-auth-revoked-'):
                authorization.write_bytes(competing)
                recreated.append(True)
            return result

        with mock.patch.object(adopt.os, 'unlink', side_effect=recreate):
            with self.assertRaises(RuntimeError):
                adopt.revoke_authorization(tx)
        self.assertEqual(recreated, [True])
        self.assertEqual(authorization.read_bytes(), competing)


if __name__ == '__main__':
    unittest.main()
