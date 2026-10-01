#!/usr/bin/env python3
"""Non-root XPC and independent-process restoration. Only our own simulated children receive signals."""
import datetime
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
    raise SystemExit("Dry-run must run without root")
lines = [f"M2 simulation verification: {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
         f"Effective UID: {os.geteuid()}. No helper registration, sudo or SMC writes."]
loopback = subprocess.run([str(binary), "--loopback-check"], capture_output=True, text=True, timeout=20)
if loopback.returncode:
    raise SystemExit(loopback.stdout + loopback.stderr)
lines.append(loopback.stdout.strip())
protocol_check = subprocess.run([str(binary), "--experiment-protocol-check"], capture_output=True, text=True, check=True, timeout=5)
lines.append(protocol_check.stdout.strip())
gui_binary = binary.with_name("Ventilator")
gui_symbols = subprocess.run(["nm", "-g", str(gui_binary)], capture_output=True, text=True, check=True, timeout=5).stdout
helper_symbols = subprocess.run(["nm", "-g", str(binary)], capture_output=True, text=True, check=True, timeout=5).stdout
assert "_SMCExperimentWriteStep" not in gui_symbols and "_SMCExperimentOpen" not in gui_symbols
assert "_SMCExperimentWriteStep" in helper_symbols
lines.append("Built GUI contains no SMCExperiment open/write symbols; fixed-operation writer is linked only into the helper.")
power = subprocess.run([str(binary), "--power-callback-check"], capture_output=True, text=True, check=True, timeout=5)
lines.append(power.stdout.strip())
denied = subprocess.run([str(binary)], capture_output=True, text=True, timeout=5)
assert denied.returncode == 78, denied.stdout + denied.stderr
lines.append("Default daemon mode refused in the ad hoc/non-root test context (exit 78).")
with tempfile.TemporaryDirectory(prefix="control-dry-run-", dir=root / ".build") as folder:
    child = subprocess.Popen([str(binary), "--simulate-crash", folder], stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
    try:
        ready, _, _ = select.select([child.stdout], [], [], 5)
        if not ready:
            raise RuntimeError("Simulated child did not save its journal in time")
        started = json.loads(child.stdout.readline())
        assert started["control"]["phase"] == "waitingForFixed"
        assert started["control"]["simulationOnly"] and not started["hardwareControlAvailable"]
        assert (Path(folder) / "session.json").is_file()
        child.kill()  # Only the exact process we created; its transport is simulated.
        child.wait(timeout=5)
        assert child.returncode == -signal.SIGKILL
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=5)
    restarted = subprocess.run([str(binary), "--recover-simulation", folder], capture_output=True,
                               text=True, check=True, timeout=5)
    restored = json.loads(restarted.stdout)
    assert restored["control"]["phase"] == "autoCodeObserved"
    assert restored["control"]["reason"] == "processRestart"
    assert restored["control"]["sessionID"] == started["control"]["sessionID"]
    assert not (Path(folder) / "session.json").exists()
    lines.append("SIGKILL of simulated helper: pending file survived; new process requested simulated Auto only,")
    lines.append("observed three separated Auto-code samples and removed the marker. Temporary directory cleaned.")


def independent_worker_case(name, owner_signal, restore_failure=False, worker_signal=None):
    with tempfile.TemporaryDirectory(prefix="control-worker-", dir=root / ".build") as folder:
        mode = "--worker-parent-restore-failure" if restore_failure else "--worker-parent"
        parent = subprocess.Popen([str(binary), mode, folder], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        worker_pid = None
        try:
            ready, _, _ = select.select([parent.stdout], [], [], 5)
            if not ready:
                raise RuntimeError("Worker parent did not arm in time")
            started = json.loads(parent.stdout.readline())
            worker_pid = started["workerPID"]
            identifier = started["reply"]["control"]["sessionID"]
            assert started["reply"]["control"]["simulationOnly"]
            assert (Path(folder) / "session.json").is_file()
            if worker_signal:
                os.kill(worker_pid, worker_signal)  # PID came from the exact child we created.
            if owner_signal:
                os.kill(parent.pid, owner_signal)
            deadline = time.monotonic() + 12
            outcome_file = Path(folder) / "worker-result.json"
            while not outcome_file.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            assert outcome_file.exists(), f"{name}: worker did not persist a result"
            result = json.loads(outcome_file.read_text())
            control = result["reply"]["control"]
            assert control["sessionID"] == identifier
            assert control["simulationOnly"] and not result["reply"]["hardwareControlAvailable"]
            assert result["effects"] == ["fixed2500", "auto"]
            assert 0 <= result["elapsedSeconds"] < 12
            if restore_failure:
                assert control["phase"] == "recoveryRequired" and control["reason"] == "transportFailure"
                assert (Path(folder) / "session.json").is_file()
            else:
                expected = "systemShutdown" if worker_signal else "heartbeatLost" if owner_signal == signal.SIGSTOP else "helperExited"
                assert control["phase"] == "autoCodeObserved" and control["reason"] == expected
                assert not (Path(folder) / "session.json").exists()
            lines.append(f"{name}: {control['phase']}/{control['reason']}; effects fixed2500, auto exactly once; "
                         f"worker finished after {result['elapsedSeconds']:.2f}s; power registration={result['powerNotificationsRegistered']}.")
        finally:
            if parent.poll() is None:
                if owner_signal == signal.SIGSTOP:
                    parent.send_signal(signal.SIGCONT)
                parent.terminate()
                parent.wait(timeout=5)
            # The result is saved just before worker exit. Wait for its exclusive lock to be released
            # before removing the private directory; no generic process-name kill is used.
            if worker_pid:
                lock_file = Path(folder) / "worker.lock"
                import fcntl
                with lock_file.open("rb") as lock:
                    deadline = time.monotonic() + 10
                    while True:
                        try:
                            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                            break
                        except BlockingIOError:
                            if time.monotonic() >= deadline:
                                raise RuntimeError("Worker remained alive beyond its restoration deadline")
                            time.sleep(0.05)


independent_worker_case("SIGKILL of helper with live worker", signal.SIGKILL)
independent_worker_case("SIGSTOP of helper with live worker", signal.SIGSTOP)
independent_worker_case("SIGTERM of simulation worker", None, worker_signal=signal.SIGTERM)
independent_worker_case("Restore failure after helper SIGKILL", signal.SIGKILL, restore_failure=True)
lines += ["These checks do not prove physical fan changes or Auto restoration on hardware.",
          "SHA-256 of tested helper: " + hashlib.sha256(binary.read_bytes()).hexdigest()]
report = "\n".join(lines) + "\n"
(root / "docs/research/evidence/control-dry-run.txt").write_text(report)
print(report, end="")
