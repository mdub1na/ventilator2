#!/usr/bin/env python3
"""Non-root timer/record fixtures and owner-boundary failure checks; never invokes sudo."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from unittest.mock import patch

root = Path(__file__).absolute().parent.parent
spec = importlib.util.spec_from_file_location("registration_snapshot", root / "scripts/helper-registration-diagnostics.py")
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)
assert os.geteuid() != 0

# POSIX alarm must survive exec and terminate the command, not merely its parent wrapper.
started = time.monotonic()
result = subprocess.run(["/usr/bin/perl", "-e", 'alarm 1; exec "/bin/sleep", "15"; die "exec failed\\n";'])
assert result.returncode == -signal.SIGALRM and time.monotonic() - started < 3
print("Real non-root exec timer: sleeping utility terminated by SIGALRM; no sudo.")

records = snapshot.scoped_btm(''' Records for UID -2 : TEST
 #1:
 Identifier: 2.dev.ventilator.macos
 URL: /Applications/Ventilator.app
 Disposition: [disabled, disallowed] (pending authorization)
 Embedded Item Identifiers:
    #1: 16.dev.ventilator.helper
 #2:
 Name: Ventilator lookalike
 Identifier: 2.other.application
 URL: /Applications/Unrelated.app
 #3:
 Identifier: 16.dev.ventilator.helper
 Parent Identifier: 2.dev.ventilator.macos
 Records for UID 0 : TEST
 #1:
 Identifier: 2.dev.ventilator.macos
 Disposition: [enabled, allowed]
''')
assert len(records) == 3 and [r["uid"] for r in records] == [-2, -2, 0]
assert "Unrelated" not in json.dumps(records) and "lookalike" not in json.dumps(records)
assert "pending authorization" in records[0]["fields"]["Disposition"]
assert snapshot.scoped_btm("unrecognized output") == []
print("Scoped BTM fixture: preserves UID/parent disposition, rejects unrelated/lookalike records and embedded numbering.")

for uid, tty in [(0, True), (501, False)]:
    with patch.object(snapshot.os, "geteuid", return_value=uid), patch.object(snapshot.sys.stdin, "isatty", return_value=tty), \
            patch.object(snapshot.sys.stdout, "isatty", return_value=tty), patch.object(snapshot, "check") as checking, \
            patch.object(snapshot.subprocess, "run") as external:
        try:
            snapshot.collect(Path("/unused"))
            raise AssertionError("Owner boundary bypassed")
        except RuntimeError:
            pass
        checking.assert_not_called()
        external.assert_not_called()
print("Root and no-TTY collection refused before file inspection, markers or privileged commands.")

with tempfile.TemporaryDirectory(prefix="ventilator-registration-model-", dir=root / ".build") as directory:
    work = Path(directory)
    package = work / "helper-registration-diagnostics"
    owner = work / "owner-session"
    installed = work / "installed.app"
    package.mkdir(); owner.mkdir()
    (package / "snapshot.py").write_text("model script")
    (package / "PLAN.md").write_text("Model read-only plan; zero hardware writes.")
    (owner / "sealed.json").write_text("model immutable owner file")
    fingerprints = {}
    for key, name in snapshot.INSTALLED_FILES.items():
        path = installed / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(key)
        fingerprints[key] = snapshot.digest(path)
    manifest = {"scriptSHA256": snapshot.digest(package / "snapshot.py"),
                "planSHA256": snapshot.digest(package / "PLAN.md"), "installedFingerprint": fingerprints,
                "ownerFilesSHA256": {"sealed.json": snapshot.digest(owner / "sealed.json")},
                "commands": snapshot.COMMANDS, "hardwareWritesExecuted": 0}
    snapshot.save(package / "manifest.json", manifest)
    original_check = snapshot.check

    for changed in [package / "snapshot.py", owner / "sealed.json", installed / snapshot.INSTALLED_FILES["helperSHA256"]]:
        before = changed.read_bytes()
        changed.write_bytes(before + b" changed")
        with patch.object(snapshot, "owner_terminal"), \
                patch.object(snapshot, "check", side_effect=lambda p: original_check(p, installed)), \
                patch.object(snapshot.subprocess, "run") as external:
            try:
                snapshot.collect(package)
                raise AssertionError("Changed pin admitted")
            except RuntimeError:
                pass
            external.assert_not_called()
            assert not (package / "started.json").exists()
        changed.write_bytes(before)
    print("Changed diagnostic script, owner seal and installed helper refused before sudo/attempt marker.")

    unchanged_owner = (owner / "sealed.json").read_bytes()
    responses = [subprocess.CompletedProcess([], 113, ""), subprocess.CompletedProcess([], 142, "partial BTM")]
    with patch.object(snapshot, "owner_terminal"), \
            patch.object(snapshot, "check", side_effect=lambda p: original_check(p, installed)), \
            patch.object(snapshot, "runtime_metadata", return_value={"exists": False, "lstatErrno": 2}), \
            patch.object(snapshot.subprocess, "run", side_effect=responses) as external:
        snapshot.collect(package)
        assert [call.args[0] for call in external.call_args_list] == list(snapshot.COMMANDS.values())
        report = json.loads((package / "result.json").read_text())
        assert report["stoppedAt"] == "btm" and report["steps"]["btm"]["alarmExpired"]
        assert report["steps"]["btm"]["complete"] is False and report["hardwareWritesExecuted"] == 0
        assert (owner / "sealed.json").read_bytes() == unchanged_owner
        external.reset_mock()
        try:
            snapshot.collect(package)
            raise AssertionError("Collection replayed")
        except FileExistsError:
            pass
        external.assert_not_called()
    print("Missing job and timed-out BTM retained as failures; no readiness claim, owner file unchanged and replay blocked.")

with tempfile.TemporaryDirectory(prefix="ventilator-registration-denied-", dir=root / ".build") as directory:
    package = Path(directory)
    (package / "PLAN.md").write_text("Model authentication refusal.")
    with patch.object(snapshot, "owner_terminal"), patch.object(snapshot, "check", return_value=manifest), \
            patch.object(snapshot, "runtime_metadata", return_value={"exists": False}), \
            patch.object(snapshot.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "")) as external:
        snapshot.collect(package)
        assert external.call_count == 1
        report = json.loads((package / "result.json").read_text())
        assert report["stoppedAt"] == "launchd" and "btm" not in report["steps"]
    print("Sudo refusal stops before BTM; partial result retained without a second administrative command.")
for metadata in [{"exists": True}, {"exists": None, "lstatErrno": 13}]:
    with patch.object(snapshot, "runtime_metadata", return_value=metadata), patch.object(snapshot.subprocess, "run") as external:
        try:
            snapshot.unstarted_job_absent()
            raise AssertionError("Existing/unknown runtime admitted for cycle")
        except RuntimeError:
            pass
        external.assert_not_called()
with patch.object(snapshot, "runtime_metadata", return_value={"lstatErrno": 2}), \
        patch.object(snapshot.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "job loaded")):
    try:
        snapshot.unstarted_job_absent()
        raise AssertionError("Loaded job admitted for cycle")
    except RuntimeError:
        pass
print("System cycle refuses runtime presence/unreadability and loaded job before owner UI action.")

# Admission must bind the original owner and the previous administrative evidence before UI or sudo.
with tempfile.TemporaryDirectory(prefix="ventilator-system-proof-model-", dir=root / ".build") as directory:
    work = Path(directory)
    previous = work / "helper-registration-diagnostics"
    package = work / "helper-registration-approval"
    owner = work / "owner-session"
    previous.mkdir(); package.mkdir(); owner.mkdir()
    (previous / "result.json").write_text("model previous evidence")
    (owner / "sealed.json").write_text("model owner seal")
    (package / "snapshot.py").write_text("model script")
    (package / "PLAN.md").write_text("model one system cycle")
    cycle_manifest = dict(manifest, purpose="oneSystemApprovalCycle",
                          scriptSHA256=snapshot.digest(package / "snapshot.py"),
                          planSHA256=snapshot.digest(package / "PLAN.md"),
                          ownerFilesSHA256={"sealed.json": snapshot.digest(owner / "sealed.json")},
                          approvalPrerequisite={"ownerUID": os.getuid(),
                                                "sourceFilesSHA256": {"result.json": snapshot.digest(previous / "result.json")}})
    snapshot.save(package / "manifest.json", cycle_manifest)
    with patch.object(snapshot, "digest", side_effect=lambda p: fingerprints[next(k for k, n in snapshot.INSTALLED_FILES.items()
                      if str(p).endswith(n))] if str(p).startswith("/Applications/") else hashlib.sha256(p.read_bytes()).hexdigest()):
        snapshot.check(package)
        for substitution in ("owner", "evidence"):
            (previous / "result.json").write_text("changed" if substitution == "evidence" else "model previous evidence")
            with patch.object(snapshot.os, "getuid", return_value=os.getuid() + (1 if substitution == "owner" else 0)), \
                    patch.object(snapshot, "owner_terminal"), patch("builtins.input") as owner_input, \
                    patch.object(snapshot.subprocess, "run") as external:
                try:
                    snapshot.collect(package)
                    raise AssertionError("Changed owner/evidence admitted")
                except RuntimeError:
                    pass
                owner_input.assert_not_called(); external.assert_not_called()
                assert not (package / "started.json").exists()
print("Changed owner UID or previous administrative evidence refused before UI prompt, marker or sudo.")

for answer in ("cancel", "DONE"):
    with tempfile.TemporaryDirectory(prefix="ventilator-system-cycle-model-", dir=root / ".build") as directory:
        package = Path(directory)
        (package / "PLAN.md").write_text("Model one system cycle; no hardware approval.")
        cycle_manifest = dict(manifest, purpose="oneSystemApprovalCycle")
        with patch.object(snapshot, "owner_terminal"), patch.object(snapshot, "check", return_value=cycle_manifest), \
                patch.object(snapshot, "unstarted_job_absent"), \
                patch.object(snapshot, "runtime_metadata", return_value={"lstatErrno": 2}), \
                patch("builtins.input", return_value=answer) as owner_input, \
                patch.object(snapshot.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "")) as external:
            if answer == "cancel":
                try:
                    snapshot.collect(package)
                    raise AssertionError("Canceled UI cycle proceeded")
                except RuntimeError:
                    pass
                external.assert_not_called()
            else:
                snapshot.collect(package)
                assert external.call_count == 2 and (package / "owner-action.json").exists()
                report = json.loads((package / "result.json").read_text())
                assert "ownerActionReported" in report and report["hardwareWritesExecuted"] == 0
                assert [c.args[0] for c in external.call_args_list] == list(snapshot.COMMANDS.values())
            owner_input.reset_mock(); external.reset_mock()
            try:
                snapshot.collect(package)
                raise AssertionError("Owner UI cycle replayed")
            except FileExistsError:
                pass
            owner_input.assert_not_called(); external.assert_not_called()
print("Cancel stops before sudo; DONE performs two fixed reads only; marker blocks repeated UI prompt and sudo.")

# Updated installed copy: notification inspection is not a new registration or UI toggle cycle.
for mode in ["none", "allow", "cancel", "sudo-denied", "btm-timeout", "bad-peer", "verify-timeout", "runtime-appeared", "source-changed-after-input"]:
    with tempfile.TemporaryDirectory(prefix="ventilator-readonly-consent-model-", dir=root / ".build") as directory:
        package = Path(directory)
        (package / "PLAN.md").write_text("Model notification inspection; zero SMC writes.")
        manifest = {"purpose": "readOnlyApprovalInspection", "scriptSHA256": "a" * 64, "planSHA256": "b" * 64,
                    "installedFingerprint": fingerprints}
        calls = []
        def command(command, **kwargs):
            calls.append(command)
            if len(calls) == 1:
                return subprocess.CompletedProcess(command, 1 if mode == "sudo-denied" else 113 if mode == "none" else 0, "model system job")
            if len(calls) == 2:
                return subprocess.CompletedProcess(command, 142 if mode == "btm-timeout" else 0, "Records for UID -2 : TEST\n")
            assert command == ["/Applications/Ventilator.app/Contents/MacOS/Ventilator", "--verify-installed-helper"]
            if mode == "verify-timeout": raise subprocess.TimeoutExpired(command, 10)
            reply = {"trustedBundle": True, "rootOwned": True, "installedLocation": True,
                     "hardwareControlAvailable": False, "helperVerified": mode != "bad-peer",
                     "fingerprint": fingerprints, "registration": "enabled"}
            return subprocess.CompletedProcess(command, 78 if mode == "bad-peer" else 0, json.dumps(reply), "")
        checks = 0
        def checking(_):
            global checks
            checks += 1
            if mode == "source-changed-after-input" and checks == 2: raise RuntimeError("Model source changed during owner inspection")
            return manifest
        absent = {"exists": False, "lstatErrno": 2}
        after = {"exists": True} if mode == "runtime-appeared" else absent
        metadata = [absent, absent, after, after]
        with patch.object(snapshot, "owner_terminal"), patch.object(snapshot, "check", side_effect=checking), \
                patch.object(snapshot, "runtime_metadata", side_effect=metadata), \
                patch("builtins.input", return_value="cancel" if mode == "cancel" else "NONE" if mode == "none" else "ALLOW") as owner_input, \
                patch.object(snapshot.subprocess, "run", side_effect=command):
            if mode in ["cancel", "source-changed-after-input"]:
                try:
                    snapshot.collect(package)
                    raise AssertionError("Cancelled/changed inspection admitted")
                except RuntimeError: pass
                assert not calls
            else:
                snapshot.collect(package)
                report = json.loads((package / "result.json").read_text())
                assert report["helperVerified"] == (mode == "allow")
                assert len(calls) == (1 if mode == "sudo-denied" else 3 if mode in ["allow", "bad-peer", "verify-timeout"] else 2)
                assert report["hardwareWritesExecuted"] == 0
                if mode == "none": assert report["outcome"] == "systemApprovalPending"
                if mode == "runtime-appeared": assert report["outcome"] == "runtimeStatePresent"
                if mode == "bad-peer": assert report["steps"]["verification"]["reply"]["helperVerified"] is False
                if mode == "verify-timeout": assert report["steps"]["verification"]["timedOut"]
            before = list(calls)
            owner_input.reset_mock()
            # Runtime and binding reads may repeat; owner prompt, sudo and XPC may not.
            with patch.object(snapshot, "runtime_metadata", return_value=absent), patch.object(snapshot, "check", return_value=manifest):
                try:
                    snapshot.collect(package)
                    raise AssertionError("Read-only inspection replayed")
                except FileExistsError: pass
            owner_input.assert_not_called(); assert before == calls
print("Read-only consent inspection: nine branches; ALLOW alone never proves consent, NONE still saves snapshot, one conditional peer verify; cancellation, source race, failed/partial reads, runtime and replay stop dependent actions.")

with tempfile.TemporaryDirectory(prefix="ventilator-readonly-consent-bindings-", dir=root / ".build") as directory:
    import shutil
    base = Path(directory)
    source = base / ".build" / snapshot.READ_ONLY_SOURCE
    installed, backup = base / "installed.app", base / "backup"
    source.mkdir(parents=True); (base / "docs").mkdir()
    shutil.copyfile(root / "docs/helper-read-only-approval.md", base / "docs/helper-read-only-approval.md")
    for key, name in snapshot.INSTALLED_FILES.items():
        for bundle in [source / "Ventilator.app", installed, backup]:
            path = bundle / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(key)
    hashes = {key: snapshot.digest(installed / name) for key, name in snapshot.INSTALLED_FILES.items()}
    (source / "PLAN.md").write_text("Model stopped plan"); (source / "session.py").write_text("Model stopped script")
    source_manifest = {"readOnlyUpdate": True, "readOnlyMachine": snapshot.READ_ONLY_MACHINE, "installedReplacement": hashes,
                       "certificateSHA1": "model-cert", "teamIdentifier": "model-team",
                       "packageFiles": {n: snapshot.digest(source / n) for n in ["PLAN.md", "session.py"]}}
    snapshot.save(source / "manifest.json", source_manifest)
    snapshot.save(source / "sealed.json", {"fingerprint": hashes, "positiveRevocation": True,
        "certificateSHA1": "model-cert", "teamIdentifier": "model-team"})
    snapshot.save(source / "replacement-completed.json", {"fingerprint": hashes, "previous": hashes, "hardwareWritesExecuted": 0})
    snapshot.save(source / "registration-completed.json", {"fingerprint": hashes, "registration": "requiresApproval",
        "hardwareControlAvailable": False, "trustedBundle": True, "rootOwned": True, "installedLocation": True})
    for n in ["qualification-started.json", "update-started.json", "removal-started.json", "removal-completed.json", "replacement-started.json", "registration-started.json"]:
        snapshot.save(source / n, {"model": True})
    with patch.object(snapshot, "READ_ONLY_BACKUP", backup), patch.object(snapshot, "machine", return_value=snapshot.READ_ONLY_MACHINE), \
            patch.object(snapshot, "runtime_metadata", return_value={"lstatErrno": 2}):
        before = snapshot.tree_files(source)
        snapshot.prepare_read_only(base, installed=installed)
        package = base / ".build" / snapshot.READ_ONLY_SNAPSHOT
        prepared = snapshot.check(package, installed=installed)
        assert prepared["ownerFilesSHA256"] == before and snapshot.tree_files(source) == before
        assert prepared["backupFilesSHA256"] == snapshot.tree_files(backup)
        for path in [source / "PLAN.md", installed / snapshot.INSTALLED_FILES["helperSHA256"], backup / snapshot.INSTALLED_FILES["applicationSHA256"]]:
            original = path.read_bytes(); path.write_bytes(original + b" changed")
            try:
                snapshot.check(package, installed=installed)
                raise AssertionError("Changed bound file admitted")
            except RuntimeError: pass
            path.write_bytes(original)
        for substitution in ["owner", "machine", "advanced-source"]:
            with patch.object(snapshot.os, "getuid", return_value=os.getuid() + (1 if substitution == "owner" else 0)), \
                    patch.object(snapshot, "machine", return_value={} if substitution == "machine" else snapshot.READ_ONLY_MACHINE):
                if substitution == "advanced-source": (source / "result.json").write_text("{}")
                try:
                    snapshot.check(package, installed=installed)
                    raise AssertionError("Changed diagnostic binding admitted")
                except RuntimeError: pass
                if substitution == "advanced-source": (source / "result.json").unlink()
        assert snapshot.tree_files(source) == before
print("Real read-only package preparation/check: stopped source and backup preserved; changed source/installed/backup, owner, machine and advanced source refused.")
print("Registration diagnostics dry-run passed; no registration, actual UI cycle, installed app execution, root commands or SMC.")
