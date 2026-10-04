#!/usr/bin/env python3
"""Run only models and rejected admission paths in the ad hoc diagnostic build."""
import json
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
app = repo / ".build/registration-probe-build/Ventilator Registration Probe.app"
results = []
for args in [["--model-check"], ["--inspect-probe", str(app)], ["--qualify-probe", str(app)], ["--probe-status", "/tmp"], ["--probe-cleanup", "/tmp"]]:
    result = subprocess.run([str(app / "Contents/MacOS/RegistrationProbe"), *args], capture_output=True, text=True, timeout=10)
    expected = 0 if args == ["--model-check"] else 78
    assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
    results.append({"arguments": args, "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
for args, expected in [(["--model-check"], 0), ([], 78)]:
    result = subprocess.run([str(app / "Contents/MacOS/RegistrationProbeDaemon"), *args], capture_output=True, text=True, timeout=10)
    assert result.returncode == expected
    results.append({"arguments": ["daemon", *args], "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
(repo / ".build/registration-probe-native-checks.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
print("Native probe: model/replay passed; ad hoc inspect/qualify, uninstalled status/cleanup and non-root daemon refused before service/device access.")
