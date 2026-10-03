"""Storage identity and platform dispatch checks; no node or service access."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('linux_storage', ROOT / 'scripts/lib/linux_storage_runtime.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class LinuxStorageTests(unittest.TestCase):
    def test_binary_selection_matches_platform(self):
        adapter_spec = importlib.util.spec_from_file_location('adapter', ROOT / 'scripts/lib/client_fixture_result.py')
        adapter = importlib.util.module_from_spec(adapter_spec)
        adapter_spec.loader.exec_module(adapter)
        self.assertEqual(adapter.BINARY, guard.BINARY)

    def test_adapter_never_hashes_unregistered_path(self):
        adapter_spec = importlib.util.spec_from_file_location('adapter', ROOT / 'scripts/lib/client_fixture_result.py')
        adapter = importlib.util.module_from_spec(adapter_spec)
        adapter_spec.loader.exec_module(adapter)
        with patch.object(adapter, 'sha_file') as hashed:
            self.assertIsNone(adapter.optional_hash(Path('/tmp/unregistered-runtime')))
            hashed.assert_not_called()

    def test_overrides_are_closed(self):
        with patch.object(guard, 'canonical'), patch.object(Path, 'open') as opened, \
             patch.object(guard.hashlib, 'file_digest', return_value=SimpleNamespace(hexdigest=lambda: guard.EXPECTED_SHA)):
            for allowed in ('', str(guard.BINARY), str(guard.PROJECT / 'scripts/external-sing-box')):
                guard.verify(str(guard.PROJECT / 'scripts'), allowed)
            for rejected in ('/usr/local/bin/sing-box', '/usr/bin/sing-box', './scripts/external-sing-box',
                             str(guard.BINARY) + '/..', str(guard.BINARY) + '-other',
                             str(guard.PROJECT / 'tools/sing-box/sing-box')):
                with self.subTest(rejected=rejected), self.assertRaises(ValueError):
                    guard.verify(str(guard.PROJECT / 'scripts'), rejected)
            self.assertEqual(opened.call_count, 3)

    def test_wrong_caller_project_and_fingerprint(self):
        with patch.object(guard.os, 'getuid', return_value=0), self.assertRaises(ValueError):
            guard.verify(str(guard.PROJECT / 'scripts'), '')
        with self.assertRaises(ValueError):
            guard.verify('/tmp/copied-project/scripts', '')
        with patch.object(guard, 'canonical'), patch.object(Path, 'open'), \
             patch.object(guard.hashlib, 'file_digest', return_value=SimpleNamespace(hexdigest=lambda: 'changed')), \
             self.assertRaises(ValueError):
            guard.verify(str(guard.PROJECT / 'scripts'), '')

    def test_canonical_symlinks_and_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); target = base / 'real'; target.mkdir()
            alias = base / 'alias'; alias.symlink_to(target, target_is_directory=True)
            for path in (alias, alias / 'child', base / 'missing'):
                with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                    guard.canonical(path)

    def test_filesystem_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); root.chmod(0o700)
            with patch.object(guard.subprocess, 'run', return_value=SimpleNamespace(stdout=guard.EXPECTED_UUID + ' ext4\n')):
                guard.canonical(root, private=True)
            for wrong in ('wrong ext4', guard.EXPECTED_UUID + ' tmpfs', ''):
                with patch.object(guard.subprocess, 'run', return_value=SimpleNamespace(stdout=wrong)), self.assertRaises(ValueError):
                    guard.canonical(root)
            root.chmod(0o777)
            with self.assertRaises(ValueError): guard.canonical(root)

    def test_owner_and_executable_type(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); binary = root / 'binary'; binary.write_bytes(b'fixture'); binary.chmod(0o600)
            with self.assertRaises(ValueError): guard.canonical(binary, executable=True)
            with self.assertRaises(ValueError): guard.canonical(root, executable=True)
            real_stat = root.stat()
            with patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=0, st_mode=real_stat.st_mode)), self.assertRaises(ValueError):
                guard.canonical(root)

    def test_dispatch_branches_are_disjoint(self):
        # Exercise a copied dispatcher with markers, never a real Darwin volume.
        original = (ROOT / 'scripts/lib/storage_runtime.sh').read_text()
        self.assertIn('$(/usr/bin/uname -s)', original)
        for platform, expected in [('Linux', 'LINUX_GUARD'), ('Darwin', 'DARWIN_BODY'), ('Unknown', None)]:
            with tempfile.TemporaryDirectory() as directory:
                scripts = Path(directory) / 'scripts'; lib = scripts / 'lib'; lib.mkdir(parents=True)
                source = original.replace('$(/usr/bin/uname -s)', '$(printf ' + platform + ')')
                source = source.replace('/usr/bin/python3 -I "$rpn_script_root/lib/linux_storage_runtime.py" "$rpn_script_root" "$rpn_requested"', "printf 'LINUX_GUARD\\n'")
                (lib / 'storage_runtime.sh').write_text(source)
                (lib / 'storage_runtime_macos.sh').write_text("rpn_storage_prepare() { printf 'DARWIN_BODY\\n'; }\n")
                process = subprocess.run(['bash', '-c', 'source "$1"; rpn_storage_prepare', 'dispatch', str(lib / 'storage_runtime.sh')],
                                         capture_output=True, text=True, env={'PATH': '/usr/bin:/bin'})
                if expected is None:
                    self.assertEqual(process.returncode, 78)
                else:
                    self.assertEqual(process.returncode, 0)
                    self.assertEqual(process.stdout.strip(), expected)


if __name__ == '__main__':
    unittest.main()
