#!/usr/bin/env python3
"""One non-root, NAND-only observation; preserve a failed run instead of repeating it."""
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parent.parent
expected = {'model': 'Mac15,7', 'version': '27.0.1', 'build': '26A434'}
paths = ('tools/nand_profile_probe.m', 'Sources/CHIDTemperature/HIDTemperatureRead.c',
         'Sources/CHIDTemperature/include/HIDTemperatureRead.h', 'scripts/build-nand-profile-probe.sh',
         'scripts/check-nand-profile.py', '.build/research/nand-profile-probe')

def hashes():
    return {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in paths}

def save(path, value):
    with path.open('x') as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write('\n')

def qualifies(report, code, error, unchanged):
    if (type(code) is not int or code != 0 or error is not None or not unchanged or not isinstance(report, dict) or
        report.get('passed') is not True or report.get('profileBefore') != expected or
        report.get('profileAfter') != expected or type(report.get('hardwareWrites')) is not int or
        report['hardwareWrites'] != 0 or
        report.get('SMCTransportLinked') is not False):
        return False
    samples = report.get('samples')
    if not isinstance(samples, list) or len(samples) != 5:
        return False
    previous = -1
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            return False
        if (type(sample.get('index')) is not int or sample['index'] != index or
            type(sample.get('status')) is not int or sample['status'] != 0 or sample.get('accepted') is not True):
            return False
        value, duration, elapsed = (sample.get(key) for key in ('celsius', 'readSeconds', 'elapsedSeconds'))
        if not all(type(number) in (int, float) and math.isfinite(number) for number in (value, duration, elapsed)):
            return False
        if not (-10 <= value <= 125 and 0 <= duration < 0.5 and duration <= elapsed < 8 and elapsed > previous):
            return False
        previous = elapsed
    return previous >= 4

def main():
    if len(sys.argv) != 2 or os.geteuid() == 0:
        raise SystemExit('Use non-root check-nand-profile.py NEW_OUTPUT_DIRECTORY')
    folder = Path(sys.argv[1]).absolute()
    if folder.resolve() != folder or folder.exists():
        raise SystemExit('Output must be a new unaliased directory; no retry')
    before = hashes()
    folder.mkdir(mode=0o700)
    save(folder / 'started.json', {'UID': os.geteuid(), 'sourceSHA256': before, 'expectedProfile': expected})
    report = None
    error = None
    code = None
    try:
        run = subprocess.run([str(repo / '.build/research/nand-profile-probe')],
                             capture_output=True, text=True, timeout=8)
        code = run.returncode
        report = json.loads(run.stdout) if run.stdout.strip() else None
        error = run.stderr.strip() or None
    except (OSError, subprocess.SubprocessError, ValueError) as failure:
        error = str(failure)
    try:
        unchanged = before == hashes()
    except OSError as failure:
        unchanged = False
        error = error or str(failure)
    qualified = qualifies(report, code, error, unchanged)
    result = {'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'expectedProfile': expected, 'qualified': qualified, 'UID': os.geteuid(),
              'exitCode': code, 'error': error, 'observation': report, 'sourceSHA256': before,
              'sourcesUnchanged': unchanged, 'sudoOrHelperUsed': False, 'fanWrites': 0,
              'physicalAutoVerified': False, 'CPUOrGPUAttributed': False}
    save(folder / 'result.json', result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not qualified:
        raise SystemExit('NAND profile not qualified; preserve results, no automatic retry')

if __name__ == '__main__':
    main()
