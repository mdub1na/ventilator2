#!/usr/bin/env python3
"""Sample before, during and after two bounded 10-second workloads; no SMC writes."""
import json
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[1]
output = root / ".build/research"
phases = []
with (output / "temperature-workloads.jsonl").open("w") as samples:
    probe = subprocess.Popen([str(output / "temperature-probe"), "45"], stdout=samples)
    try:
        time.sleep(5)
        for phase in ("cpu", "gpu"):
            run = subprocess.run([str(output / "temperature-workload"), phase],
                                 capture_output=True, text=True, timeout=20)
            record = json.loads(run.stdout)
            phases.append(record)
            print(json.dumps(record), flush=True)
            if run.returncode:
                break
            time.sleep(8)
        probe.wait(timeout=25)
        if probe.returncode:
            raise RuntimeError(f"Probe failed: {probe.returncode}")
    finally:
        if probe.poll() is None:
            probe.terminate()
            probe.wait(timeout=5)
        (output / "temperature-phases.json").write_text(
            json.dumps(phases, indent=2) + "\n")
