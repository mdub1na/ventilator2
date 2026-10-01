#!/usr/bin/env python3
"""Try configured signing only in an isolated no-graphics/no-TTY security session; never unlock a keychain."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
if os.geteuid() == 0:
    raise SystemExit("Signing must run without root")
source = root / ".build/Ventilator.app"
wrapper = root / ".build/sign-without-ui"
report = {"checkedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
          "effectiveUID": os.geteuid(), "signed": False, "hardwareWritesExecuted": 0,
          "keychainSettingsChanged": False, "signingAttempted": False, "bundle": None}
subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(root / ".build/swift-module-cache"),
                str(root / "tools/sign_without_ui.swift"), "-o", str(wrapper)], check=True, timeout=30)
identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True, timeout=10)
entries = re.findall(r'^\s*\d+\) ([0-9A-F]{40}) "[^"]+"(.*)$', identities.stdout, re.MULTILINE)
report["identities"] = [{"certificateSHA1": sha, "revoked": "REVOKED" in flags} for sha, flags in entries]
candidates = [sha for sha, flags in entries if not flags.strip()]
report["candidateCertificateSHA1"] = candidates[0] if len(candidates) == 1 else None
probe = subprocess.run([str(wrapper), "--probe"], cwd=root, capture_output=True, text=True, timeout=5)
report["sessionProbeExitCode"] = probe.returncode
report["sessionProbe"] = (probe.stdout + probe.stderr).strip()
report["wrapperSHA256"] = hashlib.sha256(wrapper.read_bytes()).hexdigest()
if probe.returncode:
    report["blocker"] = "headlessSecuritySessionUnavailable"
elif len(candidates) != 1:
    report["blocker"] = "singleUnflaggedIdentityRequired"
else:
    staging = Path(tempfile.mkdtemp(prefix="signed-bundle-", dir=root / ".build")) / "Ventilator.app"
    shutil.copytree(source, staging)
    report["bundle"] = str(staging)
    for role in ["helper", "application"]:
        report["signingAttempted"] = True
        result = subprocess.run([str(wrapper), role, candidates[0], str(staging)], cwd=root,
                                capture_output=True, text=True, timeout=15)
        report[role + "SigningExitCode"] = result.returncode
        report[role + "SigningOutput"] = (result.stdout + result.stderr).strip()
        if result.returncode:
            report["blocker"] = "noninteractiveSigningFailed"
            break
    else:
        for path in [staging / "Contents/MacOS/VentilatorHelper", staging]:
            subprocess.run(["codesign", "--verify", "--strict", str(path)], check=True, timeout=10)
        status = subprocess.run([str(staging / "Contents/MacOS/Ventilator"), "--helper-status"],
                                capture_output=True, text=True, check=True, timeout=5)
        checked = json.loads(status.stdout)
        report["signed"] = checked["trustedBundle"]
        report["fingerprint"] = checked.get("fingerprint")
        if not report["signed"]:
            report["blocker"] = "signedBundleInspectorRejected"
report["installed"] = False
report["ownerSessionStillRequired"] = True
text = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
(root / "docs/research/evidence/installation-signing.json").write_text(text)
print(text, end="")
