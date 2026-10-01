#!/usr/bin/env python3
"""Local TTY consent and broker SIGKILL recovery. Non-root file devices only."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import sys
import tempfile
import time
import uuid

root = Path(__file__).resolve().parents[1]
binary = root / ".build/Ventilator.app/Contents/MacOS/VentilatorHelper"
if os.geteuid() == 0:
    raise SystemExit("Local approval/restart dry-run must run without root")
candidate = json.loads(subprocess.check_output([str(binary), "--candidate-plan"], timeout=5))
lines = [f"Local approval/restart verification: {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
         f"UID={os.geteuid()}; TTY model approval, file-backed device only; no root, native open/write, installation or actual sleep."]


def record(message):
    lines.append(message)
    print(message, flush=True)


def read_state(folder):
    path = folder / "authority-simulation.json"
    return json.loads(path.read_text()) if path.exists() else {}


def wait_for(predicate, timeout=6):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.01)
    raise AssertionError("Timed out waiting for model state")


def make_review(folder, domain="simulation"):
    review = {"domain": domain, "candidate": candidate["plan"],
              "ownerInstructions": "Model session: exact ten candidate steps; Fixed 2500 RPM, lease 10 seconds. "
              "One Auto sequence, original 8-second deadline; stop on faults. No hardware actions. "
              "Hashes and all key/type/byte writes are printed below. Restart permits Auto only."}
    data = json.dumps(review, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    path = folder / "local-review-simulation.json"
    path.write_bytes(data); path.chmod(0o600)
    return hashlib.sha256(data).hexdigest()


def tty_approval(folder, response="approve", digest=None, mutate=False, hardware=False):
    review_sha = digest or make_review(folder)
    arguments = [str(binary), "--approve-local-hardware"] if hardware else [str(binary), "--approve-local-model", str(folder)]
    arguments += [str(uuid.uuid4()), candidate["planSHA256"], review_sha]
    # Replay must use the same owner, just as the authority-bound challenge does.
    if read_state(folder).get("challenge"):
        arguments[-3] = read_state(folder)["challenge"]["connectionOwner"]
    master, slave = pty.openpty()
    process = subprocess.Popen(arguments, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    output = b""; sent = False
    deadline = time.monotonic() + 5
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                output += data
                match = re.search(rb"(?:^|\n)(APPROVE [0-9A-F-]{36} [0-9a-f]{64} [0-9a-f]{64})\r?\n", output)
                if match and not sent:
                    assert b"Model session:" in output and b'"fixedWrites"' in output and b'"restoreWrites"' in output, output
                    if mutate:
                        path = folder / "local-review-simulation.json"
                        value = json.loads(path.read_text()); value["ownerInstructions"] += " Changed after display."
                        path.write_text(json.dumps(value))
                    os.write(master, match[1] + b"\n" if response == "approve" else b"\x04" if response == "eof" else b"no\n")
                    sent = True
            if process.poll() is not None and not ready:
                break
        process.wait(timeout=1)
        return process.returncode, output.decode(errors="replace")
    finally:
        if process.poll() is None:
            process.kill(); process.wait(timeout=2)
        os.close(master)


for name, response, digest, mutate in [
        ("Exact local confirmation", "approve", None, False),
        ("Declined confirmation", "no", None, False),
        ("EOF confirmation", "eof", None, False),
        ("Wrong review digest", "approve", "0" * 64, False),
        ("Review changed after display", "approve", None, True)]:
    with tempfile.TemporaryDirectory(prefix="local-consent-", dir=root / ".build") as directory:
        folder = Path(directory)
        make_review(folder)
        code, output = tty_approval(folder, response, digest, mutate)
        state = read_state(folder)
        assert state.get("ledger") is None and not (folder / "simulation-device.json").exists()
        if name == "Exact local confirmation":
            assert code == 0 and state["approval"]["challenge"]["ownerReviewSHA256"] == make_review(folder), output
            approval = state["approval"]
            replay, output = tty_approval(folder)
            assert replay == 78 and "approvalAlreadyIssued" in output and read_state(folder)["approval"] == approval
        else:
            assert code == 78 and state.get("approval") is None, output
        record(f"{name}: verified; no ledger or device effect." + (" Exact consent replay rejected." if name == "Exact local confirmation" else ""))

with tempfile.TemporaryDirectory(prefix="local-domain-", dir=root / ".build") as directory:
    folder = Path(directory)
    sha = make_review(folder, domain="hardware")
    code, output = tty_approval(folder, digest=sha)
    assert code == 78 and read_state(folder).get("approval") is None, output
    code, output = tty_approval(folder, digest=sha, hardware=True)
    assert code == 78 and "localTerminalRequired" in output, output
    denied = subprocess.run([str(binary), "--approve-local-model", str(folder), str(uuid.uuid4()), candidate["planSHA256"], sha],
                            capture_output=True, text=True, timeout=2)
    assert denied.returncode == 78 and "localTerminalRequired" in denied.stderr
    record("Hardware-domain review, non-root hardware issuer and non-TTY model issuer rejected before approval; no native device opened.")


def ready_line(process):
    readable, _, _ = select.select([process.stdout], [], [], 5)
    assert readable, "Missing broker readiness"
    line = process.stdout.readline()
    assert line, "Broker exited before readiness"
    return json.loads(line)


def restart(folder, ready, boot=None):
    result_path = folder / "recovery-result.json"
    if result_path.exists():
        result_path.unlink()
    process = subprocess.Popen([str(binary), "--approved-model-broker", str(folder)], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write(json.dumps({"sessionID": ready["scope"]["sessionID"], "fault": "normal", "restarting": True,
                                  "modelBootSession": boot or ready["scope"]["bootSession"]}) + "\n")
    process.stdin.flush()
    try:
        output, error = process.communicate(timeout=10)
        assert process.returncode == 0, error
        outcome = json.loads(result_path.read_text())
        new_ready = json.loads(output.splitlines()[0]) if output.strip() else None
        if new_ready:
            assert new_ready["writerPID"] == 0 and new_ready["scope"]["nonce"] != ready["scope"]["nonce"]
            assert new_ready["scope"]["sessionID"] == ready["scope"]["sessionID"]
        return outcome, new_ready
    finally:
        if process.poll() is None:
            process.kill(); process.wait(timeout=2)


def kill_owned(pid):
    # Only children in this test's exact live tree, obtained from its private readiness/event stream.
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


for name, fault in [("Broker SIGKILL in Fixed", "hold"), ("Device lock held by another process", "hold"),
                    ("Partially returned Auto", "delayedAutoZero"), ("Ambiguous Auto", "blockedRestore"),
                    ("Expired original Auto deadline", "blockedRestore"), ("Wrong boot session", "hold")]:
    with tempfile.TemporaryDirectory(prefix="broker-restart-", dir=root / ".build") as directory:
        folder = Path(directory)
        # Exercise the complete local issuer -> consumed receipt -> broker path, not an injected approval.
        code, output = tty_approval(folder)
        assert code == 0, output
        approval = read_state(folder)["approval"]
        parent = subprocess.Popen([str(binary), "--approved-model-parent", str(folder), fault],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ready = None; blocked_pid = None; guard_process = None
        try:
            ready = ready_line(parent)
            assert ready["scope"]["domain"] == "simulation"
            wait_for(lambda: json.loads((folder / "simulation-device.json").read_text())["effects"][:5] == list(range(5)))
            original_epoch = None
            if fault == "delayedAutoZero":
                wait_for(lambda: 5 in read_state(folder)["ledger"].get("successfulReturns", []))
                original_epoch = read_state(folder)["ledger"]["restoreStartedAt"]
            elif fault == "blockedRestore":
                os.kill(ready["brokerPID"], signal.SIGTERM)
                event = ready_line(parent)
                assert event["role"] == "restore" and event["scope"] == ready["scope"]
                blocked_pid = event["pid"]
                wait_for(lambda: 5 in json.loads((folder / "simulation-device.json").read_text())["effects"])
                original_epoch = read_state(folder)["ledger"]["restoreStartedAt"]
                assert 5 not in read_state(folder)["ledger"].get("successfulReturns", [])
            kill_owned(ready["brokerPID"])
            parent.wait(timeout=3)
            assert parent.returncode == 78 and read_state(folder)["approval"] == approval
            if name == "Device lock held by another process":
                # This independent model guard survives the broker's entire process tree. On this Mac,
                # even a SIGSTOP writer disappeared when its broker was killed; that cannot model a
                # surviving kernel operation. The guard supplies a live lifetime FD without native I/O.
                guard_process = subprocess.Popen([sys.executable, "-u", "-c",
                    "import fcntl,sys; f=open(sys.argv[1],'rb'); fcntl.flock(f,fcntl.LOCK_EX); "
                    "print('guard-ready',flush=True); sys.stdin.read()", str(folder / "device-execution-simulation.lock")],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                readable, _, _ = select.select([guard_process.stdout], [], [], 2)
                assert readable and guard_process.stdout.readline().strip() == "guard-ready"
            if fault == "blockedRestore":
                assert read_state(folder)["ledger"]["attempts"] == list(range(6))
                kill_owned(blocked_pid); blocked_pid = None
            if name == "Expired original Auto deadline":
                # Python monotonic and mach_continuous_time can have different epochs after system sleep.
                time.sleep(8.1)
            result, new_ready = restart(folder, ready, str(uuid.uuid4()) if name == "Wrong boot session" else None)
            ledger = read_state(folder)["ledger"]
            effects = json.loads((folder / "simulation-device.json").read_text())["effects"]
            assert read_state(folder)["approval"] == approval
            assert len(ledger["attempts"]) == len(set(ledger["attempts"])) and effects[:5] == list(range(5))
            if original_epoch is not None:
                assert ledger["restoreStartedAt"] == original_epoch
            if name in {"Broker SIGKILL in Fixed", "Partially returned Auto"}:
                assert result["phase"] == "autoCodesObserved" and not ledger["pendingRestoration"] and new_ready
                assert ledger["attempts"] == effects == list(range(10))
            elif name == "Ambiguous Auto":
                assert result["reason"] == "ambiguousAutoAttempt" and ledger["pendingRestoration"] and new_ready
                assert ledger["attempts"] == effects == list(range(10)) and 5 not in ledger["successfulReturns"]
            elif name == "Device lock held by another process":
                assert result["reason"] == "deviceStillActive" and ledger["fixedClosed"] and ledger["pendingRestoration"], (result, ledger)
                assert ledger.get("restoreStartedAt") is None and effects == ledger["attempts"] == list(range(5))
            else:
                assert result["reason"] == "restartRejected" and ledger["pendingRestoration"] and not new_ready
                assert ledger["attempts"] == effects == (list(range(6)) if fault == "blockedRestore" else list(range(5)))
            record(f"{name}: {result['phase']}/{result['reason']}; steps={ledger['attempts']}; "
                   f"pending={ledger['pendingRestoration']}; same receipt, no repeated Fixed/Auto, original deadline preserved.")
        finally:
            if guard_process:
                guard_process.communicate(timeout=2)
            if blocked_pid:
                kill_owned(blocked_pid)
            if ready:
                # Broker/ordinary children close on EOF. Kill only this exact broker if a test failed early.
                if parent.poll() is None:
                    kill_owned(ready["brokerPID"])
            if parent.poll() is None:
                parent.kill(); parent.wait(timeout=3)
            time.sleep(0.1)

lines += ["Six TTY/domain cases and six broker restart cases passed; hardware positive issuer/start and physical recovery remain unverified.",
          "No PID is persisted or used by production restart. A live device lock prevents Auto; ambiguous attempted Auto is never retried.",
          "SHA-256 of tested helper: " + hashlib.sha256(binary.read_bytes()).hexdigest()]
(root / "docs/research/evidence/local-approval-restart-dry-run.txt").write_text("\n".join(lines) + "\n")
