import importlib.util
import os
from pathlib import Path
import shutil
import stat
import tempfile
import unittest
from contextlib import contextmanager
from unittest.mock import patch


FILE = Path(__file__).resolve().parents[1] / "scripts/linux_rule_cache_fixture.py"
spec = importlib.util.spec_from_file_location("linux_rule_cache_fixture", FILE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def evaluate(machine, nr, family=0, protocol=0, audit=None):
    words = {0: nr, 4: m.ARCH[machine][0] if audit is None else audit, 16: family, 32: protocol}
    rows = m.instructions(machine)
    pc = acc = steps = 0
    while pc < len(rows):
        steps += 1
        if steps > 100:
            raise AssertionError("filter did not terminate")
        code, jt, jf, k = rows[pc]
        if code == 0x20:
            acc = words[k]
        elif code == 0x15:
            pc += jt if acc == k else jf
        elif code == 0x45:
            pc += jt if acc & k else jf
        elif code == 0x06:
            return k
        else:
            raise AssertionError("unexpected opcode")
        pc += 1
    raise AssertionError("no return")


@contextmanager
def owned_case():
    root = Path(tempfile.mkdtemp(prefix="mlpa-cache-unit-", dir=Path.home()))
    identity = root.stat()
    try:
        yield root
    finally:
        assert root.resolve() == root and root.parent == Path.home().resolve()
        assert root.name.startswith("mlpa-cache-unit-") and root.stat().st_uid == os.getuid()
        assert (root.stat().st_dev, root.stat().st_ino) == (identity.st_dev, identity.st_ino)
        shutil.rmtree(root)


class FilterContract(unittest.TestCase):
    def test_all_socket_domains_except_kernel_route_are_denied(self):
        for machine, (_, nr, _) in m.ARCH.items():
            for family in range(256):
                self.assertEqual(evaluate(machine, nr, family), m.ALLOW if family == 16 else m.DENY)
            for protocol in (1, 2, 3, 9, 16, 31):
                self.assertEqual(evaluate(machine, nr, 16, protocol), m.DENY)

    def test_socketpair_and_uring_are_denied(self):
        for machine, (_, _, pair) in m.ARCH.items():
            for nr in (pair, 425, 426, 427):
                self.assertEqual(evaluate(machine, nr), m.DENY)

    def test_arch_switch_killed_and_x32_denied(self):
        for machine in m.ARCH:
            self.assertEqual(evaluate(machine, 0, audit=0x40000003), m.KILL)
            for nr in (0, 41, 53, 198, 199, 425):
                self.assertEqual(evaluate(machine, nr | 0x40000000), m.DENY)

    def test_non_network_operations_unchanged(self):
        for machine in m.ARCH:
            for nr in (0, 1, 2, 3, 9, 10, 22, 38, 60, 231):
                self.assertEqual(evaluate(machine, nr), m.ALLOW)

    def test_unknown_arch_rejected(self):
        with self.assertRaises(m.Rejected):
            m.instructions("i386")


class PrivilegeContract(unittest.TestCase):
    @staticmethod
    def state():
        return {"Uid": "1000 1000 1000 1000", "CapEff": "0", "CapPrm": "0",
                "CapInh": "0", "CapAmb": "0", "NoNewPrivs": "1", "Seccomp": "2"}

    def test_all_four_zero_sets_and_matching_UIDs_accepted(self):
        m.validate_identity(self.state(), 1000)

    def test_every_nonzero_capability_set_rejected(self):
        for key in ("CapEff", "CapPrm", "CapInh", "CapAmb"):
            state = self.state()
            state[key] = "0000000000001000"
            with self.assertRaises(m.Rejected):
                m.validate_identity(state, 1000)

    def test_any_native_UID_mismatch_or_root_rejected(self):
        for position in range(4):
            state = self.state()
            values = ["1000"] * 4
            values[position] = "0" if position % 2 else "1001"
            state["Uid"] = " ".join(values)
            with self.assertRaises(m.Rejected):
                m.validate_identity(state, 1000)
        with self.assertRaises(m.Rejected):
            m.validate_identity(self.state(), 0)

    def test_proc_parser_keeps_Prm_Inh_and_parent_gate_rejects_them(self):
        state = self.state()
        state["CapPrm"] = state["CapInh"] = "1000"
        text = "\n".join(key + ":\t" + value for key, value in state.items())
        with patch.object(m.Path, "read_text", return_value=text):
            parsed = m.process_status(123)
        self.assertEqual(parsed["CapPrm"], "1000")
        self.assertEqual(parsed["CapInh"], "1000")
        with patch.object(m, "process_status", return_value=parsed), \
             patch.object(m.os, "getuid", return_value=1000), \
             patch.object(m.os, "geteuid", return_value=1000), \
             patch.object(m.sys, "platform", "linux"):
            with self.assertRaises(m.Rejected):
                m.unprivileged()


class PublicInputContract(unittest.TestCase):
    def test_read_accepts_legitimate_atime_change(self):
        with owned_case() as root:
            p = root / "public.srs"
            p.write_bytes(b"public-only-fixture")
            p.chmod(0o600)
            os.utime(p, ns=(1, p.stat().st_mtime_ns))
            self.assertEqual(m.public_file(p, m.sha(b"public-only-fixture"), 100, os.getuid()),
                             b"public-only-fixture")

    def test_hash_symlink_hardlink_writable_or_oversize_rejected(self):
        with owned_case() as root:
            p = root / "public.srs"
            p.write_bytes(b"public-fixture")
            p.chmod(0o600)
            good = m.sha(p.read_bytes())
            for digest, maximum in (("0" * 64, 100), (good, 1)):
                with self.assertRaises(m.Rejected):
                    m.public_file(p, digest, maximum, os.getuid())
            link = root / "link.srs"
            link.symlink_to(p)
            with self.assertRaises(m.Rejected):
                m.public_file(link, good, 100, os.getuid())
            hard = root / "hard.srs"
            os.link(p, hard)
            with self.assertRaises(m.Rejected):
                m.public_file(p, good, 100, os.getuid())
            q = root / "writable.srs"
            q.write_bytes(b"public-fixture")
            q.chmod(0o666)
            with self.assertRaises(m.Rejected):
                m.public_file(q, good, 100, os.getuid())

    def test_public_config_has_no_takeover_or_secret_features(self):
        c = m.config(Path("/fixture/new.db"), m.URLS)
        self.assertEqual(c["inbounds"], [])
        self.assertEqual(c["outbounds"], [{"type": "direct", "tag": "direct"}])
        self.assertEqual(set(c), {"log", "dns", "inbounds", "outbounds", "route", "experimental"})
        cache = c["experimental"]["cache_file"]
        self.assertFalse(cache["store_fakeip"])
        self.assertFalse(cache["store_rdrc"])
        self.assertEqual(cache["cache_id"], "mlpa-public-fixture-only-v1")
        self.assertFalse(c["route"]["auto_detect_interface"])
        self.assertEqual({x["url"] for x in c["route"]["rule_set"]}, set(m.URLS.values()))
        self.assertEqual({x["tag"] for x in c["route"]["rule_set"]}, {"fixture-domain", "fixture-ip"})


if __name__ == "__main__":
    unittest.main()
