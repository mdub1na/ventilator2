#!/usr/bin/env python3
"""Exercise the isolated owner workflow against files/fakes; never sign, register or use sudo."""
import importlib.util
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("probe", repo / "scripts/registration-probe-session.py")
probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)

def fixture(root):
    package = root / "session"; package.mkdir(mode=0o700)
    app = package / "payload.app"; app.mkdir()
    for name in ["Contents/Info.plist", "Contents/MacOS/RegistrationProbe", "Contents/MacOS/RegistrationProbeDaemon", "Contents/_CodeSignature/CodeResources", "Contents/Library/LaunchDaemons/" + probe.DAEMON_ID + ".plist"]:
        path = app / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text("model bytes")
    protected = root / "ventilator"; protected.mkdir(); (protected / "binary").write_text("preserve me")
    (package / "session.py").write_text("model script"); (package / "PLAN.md").write_text("model plan")
    probe.save(package / "manifest.json", {"purpose": "isolatedRegistrationProbe", "sessionPath": str(package), "ownerUID": probe.os.getuid(),
        "machine": probe.MACHINE, "certificate": probe.CERTIFICATE, "team": probe.TEAM, "installedPath": str(root / "probe.app"),
        "bundleFilesSHA256": probe.tree(app), "protectedFilesSHA256": {str(protected): probe.tree(protected)},
        "scriptSHA256": probe.digest(package / "session.py"), "planSHA256": probe.digest(package / "PLAN.md"), "hardwareWrites": []})
    return package, root / "probe.app", protected

for mode in ["verified", "pending", "certificate-failure", "job-collision", "sudo-denied", "alarm", "cancel", "unknown-status", "partial-install", "changed-protected", "target-present", "gui-running"]:
    with tempfile.TemporaryDirectory(prefix="ventilator-isolated-model-", dir=repo / ".build") as directory:
        package, installed, protected = fixture(Path(directory)); calls = []; job_calls = []
        answers = iter(["CANCEL" if mode == "cancel" else "NONE" if mode == "pending" else "ALLOW", "CLOSED"])
        if mode == "target-present": installed.mkdir()
        if mode == "changed-protected": (protected / "binary").write_text("changed")
        def execute(argv, timeout=30):
            argv = [str(x) for x in argv]; calls.append(argv)
            if argv[0] == "/usr/bin/codesign": return subprocess.CompletedProcess(argv, 0, "", "model signing")
            if argv[0] == "/usr/bin/open":
                probe.save(package / "registration-started.json", {"pid": 1})
                probe.save(package / "registration.json", {"registration": "requiresApproval", "diagnostic": "model error 1"})
                probe.save(package / "gui.json", {"pid": 1})
            if "--probe-status" in argv:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"registration": "unexpected" if mode == "unknown-status" else "requiresApproval" if mode == "pending" else "enabled"}), "")
            if "--probe-cleanup" in argv:
                probe.save(package / "cleanup-started.json", {"pid": 1})
                probe.save(package / "cleanup.json", {"registration": "notRegistered"})
                return subprocess.CompletedProcess(argv, 0, '{"registration":"notRegistered"}', "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        def inspect(executable, app, qualify=False):
            if qualify and mode == "certificate-failure": raise RuntimeError("model positive revocation failure")
            return {"fingerprint": probe.tree(app), "positiveRevocation": qualify, "team": probe.TEAM, "certificate": probe.CERTIFICATE}
        def privileged(argv, alarm=20):
            argv = [str(x) for x in argv]; calls.append(argv)
            if argv[0] == "/bin/launchctl":
                assert argv == ["/bin/launchctl", "print", "system/" + probe.DAEMON_ID] and alarm == 5
                job_calls.append(1)
                code = (1 if mode == "sudo-denied" else -14 if mode == "alarm" else 0 if mode == "job-collision" else 113) if len(job_calls) == 1 else (113 if mode == "pending" or (package / "cleanup-started.json").exists() else 0)
                return subprocess.CompletedProcess(argv, code, "model job", "")
            if argv[0] == "/bin/mkdir": installed.mkdir()
            if argv[0] == "/usr/bin/ditto":
                if mode == "partial-install": return subprocess.CompletedProcess(argv, 1, "", "model copy failure")
                shutil.copytree(package / "payload.app", installed, dirs_exist_ok=True)
            if argv[0] == "/bin/mv": shutil.move(str(installed), str(package / "retired.bundle"))
            return subprocess.CompletedProcess(argv, 0, "", "")
        def installed_check(p):
            probe.check(p)
            assert probe.tree(installed) == json.loads((p / "sealed.json").read_text())["fingerprint"]
        def alive(pid, signal):
            assert pid == 1 and signal == 0
            if mode != "gui-running": raise ProcessLookupError()
        with patch.object(probe, "INSTALLED", installed), patch.object(probe, "machine", return_value=probe.MACHINE), \
             patch.object(probe, "owner_terminal"), patch.object(probe, "execute", side_effect=execute), \
             patch.object(probe, "privileged", side_effect=privileged), patch.object(probe, "inspect", side_effect=inspect), \
             patch.object(probe, "installed_check", side_effect=installed_check), patch.object(probe.os, "kill", side_effect=alive), patch("builtins.input", side_effect=lambda _: next(answers)):
            if mode in ("verified", "pending"):
                probe.run(package)
                result = json.loads((package / "result.json").read_text())
                assert result["isolatedBootstrapConfirmed"] == (mode == "verified")
                assert result["ventilatorRootPeerVerified"] is False and result["hardwareWritesExecuted"] == 0
                assert not installed.exists() and (package / "cleanup-completed.json").exists()
            else:
                try: probe.run(package); raise AssertionError("Failure ignored")
                except (RuntimeError, FileNotFoundError): pass
                assert not (package / "cleanup-completed.json").exists()
                assert (package / "result.json").exists() == (mode == "gui-running")
                if mode in ("certificate-failure", "job-collision", "sudo-denied", "alarm", "changed-protected", "target-present"):
                    assert not any("--owner-probe-session" in x for x in calls)
                if mode in ("changed-protected", "target-present"): assert not calls and not (package / "run-started.json").exists()
                if mode == "partial-install": assert installed.exists() and not (package / "installation.json").exists()
                if mode == "cancel":
                    assert not any("--probe-cleanup" in x for x in calls)
                    probe.cleanup(package)
                    assert (package / "cleanup-completed.json").exists()
                if mode == "gui-running":
                    assert installed.exists() and not (package / "retired.bundle").exists()
                    before_cleanup = list(calls)
                    try: probe.cleanup(package); raise AssertionError("Cleanup retry admitted")
                    except RuntimeError: pass
                    assert calls == before_cleanup
            before = list(calls)
            try: probe.run(package); raise AssertionError("Replay admitted")
            except (FileExistsError, RuntimeError): pass
            assert calls == before
        assert (protected / "binary").read_text() == ("changed" if mode == "changed-protected" else "preserve me")
        print(f"Isolated workflow model: {mode} passed; no real keys, GUI, root or ServiceManagement.")

with tempfile.TemporaryDirectory(prefix="ventilator-isolated-binding-", dir=repo / ".build") as directory:
    package, installed, protected = fixture(Path(directory))
    with patch.object(probe, "INSTALLED", installed), patch.object(probe, "machine", return_value=probe.MACHINE):
        probe.check(package)
        for name in ["session.py", "PLAN.md", "payload.app/Contents/MacOS/RegistrationProbeDaemon"]:
            path = package / name; original = path.read_bytes(); path.write_bytes(original + b" changed")
            try: probe.check(package); raise AssertionError("Changed binding admitted")
            except RuntimeError: pass
            path.write_bytes(original)
        original = (package / "PLAN.md").read_bytes(); (package / "PLAN.md").unlink(); (package / "PLAN.md").symlink_to(protected / "binary")
        try: probe.check(package); raise AssertionError("Alias admitted")
        except RuntimeError: pass
print("Isolated owner workflow: 12 outcome paths, protected files/frozen binding/alias/replay/active-GUI archival gates passed. No actual signing, sudo, registration or hardware experiment.")
