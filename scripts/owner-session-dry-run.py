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

previous = {"applicationSHA256": "a" * 64, "helperSHA256": "b" * 64, "launchDaemonSHA256": "c" * 64}
inactive = {"fingerprint": previous, "trustedBundle": True, "rootOwned": True, "installedLocation": True,
            "registration": "notFound", "error": "serviceNotEnabled", "helperVerified": False, "hardwareControlAvailable": False}
session.admit_replacement(inactive, previous, previous, False)
for key, value in [("registration", "enabled"), ("registration", "requiresApproval"), ("trustedBundle", False),
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
lines.append("Pinned replacement policy rejects active/approved service, changed hashes, invalid identity/ownership and any hardware journal directory; pure inputs only.")

# Execute the orchestration with fake external commands, including a change during staging.
for changed_after_staging in [False, True]:
    with tempfile.TemporaryDirectory(prefix="ventilator-replace-", dir=root / ".build") as tmp:
        directory = Path(tmp)
        new = {**previous, "applicationSHA256": "d" * 64}
        (directory / "sealed.json").write_text(json.dumps({"fingerprint": new}))
        staged = {"trustedBundle": True, "rootOwned": True, "fingerprint": new}
        second = {**inactive, "fingerprint": {}} if changed_after_staging else inactive
        with patch.object(session, "SESSION", directory), patch.object(session, "owner_terminal"), \
                patch.object(session, "check", return_value={"installedReplacement": previous}), \
                patch.object(session, "fingerprints", return_value=previous), \
                patch.object(session, "installed_check"), patch.object(session.HARDWARE_ROOT.__class__, "lstat", side_effect=FileNotFoundError), \
                patch.object(session.os.path, "lexists", return_value=False), \
                patch.object(session, "output", side_effect=[json.dumps(inactive), json.dumps(staged), json.dumps(second)]), \
                patch.object(session.subprocess, "run") as commands:
            if changed_after_staging:
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
                assert operations == ["/usr/bin/ditto", "/usr/sbin/chown", "/bin/chmod", "/bin/mv", "/bin/mv"]
            assert (directory / "replacement-started.json").exists()
lines.append("Replacement orchestration preserved backup order on mocked commands; an installed hash change during staging stopped both moves and retained its marker.")

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
