#!/usr/bin/env python3
"""Export and check an unapproved offline candidate. Never registers a helper or executes SMC writes."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
helper = root / ".build/Ventilator.app/Contents/MacOS/VentilatorHelper"
application = helper.with_name("Ventilator")
if os.geteuid() == 0:
    raise SystemExit("Offline preparation must run without root")
result = subprocess.run([str(helper), "--candidate-plan"], capture_output=True, text=True, check=True, timeout=5)
document = json.loads(result.stdout)
plan = document["plan"]
assert plan["stage"] == "candidate-unapproved" and not plan["readyForOwnerApproval"]
assert document["hardwareWritesExecuted"] == 0 and document["blockers"]
assert plan["binaries"]["helperSHA256"] == hashlib.sha256(helper.read_bytes()).hexdigest()
assert plan["binaries"]["applicationSHA256"] == hashlib.sha256(application.read_bytes()).hexdigest()
canonical = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
assert hashlib.sha256(canonical).hexdigest() == document["planSHA256"]
destination = root / "docs/research/evidence/candidate-experiment-plan.json"
destination.write_text(result.stdout)
print(f"Candidate exported: {destination}")
print(f"Plan SHA-256: {document['planSHA256']}")
print("Candidate only; readyForOwnerApproval=false; no hardware writes. See blockers in the artifact.")
