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

root = Path(__file__).resolve().parents[1]
helper = root / ".build/Ventilator.app/Contents/MacOS/VentilatorHelper"
app = helper.with_name("Ventilator")
assert os.geteuid() != 0
lines = [f"Owner session dry-run: {datetime.now().astimezone().isoformat(timespec='seconds')}",
         "Non-root offline files and anonymous model only; no private key, signing, sudo, installation or native writes."]


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
    for command in ["sign", "install", "register", "ready", "run", "collect", "unregister"]:
        refusal = run(["python3", package / "session.py", command], success=False)
        assert "non-root Terminal" in refusal.stderr
    assert not (package / "sign-started.json").exists()
    original = (package / "PLAN.md").read_text()
    (package / "PLAN.md").write_text(original + "modified")
    assert "Package changed" in run(["python3", package / "session.py", "check"], success=False).stderr
    lines.append("Copied package fingerprints/check passed; changed plan rejected; seven owner actions rejected before mutation without Terminal.")
finally:
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
          "Positive Apple-issued signing/revocation, root installed connection, sudo stages and hardware experiment require owner; not claimed.",
          f"SHA-256 of tested helper: {hashlib.sha256(helper.read_bytes()).hexdigest()}",
          f"SHA-256 of tested application: {hashlib.sha256(app.read_bytes()).hexdigest()}"]
destination = root / "docs/research/evidence/owner-session-dry-run.txt"
destination.write_text("\n".join(lines) + "\n")
print(destination)
print("\n".join(lines))
