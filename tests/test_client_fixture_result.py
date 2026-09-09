"""Pure adapter checks: never run the fixture, guard or registered binary."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'scripts/lib/client_fixture_result.py'
spec = importlib.util.spec_from_file_location('fixture_result', MODULE)
result = importlib.util.module_from_spec(spec)
spec.loader.exec_module(result)


class ResultTests(unittest.TestCase):
    def events(self):
        return '\n'.join(['manifest_count:9'] + ['artifact:complete'] * 9 +
                         ['positive:' + name for name in result.POSITIVE] +
                         ['negative:' + name for name in result.NEGATIVE] +
                         ['version:sing-box version 1.12.3', 'stage:complete', 'cleanup:pass'])

    def build(self, raw=None, code=0, after='a'):
        events, valid = result.parse_events(self.events() if raw is None else raw)
        return result.build_result(events, valid, code, 'a', after, 'b', 'b', 'run', 'start')

    def test_complete_and_bounded(self):
        data = self.build()
        self.assertEqual(data['status'], 'pass')
        self.assertEqual(data['artifact_count'], 9)
        self.assertEqual(len(data['negative']['completed']), 12)
        self.assertEqual(data['legacy'], {'target': '1.11.4', 'schema': 'pass', 'binary_validation': 'not_run'})
        files, digest = result.code_snapshot(MODULE.parents[2])
        data['code'].update(files=files, sha256=digest, sha256_after=digest)
        self.assertLessEqual(len(json.dumps(data).encode()) + 1, 8192)

    def test_early_and_partial_failure(self):
        for raw in ('', 'stage:storage', 'manifest_count:9\nartifact:complete\ncleanup:fail'):
            data = self.build(raw, code=78)
            self.assertEqual(data['status'], 'fail')
            self.assertEqual(data['exit_code'], 78)
            self.assertEqual(data['legacy']['schema'], 'not_completed')
            if 'manifest_count:' not in raw:
                self.assertIsNone(data['manifest_count'])

    def test_success_exit_cannot_mask_incomplete_or_changed_evidence(self):
        self.assertEqual(self.build(after='changed')['status'], 'fail')
        for omitted in ('cleanup:pass', 'negative:missing_artifact', 'artifact:complete',
                        'positive:legacy_schema', 'version:sing-box version 1.12.3'):
            self.assertEqual(self.build(self.events().replace(omitted, '', 1))['status'], 'fail')

    def test_unsafe_events_never_echoed(self):
        marker = 'SECRET://example.invalid'
        data = self.build(self.events() + '\nversion:' + marker + '\n' + marker)
        self.assertEqual(data['status'], 'fail')
        self.assertNotIn(marker, json.dumps(data))

    def test_duplicates_and_nonzero_exit_fail(self):
        self.assertEqual(self.build(self.events() + '\npositive:modern_template')['status'], 'fail')
        self.assertEqual(self.build(code=7)['status'], 'fail')

    def test_one_run_clean_environment_and_discarded_output(self):
        import contextlib
        import io
        from types import SimpleNamespace
        calls = []
        def run(args, **kwargs):
            calls.append((args, kwargs))
            self.assertEqual(set(kwargs['env']), {'PATH', 'RPN_RESULT_FD'})
            self.assertEqual(kwargs['stdout'], result.subprocess.DEVNULL)
            self.assertEqual(kwargs['stderr'], result.subprocess.DEVNULL)
            import os
            os.write(kwargs['pass_fds'][0], self.events().encode())
            return SimpleNamespace(returncode=0)
        output = io.StringIO()
        with patch.object(result.subprocess, 'run', side_effect=run), \
             patch.object(result, 'optional_hash', return_value='b'), \
             patch.dict(result.os.environ, {'TEMPLATE_FILE': '/private/secret', 'NODE_HOST': 'secret'}), \
             contextlib.redirect_stdout(output):
            self.assertEqual(result.main(), 0)
        self.assertEqual(len(calls), 1)
        self.assertLessEqual(len(output.getvalue().encode()), 8192)
        self.assertNotIn('secret', output.getvalue())
        self.assertEqual(json.loads(output.getvalue())['status'], 'pass')


if __name__ == '__main__':
    unittest.main()
