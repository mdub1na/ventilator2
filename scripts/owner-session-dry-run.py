#!/usr/bin/env python3
"""Real offline package/import and negative owner commands; never signing, sudo or native writes."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime
import uuid
import importlib.util
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
helper = root / ".build/Ventilator.app/Contents/MacOS/VentilatorHelper"
app = helper.with_name("Ventilator")
assert os.geteuid() != 0
lines = [f"Owner session dry-run: {datetime.now().astimezone().isoformat(timespec='seconds')}",
         "Non-root offline files and anonymous model only; no private key, signing, sudo, installation or native writes."]

# Preserve the subprocess's actual error, rather than hiding it in CalledProcessError.
spec = importlib.util.spec_from_file_location("owner_session", root / "scripts/owner-session.py")
session = importlib.util.module_from_spec(spec); spec.loader.exec_module(session)
try:
    session.output(["/bin/sh", "-c", "printf 'qualification detail' >&2; exit 78"])
    raise AssertionError("Expected failure")
except RuntimeError as error:
    assert "qualification detail" in str(error) and "78" in str(error)
lines.append("Underlying qualification stderr is preserved in STOP diagnostics.")

with tempfile.TemporaryDirectory(prefix="ventilator-sign-stage-", dir=root / ".build") as tmp:
    directory = Path(tmp)
    manifest = {"signatureReady": False}
    fingerprint = {"applicationSHA256": "a" * 64, "helperSHA256": "b" * 64, "launchDaemonSHA256": "c" * 64}
    with patch.object(session, "SESSION", directory), patch.object(session, "owner_terminal"), \
            patch.object(session, "check", return_value=manifest), patch.object(session, "fingerprints", return_value=fingerprint), \
            patch.object(session.subprocess, "run") as external, patch.object(session, "qualify") as qualification:
        session.sign()
        assert (directory / "signature-ready.json").exists()
        assert len(external.call_args_list) == 4
        assert all(c.args[0][0] == "/usr/bin/codesign" for c in external.call_args_list)
        qualification.assert_not_called()
        state = session.package_status()
        assert state["signature"] == "complete" and state["certificateQualification"] == "notStarted"
        session.save("qualification-started.json", {"fingerprint": fingerprint})
        state = session.package_status()
        assert state["signature"] == "complete" and state["certificateQualification"] == "stopped"
        assert "do not sign or qualify again" in state["nextStep"]
        first_calls = len(external.call_args_list)
        try:
            session.sign()
            raise AssertionError("Completed signing repeated")
        except RuntimeError:
            pass
        assert len(external.call_args_list) == first_calls
lines.append("Mocked signing completed after exactly two codesign + two strict verify calls, without public qualification; subsequent qualification failure retained signature=complete and repeated sign invoked no external command.")

previous = {"applicationSHA256": "a" * 64, "helperSHA256": "b" * 64, "launchDaemonSHA256": "c" * 64}
inactive = {"fingerprint": previous, "trustedBundle": True, "rootOwned": True, "installedLocation": True,
            "registration": "notFound", "error": "serviceNotEnabled", "helperVerified": False, "hardwareControlAvailable": False}
session.admit_replacement(inactive, previous, previous, False)
session.admit_replacement({**inactive, "registration": "requiresApproval"}, previous, previous, False)
for key, value in [("registration", "enabled"), ("registration", "unknown"), ("trustedBundle", False),
                   ("rootOwned", False), ("installedLocation", False), ("helperVerified", True),
                   ("hardwareControlAvailable", True), ("error", "pendingRecovery"), ("fingerprint", {})]:
    try:
        session.admit_replacement({**inactive, key: value}, previous, previous, False)
        raise AssertionError(f"Replacement admitted {key}")
    except RuntimeError:
        pass
for actual, hardware_exists in [({}, False), (previous, True)]:
    try:
        session.admit_replacement(inactive, actual, previous, hardware_exists)
        raise AssertionError("Unsafe replacement admitted")
    except RuntimeError:
        pass
lines.append("Pinned replacement policy admits disabled requiresApproval only with an absent entire runtime root; rejects enabled/unknown service, changed hashes, invalid identity/ownership and any runtime state; pure inputs only.")

# Launchd output is diagnostic data: only the exact absent or matching inactive job is accepted.
job = '''system/dev.ventilator.helper = {
    state = spawn scheduled
    program identifier = Contents/MacOS/VentilatorHelper (mode: 2)
    parent bundle identifier = dev.ventilator.macos
    managed_by = com.apple.xpc.ServiceManagement
}'''
for code, stdout, stderr, expected in [
        (113, "", 'Could not find service "dev.ventilator.helper" in domain for system', False),
        (0, job, "", True),
        (0, job.replace("state = spawn scheduled", "state = running\n    pid = 42"), "", None),
        (0, job.replace("state = spawn scheduled", "state = running"), "", None),
        (0, job.replace("state = spawn scheduled", "state = unknown"), "", None),
        (0, job.replace("dev.ventilator.macos", "other.bundle"), "", None),
        (0, job.replace("dev.ventilator.macos", "dev.ventilator.macos.other"), "", None),
        (1, "", "Operation not permitted", None),
        (113, "", "unrelated error", None)]:
    with patch.object(session.subprocess, "run", return_value=subprocess.CompletedProcess([], code, stdout, stderr)):
        if expected is None:
            try:
                session.launchd_job_present()
                raise AssertionError("Uncertain or active launchd state admitted")
            except RuntimeError:
                pass
        else:
            assert session.launchd_job_present() is expected
lines.append("Launchd repair refused an active PID, foreign bundle and ambiguous errors; accepted only exact missing service or matching inactive job on mocked diagnostic data.")

# Execute the orchestration with fake external commands, including a change during staging.
for mode in ["inactive-absent", "disabled-job", "changed-after-staging", "job-reappeared"]:
    with tempfile.TemporaryDirectory(prefix="ventilator-replace-", dir=root / ".build") as tmp:
        directory = Path(tmp)
        new = {**previous, "applicationSHA256": "d" * 64}
        (directory / "sealed.json").write_text(json.dumps({"fingerprint": new}))
        staged = {"trustedBundle": True, "rootOwned": True, "fingerprint": new}
        state = {**inactive, "registration": "requiresApproval"} if mode == "disabled-job" else inactive
        second = {**state, "fingerprint": {}} if mode == "changed-after-staging" else state
        outputs = [json.dumps(state), json.dumps(staged), json.dumps(second)]
        if mode == "disabled-job":
            outputs.insert(1, json.dumps(state))
        jobs = [True, False, False] if mode == "disabled-job" else [False, False, mode == "job-reappeared"]
        with patch.object(session, "SESSION", directory), patch.object(session, "owner_terminal"), \
                patch.object(session, "check", return_value={"installedReplacement": previous}), \
                patch.object(session, "fingerprints", return_value=previous), \
                patch.object(session, "installed_check"), patch.object(session.HARDWARE_ROOT.__class__, "lstat", side_effect=FileNotFoundError), \
                patch.object(session.os.path, "lexists", return_value=False), \
                patch.object(session, "output", side_effect=outputs), \
                patch.object(session, "launchd_job_present", side_effect=jobs), \
                patch.object(session.subprocess, "run") as commands:
            if mode in ["changed-after-staging", "job-reappeared"]:
                try:
                    session.replace_installed()
                    raise AssertionError("Changed installation moved")
                except RuntimeError:
                    pass
                assert len(commands.call_args_list) == 3
                assert not (directory / "replacement-completed.json").exists()
            else:
                session.replace_installed()
                assert (directory / "replacement-completed.json").exists()
                operations = [c.args[0][1] for c in commands.call_args_list]
                expected = ["/usr/bin/ditto", "/usr/sbin/chown", "/bin/chmod", "/bin/mv", "/bin/mv"]
                if mode == "disabled-job":
                    expected.insert(0, "/bin/launchctl")
                    assert commands.call_args_list[0].args[0] == ["sudo", "/bin/launchctl", "bootout", "system/dev.ventilator.helper"]
                assert operations == expected
            assert (directory / "replacement-started.json").exists()
lines.append("Replacement orchestration preserved backup order and performed one exact bootout only for a disabled inactive job on mocked commands; changed installation or a reappearing job stopped both moves and retained the marker.")

# A failed read must be recorded while the remaining audit/status collection still runs.
with tempfile.TemporaryDirectory(prefix="ventilator-collect-", dir=root / ".build") as tmp:
    directory = Path(tmp)
    (directory / "sealed.json").write_text("{}")
    responses = [RuntimeError("snapshot exit 78: read refused"), "{}", "{}"]
    with patch.object(session, "SESSION", directory), patch.object(session, "owner_terminal"), \
            patch.object(session, "installed_check"), patch.object(session, "output", side_effect=responses):
        session.collect()
    report = json.loads((directory / "result.json").read_text())
    assert "read refused" in report["snapshot"]["error"] and report["status"] == {} and report["audit"] == {}
lines.append("Collector retained a failed read diagnostic and continued status/audit collection on mocked responses; no installed/native commands.")


def run(command, success=True):
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=8)
    assert result.returncode == (0 if success else 78), (command, result.returncode, result.stdout, result.stderr)
    return result


# Real package copying, with only the public certificate response mocked for success/error cases.
# The fixture is ad hoc: model successes cannot qualify its certificate for installation.
for mode in ["success", "native-rejection", "revocation-failed", "timeout", "wrong-certificate", "changed-bundle", "changed-plan"]:
    with tempfile.TemporaryDirectory(prefix="ventilator-sign-resume-", dir=root / ".build") as tmp:
        source = Path(tmp) / "source"
        resumed = Path(tmp) / "resumed"
        with patch.object(session, "SESSION", source):
            session.prepare()
            session.save("sign-started.json", {"certificateSHA1": session.CERTIFICATE, "hardwareWritesExecuted": 0})
        source_manifest = json.loads((source / "manifest.json").read_text())
        source_manifest["installedReplacement"] = previous
        (source / "manifest.json").write_text(json.dumps(source_manifest))
        source_state = {str(p.relative_to(source)): session.sha(p) for p in source.rglob("*") if p.is_file()}
        with patch.object(session, "SESSION", resumed), patch.object(session, "SIGNED_SESSION", source):
            session.prepare()
            manifest = session.check()
            assert manifest["signatureReady"] and manifest["installedReplacement"] == previous
            assert manifest["fingerprint"] == session.fingerprints(source / "Ventilator.app")
            with patch.object(session, "owner_terminal"), patch.object(session.subprocess, "run") as external:
                try:
                    session.sign()
                    raise AssertionError("Imported package signed again")
                except RuntimeError as error:
                    assert "already signed" in str(error)
                external.assert_not_called()
            proof = {"certificateSHA1": session.CERTIFICATE, "teamIdentifier": session.TEAM,
                     "positiveRevocation": True, "notarizationClaimed": False, "fingerprint": manifest["fingerprint"]}
            original_output = session.output
            calls = []

            def public_response(command, timeout=5):
                calls.append([str(x) for x in command])
                if "--qualify-owner-signature" not in command:
                    return original_output(command, timeout)
                assert timeout == 20
                if mode == "native-rejection":
                    return original_output(command, timeout)
                if mode == "revocation-failed":
                    raise RuntimeError("Unable to verify revocation")
                if mode == "timeout":
                    raise subprocess.TimeoutExpired(command, timeout)
                if mode == "wrong-certificate":
                    return json.dumps({**proof, "certificateSHA1": "0" * 40})
                if mode == "changed-bundle":
                    session.files(resumed / "Ventilator.app")["helperSHA256"].write_bytes(b"changed")
                return json.dumps(proof)

            if mode == "changed-plan":
                (resumed / "PLAN.md").write_text("changed")
            with patch.object(session, "output", side_effect=public_response):
                if mode == "success":
                    session.qualify()
                    session.check(sealed=True)
                    assert session.package_status()["signature"] == "complete"
                    assert session.package_status()["certificateQualification"] == "complete"
                    assert json.loads((resumed / "sealed.json").read_text()) == proof
                    review = json.loads((resumed / "review.json").read_text())
                    assert review["ownerInstructions"] == (root / "docs/owner-session.md").read_text()
                else:
                    try:
                        session.qualify()
                        raise AssertionError(f"Unsafe qualification sealed: {mode}")
                    except (RuntimeError, subprocess.SubprocessError):
                        pass
                    assert not (resumed / "sealed.json").exists()
                first_calls = len(calls)
                try:
                    session.qualify()
                    raise AssertionError("Qualification retried automatically")
                except RuntimeError:
                    pass
                assert len(calls) == first_calls
                assert all(c[1] in ["--qualify-owner-signature", "--candidate-plan"] for c in calls)
            assert source_state == {str(p.relative_to(source)): session.sha(p) for p in source.rglob("*") if p.is_file()}
lines.append("Signed-source import preserved every source file and previous installation pin, refused re-signing; mocked public trust success sealed the full review. Real ad hoc rejection, revocation failure, timeout, wrong leaf, changed bundle/plan produced no seal or retry; commands limited to certificate/candidate reads.")

# Reject a changed source plan and a source with a partial seal before creating a destination.
for mode in ["changed-plan", "partial-seal", "missing-marker"]:
    with tempfile.TemporaryDirectory(prefix="ventilator-source-refusal-", dir=root / ".build") as tmp:
        source = Path(tmp) / "source"; destination = Path(tmp) / "destination"
        with patch.object(session, "SESSION", source):
            session.prepare()
            if mode != "missing-marker":
                session.save("sign-started.json", {"certificateSHA1": session.CERTIFICATE, "hardwareWritesExecuted": 0})
        if mode == "changed-plan":
            (source / "PLAN.md").write_text("changed")
        elif mode == "partial-seal":
            (source / "sealed.json").write_text("{}")
        with patch.object(session, "SESSION", destination), patch.object(session, "SIGNED_SESSION", source):
            try:
                session.prepare()
                raise AssertionError("Unsafe source imported")
            except (RuntimeError, OSError):
                pass
            assert not destination.exists()
lines.append("Changed source instructions, partial seal and missing owner signing marker rejected before destination creation.")

package = root / f".build/owner-session-check-{uuid.uuid4()}"
try:
    run(["python3", root / "scripts/owner-session.py", "prepare", "--output", package])
    run(["python3", package / "session.py", "check"])
    manifest = json.loads((package / "manifest.json").read_text())
    assert not manifest["signed"] and manifest["hardwareWritesExecuted"] == 0
    for command in ["sign", "install", "replace-installed", "register", "ready", "run", "collect", "unregister"]:
        refusal = run(["python3", package / "session.py", command], success=False)
        assert "non-root Terminal" in refusal.stderr
    assert not (package / "sign-started.json").exists()
    assert "No completed signature" in run(["python3", package / "session.py", "qualify"], success=False).stderr
    assert not (package / "qualification-started.json").exists()
    original = (package / "PLAN.md").read_text()
    (package / "PLAN.md").write_text(original + "modified")
    assert "Package changed" in run(["python3", package / "session.py", "check"], success=False).stderr
    lines.append("Copied package fingerprints/check passed; changed plan rejected; eight owner actions rejected before mutation without Terminal.")
finally:
    if package.exists():
        shutil.rmtree(package)

plan = json.loads(run([helper, "--candidate-plan"]).stdout)["plan"]
review = {"domain": "simulation", "candidate": plan, "ownerInstructions": (root / "docs/owner-session.md").read_text()}
canonical = json.dumps(review, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
digest = hashlib.sha256(canonical).hexdigest()
assert len(canonical) <= 16384
with tempfile.TemporaryDirectory(prefix="ventilator-review-") as tmp:
    directory = Path(tmp).resolve()
    source = directory / "full-review.json"; source.write_bytes(canonical)
    journal = directory / "journal"
    run([helper, "--stage-local-model-review", journal, source, digest])
    saved = (journal / "local-review-simulation.json").read_bytes()
    assert hashlib.sha256(saved).hexdigest() == digest
    assert not (journal / "authority-simulation.json").exists()
    assert not (journal / "simulation-device.json").exists()
    run([helper, "--stage-local-model-review", journal, source, "0" * 64], success=False)
    alias = directory / "alias.json"; alias.symlink_to(source)
    run([helper, "--stage-local-model-review", journal, alias, digest], success=False)
    lines.append(f"Full {len(canonical)}-byte UTF-8 review imported through real model CLI; canonical digest matched Swift; no approval/ledger/device. Wrong digest and symlink refused.")

for command in [[app, "--run-owner-experiment", "0" * 64], [app, "--owner-experiment-status"],
                [app, "--qualify-owner-signature", root / ".build/Ventilator.app", "4895C06FF7407EAF5F350E78CF23D0B41AD466C9"],
                [helper, "--stage-local-hardware-review", "/no/review.json", "0" * 64], [helper, "--owner-hardware-audit"]]:
    run(command, success=False)
lines += ["Ad hoc owner start/status/certificate qualification and non-root hardware stage/audit refused before native authority.",
          "This offline suite does not sign or positively qualify Apple-issued code, install root service, run sudo stages or execute hardware experiment.",
          f"SHA-256 of tested helper: {hashlib.sha256(helper.read_bytes()).hexdigest()}",
          f"SHA-256 of tested application: {hashlib.sha256(app.read_bytes()).hexdigest()}"]
destination = root / "docs/research/evidence/owner-session-dry-run.txt"
destination.write_text("\n".join(lines) + "\n")
print(destination)
print("\n".join(lines))
