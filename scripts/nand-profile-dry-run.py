#!/usr/bin/env python3
"""Exercise admission and one-shot collection with fake data; no hardware or privileged calls."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('nand_check', repo / 'scripts/check-nand-profile.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
valid = {'profileBefore': module.expected, 'profileAfter': module.expected, 'passed': True,
         'hardwareWrites': 0, 'SMCTransportLinked': False,
         'samples': [{'index': i, 'status': 0, 'accepted': True, 'celsius': 30,
                      'readSeconds': 0.01, 'elapsedSeconds': i + 0.02} for i in range(5)]}
assert module.qualifies(valid, 0, None, True)
checks = 1
cases = []
for name, change in (
    ('wrongProfile', lambda r: r.update(profileAfter={'model': 'other'})),
    ('nonfinite', lambda r: r['samples'][0].update(celsius=float('nan'))),
    ('lateRead', lambda r: r['samples'][0].update(readSeconds=0.5)),
    ('shortSeries', lambda r: r['samples'][4].update(elapsedSeconds=3.9)),
    ('failedNativeGuard', lambda r: r['samples'][0].update(status=-5)),
    ('falseStatus', lambda r: r['samples'][0].update(status=False)),
    ('falseWriteCount', lambda r: r.update(hardwareWrites=False)),
    ('missingSample', lambda r: r['samples'].pop()),
):
    bad = copy.deepcopy(valid); change(bad)
    assert not module.qualifies(bad, 0, None, True), name
    cases.append(name)
    checks += 1
for code, error, unchanged in ((78, None, True), (0, 'reader error', True), (0, None, False), (False, None, True)):
    assert not module.qualifies(valid, code, error, unchanged)
    checks += 1

with tempfile.TemporaryDirectory(prefix='nand-model-', dir=repo / '.build') as temporary:
    fake = Path(temporary)
    for name in module.paths:
        path = fake / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('fake source\n')
    binary = fake / '.build/research/nand-profile-probe'
    count = fake / 'calls'
    binary.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n'
                      f'Path({str(count)!r}).write_text("called")\nprint({json.dumps(valid)!r})\n')
    binary.chmod(0o700)
    output = fake / 'output'
    with patch.object(module, 'repo', fake), patch.object(module.sys, 'argv', ['check', str(output)]), patch('builtins.print'):
        module.main()
        result = json.loads((output / 'result.json').read_text())
        assert result['qualified'] and result['sourcesUnchanged'] and result['fanWrites'] == 0
        checks += 1
        before = {p.name: p.read_bytes() for p in output.iterdir()}
        count.unlink()
        try: module.main()
        except SystemExit: pass
        else: raise AssertionError('replay admitted')
        assert not count.exists() and before == {p.name: p.read_bytes() for p in output.iterdir()}
        checks += 1
    for index, failure in enumerate((OSError('model launch failure'), subprocess.TimeoutExpired('model', 8))):
        failed_output = fake / f'failed-{index}'
        with patch.object(module, 'repo', fake), patch.object(module.sys, 'argv', ['check', str(failed_output)]), \
             patch.object(module.subprocess, 'run', side_effect=failure) as launch, patch('builtins.print'):
            try: module.main()
            except SystemExit: pass
            else: raise AssertionError('failed launch qualified')
            result = json.loads((failed_output / 'result.json').read_text())
            assert not result['qualified'] and result['error'] and (failed_output / 'started.json').exists()
            assert launch.call_count == 1 and launch.call_args.kwargs['timeout'] == 8
            assert not count.exists()
            checks += 1
print(f'{checks} fake-data checks passed, including real subprocess collection, replay denial and preserved launch/timeout failures. No HID/SMC/helper/root operations.')
