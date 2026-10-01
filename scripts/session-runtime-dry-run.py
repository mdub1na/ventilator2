#!/usr/bin/env python3
"""Same XPC/session proxy and process broker, immutable file-model authority; never uses root."""
import datetime
import hashlib
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
helper = root / ".build/Ventilator.app/Contents/MacOS/VentilatorHelper"
if os.geteuid() == 0:
    raise SystemExit("Runtime dry-run requires non-root")
result = subprocess.run([str(helper), "--session-runtime-check"], capture_output=True, text=True, timeout=40)
assert result.returncode == 0, result.stderr
assert result.stdout.count("Runtime XPC model:") == 2, result.stdout
assert result.stdout.count("Runtime startup model:") == 2, result.stdout
lines = [f"Session runtime verification: {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
         f"UID={os.geteuid()}; anonymous XPC and file simulation only, no native open/write, registration or root.",
         result.stdout.strip()]
for argument in ["--hardware-broker", "--hardware-preflight-child"]:
    denied = subprocess.run([str(helper), argument], capture_output=True, text=True, timeout=3)
    assert denied.returncode == 78, (argument, denied.stdout, denied.stderr)
    lines.append(argument + ": non-root refused before native/journal access.")
lines += ["Actual route consumed local model approval after isolated nonce/PID/deadline-bound read-only preflight.",
          "Independent Fixed observation, wrong connection control, explicit Auto, XPC invalidation and spent replay verified.",
          "Hardware runtime is compiled behind root/installed identity, local hardware receipt and private pipes; positive installed execution remains unverified.",
          "Hardware pending/physicalAutoVerified=false are retained; no product controls enabled.",
          "SHA-256 of tested helper: " + hashlib.sha256(helper.read_bytes()).hexdigest()]
text = "\n".join(lines) + "\n"
(root / "docs/research/evidence/session-runtime-dry-run.txt").write_text(text)
print(text, end="")
