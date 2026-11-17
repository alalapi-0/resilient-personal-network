#!/usr/bin/env python3
"""Public-only Linux native remote-rule-cache fixture; never an adopter/status tool.

No real profile, registration or live DB is accepted. All native paths belong to a
new private temporary directory. Output contains fixed results and public hashes.
"""
from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import http.server
import json
import os
from pathlib import Path
import platform
import re
import select
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time

URLS = {
    "domain": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
    "ip": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
}
ALLOW, DENY, KILL = 0x7FFF0000, 0x00050000 | errno.EPERM, 0x80000000
ARCH = {"x86_64": (0xC000003E, 41, 53), "aarch64": (0xC00000B7, 198, 199)}
LIMIT = 8.0


class Rejected(Exception):
    pass


def require(ok, code):
    if not ok:
        raise Rejected(code)


def instructions(machine):
    """Only NETLINK_ROUTE socket creation; no socketpair, x32 or io_uring.

    All other socket domains are denied, not merely AF_INET/AF_INET6. Combined
    with close_fds, no inherited socket, zero capabilities and no_new_privs,
    the isolated native child cannot open an external-IP or IPC proxy socket.
    This is a fixture network restriction, NOT a filesystem/profile sandbox.
    """
    require(machine in ARCH, "ISOLATION_ARCH_UNSUPPORTED")
    audit, nr_socket, nr_pair = ARCH[machine]
    return [
        (0x20, 0, 0, 4), (0x15, 1, 0, audit), (0x06, 0, 0, KILL),
        (0x20, 0, 0, 0), (0x45, 0, 1, 0x40000000), (0x06, 0, 0, DENY),
        (0x15, 0, 1, nr_pair), (0x06, 0, 0, DENY),
        (0x15, 0, 1, 425), (0x06, 0, 0, DENY),
        (0x15, 0, 1, 426), (0x06, 0, 0, DENY),
        (0x15, 0, 1, 427), (0x06, 0, 0, DENY),
        (0x15, 0, 6, nr_socket), (0x20, 0, 0, 16),
        (0x15, 1, 0, 16), (0x06, 0, 0, DENY),
        (0x20, 0, 0, 32), (0x15, 1, 0, 0),
        (0x06, 0, 0, DENY), (0x06, 0, 0, ALLOW),
    ]


def libc():
    return ctypes.CDLL(None, use_errno=True)


def no_new_privs():
    require(libc().prctl(38, 1, 0, 0, 0) == 0, "NO_NEW_PRIVS_FAILED")


def install_filter():
    class Insn(ctypes.Structure):
        _fields_ = [("code", ctypes.c_ushort), ("jt", ctypes.c_ubyte),
                    ("jf", ctypes.c_ubyte), ("k", ctypes.c_uint32)]
    class Program(ctypes.Structure):
        _fields_ = [("len", ctypes.c_ushort), ("filter", ctypes.POINTER(Insn))]
    require(sys.platform.startswith("linux") and sys.byteorder == "little", "ISOLATION_PLATFORM")
    rows = instructions(platform.machine())
    code = (Insn * len(rows))(*(Insn(*row) for row in rows))
    no_new_privs()
    require(libc().prctl(22, 2, ctypes.byref(Program(len(rows), code)), 0, 0) == 0,
            "SECCOMP_INSTALL_FAILED")


def process_status(pid):
    data = Path(f"/proc/{pid}/status").read_text()
    values = dict(line.split(":", 1) for line in data.splitlines() if ":" in line)
    return {k: values[k].strip() for k in
            ("Uid", "CapEff", "CapPrm", "CapInh", "CapAmb", "NoNewPrivs", "Seccomp")}


def validate_identity(state, expected_uid):
    require(expected_uid > 0 and state["Uid"].split() == [str(expected_uid)] * 4,
            "ALL_UIDS_MUST_MATCH_NONROOT_PARENT")
    require(all(int(state[key], 16) == 0 for key in ("CapEff", "CapPrm", "CapInh", "CapAmb")),
            "CAPABILITIES_FORBIDDEN")


def unprivileged():
    require(sys.platform.startswith("linux") and os.getuid() == os.geteuid() != 0,
            "NONROOT_LINUX_REQUIRED")
    require(os.getgid() == os.getegid(), "REAL_EFFECTIVE_GID_MISMATCH")
    state = process_status(os.getpid())
    validate_identity(state, os.getuid())
    require(sys.byteorder == "little" and platform.machine() in ARCH, "ISOLATION_PLATFORM")


def selftest():
    unprivileged()
    install_filter()
    denied = []
    for family in (socket.AF_INET, socket.AF_INET6, socket.AF_UNIX, 17, 40):
        try:
            item = socket.socket(family, socket.SOCK_DGRAM)
        except OSError as exc:
            require(exc.errno == errno.EPERM, "SOCKET_DENIAL_NOT_FILTER")
            denied.append(family)
        else:
            item.close()
            raise Rejected("SOCKET_ISOLATION_BROKEN")
    for nr in (425, 426, 427):
        ctypes.set_errno(0)
        require(libc().syscall(nr, 0, 0, 0, 0, 0, 0) == -1 and
                ctypes.get_errno() == errno.EPERM, "URING_NOT_DENIED")
    with socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, 0):
        pass
    state = process_status(os.getpid())
    validate_identity(state, os.getuid())
    require(state["Seccomp"] == "2" and state["NoNewPrivs"] == "1", "FILTER_STATUS")
    return {"kernel_filter_verified": True, "socket_families_denied_EPERM": denied,
            "io_uring_syscalls_denied_EPERM": [425, 426, 427],
            "netlink_route_socket_allowed": True, "no_root_or_capabilities": True,
            "zero_capability_sets_verified": ["Eff", "Prm", "Inh", "Amb"],
            "four_UIDs_match_nonroot_parent": True}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def public_file(path, digest, maximum, owner):
    require(re.fullmatch("[0-9a-f]{64}", digest) is not None, "DIGEST_REQUIRED")
    item = path.lstat()
    require(path.resolve() == path and stat.S_ISREG(item.st_mode) and item.st_nlink == 1
            and item.st_uid == owner and not stat.S_IMODE(item.st_mode) & 0o022
            and 0 < item.st_size <= maximum, "PUBLIC_INPUT_METADATA")
    signature = lambda s: (s.st_dev, s.st_ino, s.st_uid, s.st_gid, s.st_mode,
                            s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        require(signature(os.fstat(fd)) == signature(item), "PUBLIC_INPUT_CHANGED")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(maximum + 1)
        require(signature(os.fstat(fd)) == signature(item) and len(data) == item.st_size
                and sha(data) == digest, "PUBLIC_INPUT_HASH")
    finally:
        os.close(fd)
    return data


def config(cache_path, source_urls):
    return {
        "log": {"level": "info", "timestamp": False},
        "dns": {"servers": [{"type": "udp", "tag": "fixture-dns", "server": "192.0.2.53"}],
                "final": "fixture-dns"},
        "inbounds": [], "outbounds": [{"type": "direct", "tag": "direct"}],
        "route": {"auto_detect_interface": False, "default_domain_resolver": "fixture-dns",
                  "rule_set": [{"type": "remote", "tag": "fixture-" + key,
                                "format": "binary", "url": source_urls[key],
                                "download_detour": "direct", "update_interval": "24h"}
                               for key in ("domain", "ip")]},
        "experimental": {"cache_file": {"enabled": True, "path": str(cache_path),
                          "cache_id": "mlpa-public-fixture-only-v1",
                          "store_fakeip": False, "store_rdrc": False}},
    }


def native_phase(binary, cfg_path, env, offline):
    require(threading.active_count() == 1 or not offline, "PREEXEC_REQUIRES_SINGLE_THREAD")
    started = False
    status = None
    output = bytearray()
    child = subprocess.Popen([str(binary), "run", "-c", str(cfg_path)],
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, close_fds=True, env=env,
                             start_new_session=True, preexec_fn=install_filter if offline else None)
    deadline = time.monotonic() + LIMIT
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([child.stdout], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                break
            piece = os.read(child.stdout.fileno(), 4096)
            if not piece:
                break
            output.extend(piece)
            require(len(output) <= 65536, "NATIVE_OUTPUT_LIMIT")
            if b"sing-box started (" in output:
                started = True
                status = process_status(child.pid)
                validate_identity(status, os.getuid())
                require(status["NoNewPrivs"] == "1", "NATIVE_NO_NEW_PRIVS_MISSING")
                if offline:
                    require(status["Seccomp"] == "2", "NATIVE_FILTER_STATUS")
                child.send_signal(signal.SIGTERM)
                break
        try:
            tail, _ = child.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            tail, _ = child.communicate(timeout=3)
            raise Rejected("NATIVE_STOP_DEADLINE")
        output.extend(tail)
        require(len(output) <= 65536, "NATIVE_OUTPUT_LIMIT")
        return {"native_ready": started, "exit_code": child.returncode,
                "clean_exit": child.returncode == 0,
                "kernel_filter_on_native_ready_process": offline and status is not None,
                "four_UIDs_and_Eff_Prm_Inh_Amb_verified_on_ready": started and status is not None,
                "initial_ruleset_failure": b"initial rule-set" in output,
                "policy_denial_observed": b"operation not permitted" in output,
                "raw_native_log_exported": False}
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=3)
        if child.stdout is not None:
            child.stdout.close()


def fixture(binary, binary_sha, assets, spec):
    unprivileged()
    no_new_privs()  # Child-local restriction; never grants host permissions.
    require(binary.name == "sing-box", "BINARY_ROLE")
    require(all(parent.stat().st_uid == 0 and not stat.S_IMODE(parent.stat().st_mode) & 0o022
                for parent in binary.parents), "BINARY_PARENT_UNTRUSTED")
    raw_binary = public_file(binary, binary_sha, 128 * 1024 * 1024, 0)
    require(raw_binary.startswith(b"\x7fELF"), "BINARY_ELF_REQUIRED")
    binary_identity = binary.stat()
    del raw_binary
    require(assets.resolve() == assets and assets.stat().st_uid == os.getuid()
            and stat.S_IMODE(assets.stat().st_mode) == 0o700, "ASSET_DIRECTORY")
    require(set(spec) == {"domain", "ip"} and all(set(v) == {"sha256", "bytes"}
            for v in spec.values()), "ASSET_SPEC")
    payload = {key: public_file(assets / (key + ".srs"), spec[key]["sha256"],
                               131072, os.getuid()) for key in ("domain", "ip")}
    require(all(len(payload[key]) == spec[key]["bytes"] for key in payload), "ASSET_SIZE")
    root = Path(tempfile.mkdtemp(prefix="mlpa-native-rule-cache-", dir=assets.parent))
    identity = root.stat()
    served = {}
    listener = None
    thread = None
    try:
        env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "HOME": str(root),
               "TMPDIR": str(root), "XDG_CACHE_HOME": str(root), "XDG_CONFIG_HOME": str(root)}
        version = subprocess.run([str(binary), "version"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 env=env, timeout=3, check=True).stdout
        require(version.startswith(b"sing-box version 1.13.14\n"), "BINARY_VERSION_REQUIRED")
        tested = subprocess.run([sys.executable, "-I", "-S", "-B", __file__, "--selftest"],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, env=env, timeout=5, check=True)
        isolation = json.loads(tested.stdout)
        require(isolation.get("kernel_filter_verified") is True, "ISOLATION_SELFTEST")

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                key = {"/domain.srs": "domain", "/ip.srs": "ip"}.get(self.path)
                if key is None or served.get(key):
                    self.send_error(404)
                    return
                served[key] = len(payload[key])
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload[key])))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(payload[key])
            def log_message(self, *_):
                pass

        class Server(http.server.HTTPServer):
            def get_request(self):
                connection, address = super().get_request()
                connection.settimeout(2)
                return connection, address

        listener = Server(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=listener.serve_forever, kwargs={"poll_interval": 0.05})
        thread.start()
        cache = root / "public-cache.db"
        producer_cfg = root / "producer.json"
        producer_cfg.write_text(json.dumps(config(cache, {key: f"http://127.0.0.1:{listener.server_port}/{key}.srs" for key in URLS})))
        producer_cfg.chmod(0o600)
        producer = native_phase(binary, producer_cfg, env, False)
        listener.shutdown()
        listener.server_close()
        thread.join(timeout=2)
        require(not thread.is_alive(), "FIXTURE_HTTP_NOT_CLOSED")
        listener = thread = None
        require(producer["native_ready"] and producer["clean_exit"] and
                served == {key: len(payload[key]) for key in payload}, "PRODUCER_FAILED")
        item = cache.lstat()
        require(cache.resolve() == cache and stat.S_ISREG(item.st_mode) and
                item.st_uid == os.getuid() and item.st_nlink == 1, "NEW_CACHE_METADATA")
        seed = {"bytes": item.st_size, "sha256": sha(cache.read_bytes())}
        consumer_cfg = root / "consumer.json"
        consumer_cfg.write_text(json.dumps(config(cache, URLS)))
        consumer_cfg.chmod(0o600)
        consumer = native_phase(binary, consumer_cfg, env, True)
        require(consumer["native_ready"] and consumer["clean_exit"], "OFFLINE_CONSUMER_FAILED")
        empty = root / "independent-empty.db"
        require(not os.path.lexists(empty), "NEGATIVE_CACHE_NOT_EMPTY")
        negative_cfg = root / "negative.json"
        negative_cfg.write_text(json.dumps(config(empty, URLS)))
        negative_cfg.chmod(0o600)
        negative = native_phase(binary, negative_cfg, env, True)
        require(not negative["native_ready"] and negative["exit_code"] != 0 and
                negative["initial_ruleset_failure"] and negative["policy_denial_observed"],
                "EMPTY_CACHE_NEGATIVE_NOT_DISTINGUISHING")
        after = binary.stat()
        keys = ("st_dev", "st_ino", "st_uid", "st_gid", "st_mode", "st_nlink",
                "st_size", "st_mtime_ns", "st_ctime_ns")
        require(binary.resolve() == binary and all(getattr(after, key) == getattr(binary_identity, key)
                for key in keys), "BINARY_CHANGED_DURING_FIXTURE")
        return {"public_fixture_only": True, "binary_version": "1.13.14", "binary_sha256": binary_sha,
                "isolation": isolation, "producer": producer, "seed_after_clean_close": seed,
                "consumer": consumer, "empty_cache_negative": negative,
                "loopback_public_payload_bytes": sum(served.values()),
                "Origin_snapshot_is_not_new_upstream_fetch": True,
                "real_profile_registration_cache_or_service_accessed": False,
                "live_network_or_Owner_adoption_accepted": False}
    finally:
        if listener is not None:
            listener.shutdown()
            listener.server_close()
        if thread is not None:
            thread.join(timeout=2)
            require(not thread.is_alive(), "FIXTURE_HTTP_NOT_CLOSED")
        # This exact task-created directory identity is checked before recursive removal.
        require(root.resolve() == root and root.parent == assets.parent and
                root.name.startswith("mlpa-native-rule-cache-") and
                root.stat().st_uid == os.getuid() and
                (root.stat().st_dev, root.stat().st_ino) == (identity.st_dev, identity.st_ino),
                "FIXTURE_CLEANUP_TARGET_CHANGED")
        shutil.rmtree(root)


class Parser(argparse.ArgumentParser):
    def error(self, _):
        raise Rejected("ARGUMENTS")


def main():
    os.umask(0o077)
    try:
        if sys.argv[1:] == ["--selftest"]:
            result = selftest()
        else:
            parser = Parser()
            parser.add_argument("--binary", type=Path, required=True)
            parser.add_argument("--binary-sha256", required=True)
            parser.add_argument("--assets", type=Path, required=True)
            parser.add_argument("--spec", type=Path, required=True)
            args = parser.parse_args()
            unprivileged()
            require(args.assets.resolve() == args.assets and args.assets.stat().st_uid == os.getuid()
                    and stat.S_IMODE(args.assets.stat().st_mode) == 0o700, "ASSET_DIRECTORY")
            require(args.spec.resolve() == args.spec and args.spec.parent == args.assets
                    and args.spec.name == "spec.json", "SPEC_LOCATION")
            item = args.spec.lstat()
            require(stat.S_ISREG(item.st_mode) and item.st_uid == os.getuid() and item.st_nlink == 1
                    and stat.S_IMODE(item.st_mode) == 0o600 and item.st_size <= 2048, "SPEC_METADATA")
            fd = os.open(args.spec, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(fd, "rb") as stream:
                require(os.fstat(stream.fileno()) == item, "SPEC_CHANGED")
                spec_bytes = stream.read(2049)
            require(len(spec_bytes) == item.st_size, "SPEC_CHANGED")
            result = fixture(args.binary, args.binary_sha256, args.assets, json.loads(spec_bytes))
        print(json.dumps(result, sort_keys=True))
    except Exception as exc:
        code = str(exc) if isinstance(exc, Rejected) else "FIXTURE_REJECTED"
        print(json.dumps({"public_fixture_only": True, "error": code}), flush=True)
        return 78
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
