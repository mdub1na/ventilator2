#!/usr/bin/env python3
"""Exact approved model steps with a separate broker and disposable device children. Never runs as root."""
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary = root / ".build/Ventilator.app/Contents/MacOS/VentilatorHelper"
if os.geteuid() == 0:
    raise SystemExit("Recovery dry-run must run without root")
lines = [f"Independent recovery verification: {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
         "Non-root. File-backed model only. No native open/write, installation, sudo or actual sleep."]

with tempfile.TemporaryDirectory(prefix="hardware-child-denial-", dir=root / ".build") as denied_folder:
    denied = subprocess.run([str(binary), "--prepared-hardware-child", denied_folder], capture_output=True, text=True, timeout=2)
    assert denied.returncode == 78 and not list(Path(denied_folder).iterdir())
lines.append("Prepared hardware child rejects non-root before journal/device access; no approval or hardware witness issued.")


def wait_file(path, timeout=16):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return json.loads(path.read_text())
        time.sleep(0.03)
    raise RuntimeError(f"Missing {path.name}")


def run_case(name, mode="hold", target=None, sent_signal=None, expected="autoCodesObserved", reason=None):
    with tempfile.TemporaryDirectory(prefix="recovery-dry-run-", dir=root / ".build") as folder:
        folder = Path(folder)
        parent = subprocess.Popen([str(binary), "--approved-model-parent", str(folder), mode],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ready = None
        try:
            readable, _, _ = select.select([parent.stdout], [], [], 5)
            assert readable, f"{name}: no readiness"
            frame = parent.stdout.readline()
            assert frame, parent.stderr.read()
            ready = json.loads(frame)
            assert ready["scope"]["domain"] == "simulation"
            if target:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    state = json.loads((folder / "simulation-device.json").read_text())
                    if state["effects"] == list(range(5)):
                        break
                    time.sleep(0.02)
                else:
                    raise RuntimeError(f"{name}: fixed steps not observed")
                pid = parent.pid if target == "helper" else ready["writerPID"] if target == "writer" else ready["readerPID"] if target == "reader" else ready["brokerPID"]
                os.kill(pid, sent_signal)  # Every PID comes from the exact non-root child tree created above.
            result = wait_file(folder / "recovery-result.json")
            ledger = json.loads((folder / "authority-simulation.json").read_text())["ledger"]
            state = json.loads((folder / "simulation-device.json").read_text())
            assert result["simulationOnly"] and result["sessionID"] == ready["scope"]["sessionID"]
            assert result["phase"] == expected, result
            if reason:
                accepted = {"writerExited", "writerChannelFailure"} if reason == "writerExited" else {reason}
                assert result["reason"] in accepted, result
            assert 0 <= result["elapsedSeconds"] < 19, result
            assert ledger["fixedClosed"] and len(ledger["attempts"]) == len(set(ledger["attempts"]))
            events = result["events"]
            assert events.count("fixedProbeConfirmed") >= 1 and events.count("readerProbeConfirmed") >= 1
            assert events.count("restoreProbeConfirmed") >= 1
            assert events.index("fixedClosed") < events.index("writerStopRequested") < events.index("writerExited")
            assert events.index("writerExited") < events.index("restorationStarted") < events.index("autoStep5Requested")
            if expected == "autoCodesObserved":
                assert ledger["autoCodesObserved"] and not ledger["pendingRestoration"]
                assert state["modes"] == [3, 3] and state["targets"] == [0, 0] and state["testMode"] == 0
                assert events.index("restorerExited") < events.index("autoCodesObserved")
                fixed = [0] if mode == "blockedFixed" else list(range(5))
                assert state["effects"] == fixed + list(range(5, 10)), state
            else:
                assert ledger["pendingRestoration"] and not ledger["autoCodesObserved"]
                if mode == "restoreFailure":
                    assert result["failedSteps"] == [5, 7, 9]
                    assert ledger["attempts"] == [0, 1, 2, 3, 4, 5, 6, 8], ledger
                    assert state["effects"] == [0, 1, 2, 3, 4, 6, 8], state
                    assert state["modes"] == [1, 3]  # The other fan's Auto proceeds despite fan zero's error.
                elif mode == "blockedRestore":
                    assert ledger["attempts"] == list(range(6)) and state["effects"] == list(range(6))
                elif mode in {"blockedAutoReader", "earlyAutoReaderFailure"}:
                    assert ledger["attempts"] == list(range(10)) and state["effects"] == list(range(10))
                    assert state["modes"] == [3, 3] and state["testMode"] == 0
                    assert "autoReaderFailed" in events  # Device effects do not become independent evidence.
            if mode == "sleep":
                assert events.index("autoCodesObserved") < events.index("sleepAcknowledged")
            lines.append(f"{name}: {result['phase']}/{result['reason']}, {result['elapsedSeconds']:.2f}s; "
                         f"writer exit precedes Auto; attempted steps={ledger['attempts']}; pending={ledger['pendingRestoration']}.")
        finally:
            if parent.poll() is None:
                if target == "helper" and sent_signal == signal.SIGSTOP:
                    parent.send_signal(signal.SIGCONT)
                parent.terminate()
            try:
                parent.wait(timeout=5)
            except subprocess.TimeoutExpired:
                parent.kill(); parent.wait(timeout=5)
            if ready:
                # The lifetime lock proves the broker has released its files before temporary cleanup.
                lock_path = folder / "recovery-broker.lock"
                with lock_path.open("rb") as lock:
                    deadline = time.monotonic() + 19
                    while True:
                        try:
                            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                            break
                        except BlockingIOError:
                            if time.monotonic() >= deadline:
                                raise RuntimeError("Recovery broker exceeded its deadline")
                            time.sleep(0.02)


run_case("Explicit Auto", "normal", reason="explicitAuto")
run_case("SIGKILL helper", target="helper", sent_signal=signal.SIGKILL, reason="helperExited")
run_case("SIGSTOP helper", target="helper", sent_signal=signal.SIGSTOP, reason="heartbeatLost")
run_case("SIGKILL writer", target="writer", sent_signal=signal.SIGKILL, reason="writerExited")
run_case("SIGSTOP writer", target="writer", sent_signal=signal.SIGSTOP, reason="writerTimeout")
run_case("Writer SIGSTOP inside authority transaction", "stoppedAuthorityTransaction", reason="writerTimeout")
run_case("Blocked Fixed after durable effect", "blockedFixed", reason="writerTimeout")
run_case("Blocked Auto after durable effect", "blockedRestore", target="helper", sent_signal=signal.SIGKILL,
         expected="recoveryRequired", reason="restorerTimeout")
run_case("Fan zero Auto failure", "restoreFailure", target="helper", sent_signal=signal.SIGKILL,
         expected="recoveryRequired", reason="restoreStepFailure")
run_case("SIGTERM broker", target="broker", sent_signal=signal.SIGTERM, reason="systemShutdown")
run_case("Injected sleep with delayed acknowledgement", "sleep", reason="systemSleep")
run_case("Ten-second lease despite heartbeat", reason="leaseExpired")
run_case("SIGSTOP independent reader", target="reader", sent_signal=signal.SIGSTOP, reason="readerTimeout")
run_case("Blocked independent Fixed reader", "blockedReader", reason="readerTimeout")
run_case("Independent reader failure", "readerFailure", reason="readerFailure")
run_case("Blocked independent Auto reader", "blockedAutoReader", target="helper", sent_signal=signal.SIGKILL,
         expected="recoveryRequired", reason="restorationReaderFailure")
run_case("Early Auto reader failure preserves all Auto attempts", "earlyAutoReaderFailure", target="helper", sent_signal=signal.SIGKILL,
         expected="recoveryRequired", reason="restorationReaderFailure")
lines += ["Writer non-quiescence is also unit tested: no Auto starts and the pending ledger remains.",
          "Process termination is model proof only; it does not prove cancellation of a kernel SMC operation.",
          "Broker SIGKILL/restart is covered separately by local-approval-restart-dry-run.py; power loss and hardware recovery remain unverified.",
          "SHA-256 of tested helper: " + hashlib.sha256(binary.read_bytes()).hexdigest()]
report = "\n".join(lines) + "\n"
(root / "docs/research/evidence/recovery-dry-run.txt").write_text(report)
print(report, end="")
