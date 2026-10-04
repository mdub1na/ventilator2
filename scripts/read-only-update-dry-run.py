#!/usr/bin/env python3
"""Exercise the diagnostic update with mocked OS commands; never signs, installs or writes SMC."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

root = Path(__file__).absolute().parent.parent
spec = importlib.util.spec_from_file_location("owner_update", root / "scripts/owner-session.py")
session = importlib.util.module_from_spec(spec); spec.loader.exec_module(session)
assert os.geteuid() != 0
previous = {"applicationSHA256": "a" * 64, "helperSHA256": "b" * 64, "launchDaemonSHA256": "c" * 64}
new = {**previous, "helperSHA256": "d" * 64}
identity = {"trustedBundle": True, "rootOwned": True, "installedLocation": True, "hardwareControlAvailable": False}
disabled = {**identity, "fingerprint": previous, "registration": "requiresApproval", "helperVerified": False, "error": "serviceNotEnabled"}
verified = {**identity, "fingerprint": new, "registration": "enabled", "helperVerified": True}

for mode in ["pending-success", "enabled-success", "runtime-present", "runtime-after-off", "cancel-off", "cancel-on",
             "changed-old-hash", "removal-incomplete", "register-failure", "peer-failure", "hardware-status-failure",
             "unsigned-success", "sign-failure", "qualification-failure", "changed-machine"]:
    with tempfile.TemporaryDirectory(prefix="ventilator-readonly-update-model-", dir=root / ".build") as directory:
        package = Path(directory)
        (package / "PLAN.md").write_text("Model read-only update; zero hardware writes.")
        if mode not in ["unsigned-success", "sign-failure", "qualification-failure"]:
            (package / "sealed.json").write_text(json.dumps({"fingerprint": new}))
        runtime = package / "runtime"
        if mode == "runtime-present": runtime.mkdir()
        manifest = {"readOnlyUpdate": True, "installedReplacement": previous, "readOnlyMachine": session.READ_ONLY_MACHINE}
        calls, actions, replacements = [], [], []
        def sign_model():
            if mode == "sign-failure": raise RuntimeError("Model signing failure")
            (package / "signature-ready.json").write_text("model signed marker")
        def qualify_model():
            if mode == "qualification-failure": raise RuntimeError("Model qualification failure")
            (package / "sealed.json").write_text(json.dumps({"fingerprint": new}))
        def answer(prompt):
            action = "OFF" if "OFF" in prompt else "ON"
            actions.append(action)
            if mode == "runtime-after-off" and action == "OFF": runtime.mkdir()
            return "cancel" if mode == "cancel-" + action.lower() else action
        def command_output(command, timeout=5):
            command = [str(p) for p in command]; calls.append(command[1])
            flag = command[1]
            if flag == "--helper-status":
                return json.dumps({**disabled, "fingerprint": {}} if mode == "changed-old-hash" else disabled)
            if flag == "--unregister-helper":
                return json.dumps(disabled if mode == "removal-incomplete" else {**disabled, "registration": "notRegistered"})
            if flag == "--register-helper":
                if mode == "register-failure": raise RuntimeError("Model registration failure")
                return json.dumps(verified if mode == "enabled-success" else {**verified, "registration": "requiresApproval", "helperVerified": False})
            if flag == "--verify-installed-helper":
                return json.dumps({**verified, "helperVerified": False} if mode == "peer-failure" else verified)
            if flag == "--owner-experiment-status":
                return json.dumps({"hardwareControlAvailable": False, "errorCode": "other" if mode == "hardware-status-failure" else 'failed("unsupportedMachine")'})
            raise AssertionError("Unexpected native command: " + flag)
        with patch.object(session, "SESSION", package), patch.object(session, "HARDWARE_ROOT", runtime), \
                patch.object(session, "current_machine", return_value={} if mode == "changed-machine" else session.READ_ONLY_MACHINE), \
                patch.object(session, "READ_ONLY_STAGE", package / "staging"), patch.object(session, "READ_ONLY_BACKUP", package / "backup"), \
                patch.object(session, "owner_terminal"), patch.object(session, "check", return_value=manifest), \
                patch.object(session, "fingerprints", side_effect=lambda _: new if replacements else previous), \
                patch.object(session, "installed_check", return_value={"fingerprint": new}), \
                patch.object(session, "replace_installed", side_effect=lambda: replacements.append("replace")), \
                patch.object(session, "sign", side_effect=sign_model) as signing, patch.object(session, "qualify", side_effect=qualify_model) as qualification, \
                patch.object(session, "output", side_effect=command_output), patch("builtins.input", side_effect=answer), \
                patch.object(session.subprocess, "run") as external:
            try:
                session.update_read_only()
                assert mode in ["pending-success", "enabled-success", "unsigned-success"]
            except RuntimeError:
                assert mode not in ["pending-success", "enabled-success", "unsigned-success"]
            assert signing.call_count == (1 if mode in ["unsigned-success", "sign-failure", "qualification-failure"] else 0)
            assert qualification.call_count == (1 if mode in ["unsigned-success", "qualification-failure"] else 0)
            external.assert_not_called()
            assert (package / "result.json").exists() == (mode in ["pending-success", "enabled-success", "unsigned-success"])
            if mode in ["sign-failure", "qualification-failure"]: assert not actions and not calls and not replacements
            if mode == "changed-machine": assert not actions and not calls and not (package / "update-started.json").exists()
            if mode in ["runtime-present", "runtime-after-off", "cancel-off"]: assert not calls and not replacements
            if mode == "changed-old-hash": assert calls == ["--helper-status"] and not replacements
            if mode == "removal-incomplete": assert not replacements and "--register-helper" not in calls
            if mode in ["register-failure", "cancel-on"]: assert "--verify-installed-helper" not in calls
            if mode == "enabled-success": assert actions == ["OFF"] and "--verify-installed-helper" not in calls
            before = (list(calls), list(actions), list(replacements), signing.call_count, qualification.call_count)
            try:
                session.update_read_only()
                raise AssertionError("Update replayed")
            except (RuntimeError, FileExistsError): pass
            assert before == (calls, actions, replacements, signing.call_count, qualification.call_count)
print("One-shot update model: three success and twelve failure paths preserve markers, stop dependent actions and block replay including signing/qualification; changed OS refused before marker.")

# Use the real replacement orchestration, with exact scoped administrative argv mocked.
with tempfile.TemporaryDirectory(prefix="ventilator-readonly-replacement-model-", dir=root / ".build") as directory:
    package = Path(directory)
    (package / "sealed.json").write_text(json.dumps({"fingerprint": new}))
    staging, backup = package / "profile-staging.app", package / "old.bundle-backup"
    responses = [json.dumps(disabled), json.dumps(disabled), json.dumps({**identity, "fingerprint": new}), json.dumps(disabled)]
    with patch.object(session, "SESSION", package), patch.object(session, "HARDWARE_ROOT", package / "absent"), \
            patch.object(session, "READ_ONLY_STAGE", staging), patch.object(session, "READ_ONLY_BACKUP", backup), \
            patch.object(session, "owner_terminal"), patch.object(session, "check", return_value={"readOnlyUpdate": True, "installedReplacement": previous}), \
            patch.object(session, "fingerprints", return_value=previous), patch.object(session, "installed_check"), \
            patch.object(session, "output", side_effect=responses), patch.object(session, "launchd_job_present", side_effect=[True, False, False]), \
            patch.object(session.subprocess, "run") as external:
        session.replace_installed()
        commands = [c.args[0] for c in external.call_args_list]
        assert commands[0] == ["sudo", "/bin/launchctl", "bootout", "system/dev.ventilator.helper"]
        assert commands[-2] == ["sudo", "/bin/mv", str(session.INSTALLED), str(backup)]
        assert commands[-1] == ["sudo", "/bin/mv", str(staging), str(session.INSTALLED)]
        assert [c[1] for c in commands] == ["/bin/launchctl", "/usr/bin/ditto", "/usr/sbin/chown", "/bin/chmod", "/bin/mv", "/bin/mv"]
        assert (package / "replacement-completed.json").exists()
print("Real replacement orchestration model: one scoped bootout, staged identity check, distinct non-app backup and ordered moves.")

# Real copy/check/CLI refusal; only the certificate qualification response is a fixture.
with tempfile.TemporaryDirectory(prefix="ventilator-readonly-package-model-", dir=root / ".build") as directory:
    base = Path(directory); source, package = base / "previous", base / "update"
    source.mkdir()
    fingerprints = session.fingerprints(root / ".build/Ventilator.app")
    import shutil
    shutil.copytree(root / ".build/Ventilator.app", source / "Ventilator.app")
    (source / "sealed.json").write_text(json.dumps({"certificateSHA1": session.CERTIFICATE, "teamIdentifier": session.TEAM,
                                                  "positiveRevocation": True, "fingerprint": fingerprints}))
    with patch.object(session, "SESSION", package), patch.object(session, "PREVIOUS_SESSION", source), patch.object(session, "READ_ONLY_UPDATE", True), \
            patch.object(session, "current_machine", return_value=session.READ_ONLY_MACHINE):
        session.prepare()
        session.save("signature-ready.json", {"fingerprint": fingerprints})
        qualification = {"certificateSHA1": session.CERTIFICATE, "teamIdentifier": session.TEAM, "positiveRevocation": True,
                         "notarizationClaimed": False, "fingerprint": fingerprints}
        with patch.object(session, "output", return_value=json.dumps(qualification)) as external:
            session.qualify()
            assert external.call_count == 1 and "--qualify-owner-signature" in external.call_args.args[0]
        assert session.check(sealed=True)["readOnlyUpdate"]
        assert session.package_status()["fullReview"] == "notApplicable"
        assert not any((package / n).exists() for n in ["candidate.json", "review.json", "review.sha256"])
        for command in ["ready", "run", "collect", "setup", "install", "register", "replace-installed", "unregister"]:
            result = subprocess.run(["python3", str(package / "session.py"), command], capture_output=True, text=True, timeout=5)
            assert result.returncode == 78 and "Read-only package permits" in result.stderr
        result = subprocess.run(["python3", str(package / "session.py"), "update-read-only"], capture_output=True, text=True, timeout=5)
        assert result.returncode == 78 and "non-root Terminal" in result.stderr
        assert not (package / "update-started.json").exists()
        (package / "review.json").write_text("model forbidden authority")
        try:
            session.check(sealed=True)
            raise AssertionError("Hardware review in read-only package admitted")
        except RuntimeError: pass
print("Real copied package/CLI: fixture qualification creates only seal; hardware review and eight disallowed commands refused; update requires owner TTY.")

# Preserve a stopped, signature-complete source. Model signatures only; public proof is a fixture.
with tempfile.TemporaryDirectory(prefix="ventilator-readonly-resume-model-", dir=root / ".build") as directory:
    import shutil
    base = Path(directory)
    previous_package, stopped, resumed = base / "previous", base / "stopped", base / "resumed"
    previous_package.mkdir()
    shutil.copytree(root / ".build/Ventilator.app", previous_package / "Ventilator.app")
    hashes = session.fingerprints(previous_package / "Ventilator.app")
    (previous_package / "sealed.json").write_text(json.dumps({"certificateSHA1": session.CERTIFICATE,
        "teamIdentifier": session.TEAM, "positiveRevocation": True, "fingerprint": hashes}))
    with patch.object(session, "SESSION", stopped), patch.object(session, "PREVIOUS_SESSION", previous_package), \
            patch.object(session, "SIGNED_SESSION", None), patch.object(session, "READ_ONLY_UPDATE", True), \
            patch.object(session, "current_machine", return_value=session.READ_ONLY_MACHINE):
        session.prepare()
        session.save("update-started.json", {"previous": hashes, "hardwareWritesExecuted": 0})
        session.save("sign-started.json", {"certificateSHA1": session.CERTIFICATE, "hardwareWritesExecuted": 0})
        session.save("signature-ready.json", {"fingerprint": hashes, "hardwareWritesExecuted": 0})
        session.save("qualification-started.json", {"fingerprint": hashes, "hardwareWritesExecuted": 0})
    with patch.object(session, "SESSION", resumed), patch.object(session, "PREVIOUS_SESSION", previous_package), \
            patch.object(session, "SIGNED_SESSION", stopped), patch.object(session, "READ_ONLY_UPDATE", True), \
            patch.object(session, "current_machine", return_value=session.READ_ONLY_MACHINE), \
            patch.object(session, "candidate", side_effect=AssertionError("Hardware candidate called")):
        before = session.read_only_source_files()
        with patch.object(session.sys, "argv", [str(root / "scripts/owner-session.py"), "prepare", "--read-only-update",
                "--previous-session", str(previous_package), "--signed-session", str(stopped), "--output", str(resumed)]):
            session.main()
        manifest = session.check()
        assert manifest["signatureReady"] and manifest["resumedFrom"]["filesSHA256"] == before
        assert manifest["fingerprint"] == hashes and manifest["installedReplacement"] == hashes
        assert not (resumed / "signature-ready.json").exists()
        assert "Developer public certificate" in session.package_status()["nextStep"]
        with patch.object(session, "owner_terminal"), patch.object(session, "output") as external, \
                patch("builtins.input") as action, patch.object(session, "sign") as signing:
            try:
                session.update_read_only()
                raise AssertionError("Unqualified resume reached owner actions")
            except RuntimeError as error: assert "Developer public certificate" in str(error)
            external.assert_not_called(); action.assert_not_called(); signing.assert_not_called()
            assert not (resumed / "update-started.json").exists()
        with patch.object(session, "owner_terminal"), patch.object(session.subprocess, "run") as external:
            try:
                session.sign()
                raise AssertionError("Imported package re-signed")
            except RuntimeError as error: assert "already signed" in str(error)
            external.assert_not_called()
        proof = {"certificateSHA1": session.CERTIFICATE, "teamIdentifier": session.TEAM, "positiveRevocation": True,
                 "notarizationClaimed": False, "fingerprint": hashes}
        with patch.object(session, "output", return_value=json.dumps(proof)) as external:
            session.qualify()
            assert external.call_count == 1
            try:
                session.qualify()
                raise AssertionError("Qualification repeated")
            except RuntimeError: pass
            assert external.call_count == 1
        assert session.check(sealed=True)["readOnlyUpdate"]
        assert session.read_only_source_files() == before
        assert not any((resumed / n).exists() for n in ["candidate.json", "review.json", "review.sha256"])
        with patch.object(session, "READ_ONLY_UPDATE", False):
            try:
                session.signed_source()
                raise AssertionError("Read-only source became hardware source")
            except RuntimeError as error: assert "cannot become a hardware package" in str(error)
        mutations = [
            (stopped / "signature-ready.json", json.dumps({"fingerprint": {}, "hardwareWritesExecuted": 0}).encode()),
            (stopped / "qualification-started.json", json.dumps({"fingerprint": hashes, "hardwareWritesExecuted": 1}).encode()),
            (stopped / "update-started.json", json.dumps({"previous": {}, "hardwareWritesExecuted": 0}).encode()),
            (stopped / "PLAN.md", b"changed plan"),
            (stopped / "Ventilator.app/Contents/MacOS/VentilatorHelper", b"changed executable"),
            (stopped / "removal-started.json", b"{}"),
            (stopped / "candidate.json", b"{}"),
        ]
        for path, content in mutations:
            original = path.read_bytes() if path.exists() else None
            path.write_bytes(content)
            try:
                session.signed_source()
                raise AssertionError("Changed source admitted: " + path.name)
            except RuntimeError: pass
            finally:
                if original is None: path.unlink()
                else: path.write_bytes(original)
        with patch.object(session, "SESSION", base / "copy-race"), \
                patch.object(session, "read_only_source_files", side_effect=[before, {}]):
            try:
                session.prepare()
                raise AssertionError("Changed source while copying admitted")
            except RuntimeError as error: assert "changed while copying" in str(error)
            assert not (base / "copy-race/manifest.json").exists()
        assert session.read_only_source_files() == before
print("Signed read-only resume: exact source preserved; unqualified owner command and re-sign refused; one public seal; hardware conversion, seven source mutations and copy race rejected.")
print("Read-only update dry-run passed; no actual signature, sudo, installation, service mutation or SMC writes.")
