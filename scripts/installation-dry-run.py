#!/usr/bin/env python3
"""Read-only installed-helper diagnostics and pre-registration refusals. Never installs or uses root."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
bundle = root / ".build/Ventilator.app"
app = bundle / "Contents/MacOS/Ventilator"
helper = app.with_name("VentilatorHelper")
if os.geteuid() == 0:
    raise SystemExit("Installation dry-run must run without root")
lines = [f"Installation gate verification: {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
         f"UID={os.geteuid()}; ad hoc bundle, no SMAppService registration, private-key access, root or hardware writes."]


def command(binary, argument, *extra):
    return subprocess.run([str(binary), argument, *extra], capture_output=True, text=True, timeout=5)


status = command(app, "--helper-status")
assert status.returncode == 0, status.stderr
report = json.loads(status.stdout)
assert not report["trustedBundle"] and not report["helperVerified"] and not report["hardwareControlAvailable"]
assert report["error"] == "appleSignatureRequired", report
for name in ["--verify-installed-helper", "--register-helper", "--unregister-helper"]:
    result = command(app, name)
    assert result.returncode == 78, (name, result.stdout, result.stderr)
    if name == "--verify-installed-helper":
        assert not json.loads(result.stdout)["helperVerified"]
    else:
        assert "appleSignatureRequired" in result.stderr
    lines.append(f"{name}: refused before registration/removal; hardware remains unavailable.")
after = json.loads(command(app, "--helper-status").stdout)
assert after["registration"] == report["registration"] and not after["helperVerified"]
lines.append("Status is not readiness: ad hoc signature rejected; service registration state remained " + report["registration"] + ".")
malformed = command(app, "--register-helper", "unexpected")
assert malformed.returncode == 78 and "invalidChallenge" in malformed.stderr
lines.append("Extra command arguments rejected before service access; no arbitrary path/service supplied by CLI.")

for kind in ["launchArguments", "helperSymlink"]:
    with tempfile.TemporaryDirectory(prefix="installation-layout-", dir=root / ".build") as directory:
        copied = Path(directory) / "Ventilator.app"
        shutil.copytree(bundle, copied)
        if kind == "launchArguments":
            path = copied / "Contents/Library/LaunchDaemons/dev.ventilator.helper.plist"
            data = plistlib.loads(path.read_bytes()); data["ProgramArguments"] = ["/bin/sh"]
            path.write_bytes(plistlib.dumps(data))
        else:
            path = copied / "Contents/MacOS/VentilatorHelper"
            path.unlink(); path.symlink_to("Ventilator")
        result = command(copied / "Contents/MacOS/Ventilator", "--helper-status")
        assert result.returncode == 0, result.stderr
        invalid = json.loads(result.stdout)
        assert invalid["error"] == "invalidLayout" and not invalid["helperVerified"], invalid
        lines.append(f"{kind}: actual bundle inspector rejected layout before service registration.")

symbols = subprocess.check_output(["nm", "-g", str(app)], text=True, timeout=5)
assert "_SMCExperimentOpen" not in symbols and "_SMCExperimentWriteStep" not in symbols
lines += ["GUI still links no native experiment open/write symbols despite adding the installation/XPC client.",
          "Positive Apple-issued signing, root-owned installed bundle, authenticated privileged XPC and SMAppService approval remain unverified.",
          "SHA-256 of tested helper: " + hashlib.sha256(helper.read_bytes()).hexdigest(),
          "SHA-256 of tested application: " + hashlib.sha256(app.read_bytes()).hexdigest()]
text = "\n".join(lines) + "\n"
(root / "docs/research/evidence/installation-dry-run.txt").write_text(text)
print(text, end="")
