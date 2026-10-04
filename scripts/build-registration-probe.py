#!/usr/bin/env python3
"""Build the separate diagnostic app ad hoc. Never access the signing identity or SMAppService."""
import os
import plistlib
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
source = repo / "Diagnostics/RegistrationProbe"
output = repo / ".build/registration-probe-build"
app = output / "Ventilator Registration Probe.app"
binary = app / "Contents/MacOS"
binary.mkdir(parents=True, exist_ok=True)
cache = output / "module-cache"
cache.mkdir(exist_ok=True)
for name, main in [("RegistrationProbe", "ProbeApp.swift"), ("RegistrationProbeDaemon", "ProbeDaemon.swift")]:
    inputs = [str(source / "ProbeBundle.swift"), str(source / main)] if name == "RegistrationProbe" else [str(source / main)]
    subprocess.run(["/usr/bin/xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(cache),
                    *inputs, "-o", str(binary / name)], check=True)
info = {"CFBundleIdentifier": "dev.ventilator.registration-probe", "CFBundleExecutable": "RegistrationProbe",
        "CFBundleName": "Ventilator Registration Probe", "CFBundleDisplayName": "Ventilator Registration Probe",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True}
plist = {"Label": "dev.ventilator.registration-probe.daemon", "BundleProgram": "Contents/MacOS/RegistrationProbeDaemon", "RunAtLoad": True}
launch = app / "Contents/Library/LaunchDaemons/dev.ventilator.registration-probe.daemon.plist"
launch.parent.mkdir(parents=True, exist_ok=True)
(app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
launch.write_bytes(plistlib.dumps(plist))
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", plist["Label"], "--timestamp=none", str(binary / "RegistrationProbeDaemon")], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app)], check=True)
for path in (binary / "RegistrationProbeDaemon", app):
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(path)], check=True)
print(app)
