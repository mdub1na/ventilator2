#!/usr/bin/env python3
"""Model the archive continuation; never invoke a native CLI, sudo or a signal."""
import importlib.util
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module
probe = load('probe', repo / 'scripts/registration-probe-session.py')
archive = load('archive', repo / 'scripts/registration-probe-archive.py')

def fixture(root):
    source = root / 'source'; source.mkdir(mode=0o700)
    package = root / 'archive'; package.mkdir(mode=0o700)
    payload = source / 'payload.app'; payload.mkdir()
    for name in ('Info.plist', 'app', 'daemon', 'plist', 'CodeResources'):
        (payload / name).write_text('signed model bytes')
    protected = root / 'protected'; protected.mkdir(); (protected / 'app').write_text('preserve')
    for p in (source, package):
        (p / 'session.py').write_text('model script'); (p / 'PLAN.md').write_text('model plan')
    installed = root / 'probe.app'; shutil.copytree(payload, installed)
    probe.save(source / 'manifest.json', {'purpose': 'isolatedRegistrationProbe', 'ownerUID': probe.os.getuid(),
        'sessionPath': str(source), 'machine': probe.MACHINE, 'certificate': probe.CERTIFICATE, 'team': probe.TEAM,
        'installedPath': str(installed), 'scriptSHA256': probe.digest(source / 'session.py'),
        'planSHA256': probe.digest(source / 'PLAN.md'), 'protectedFilesSHA256': {str(protected): probe.tree(protected)},
        'bundleFilesSHA256': probe.tree(payload), 'hardwareWrites': []})
    probe.save(source / 'sealed.json', {'fingerprint': probe.tree(payload), 'positiveRevocation': True})
    probe.save(source / 'cleanup-started.json', {'pid': 2})
    probe.save(source / 'cleanup.json', {'registration': 'notRegistered'})
    probe.save(source / 'job-after-cleanup.json', {'exitCode': 113})
    probe.save(source / 'gui.json', {'pid': 1})
    probe.save(package / 'manifest.json', {'purpose': 'archiveUnregisteredProbe', 'ownerUID': probe.os.getuid(),
        'sessionPath': str(package), 'sourcePath': str(source), 'installedPath': str(installed),
        'scriptSHA256': probe.digest(package / 'session.py'), 'planSHA256': probe.digest(package / 'PLAN.md'),
        'sourceFilesSHA256': probe.tree(source), 'hardwareWrites': []})
    return source, package, installed, protected

for mode in ('complete', 'gui-running', 'cancel', 'malformed-status', 'registered', 'job-loaded', 'alarm',
             'sudo-denied', 'changed-source', 'archive-collision', 'move-failure', 'move-noop', 'no-tty'):
    with tempfile.TemporaryDirectory(prefix='ventilator-archive-model-', dir=repo / '.build') as directory:
        source, package, installed, protected = fixture(Path(directory))
        original = probe.tree(source); calls = []
        if mode == 'changed-source': (source / 'gui.json').write_text('{}')
        if mode == 'archive-collision': (package / 'retired.bundle').mkdir()
        supplied = probe.tree(source)
        def installed_check(p):
            assert p == source
            probe.check(source)
            assert probe.tree(installed) == json.loads((source / 'sealed.json').read_text())['fingerprint']
        def exit_check(*args, **kwargs):
            if mode == 'gui-running': raise RuntimeError('model GUI alive')
        def terminal():
            if mode == 'no-tty': raise RuntimeError('model no owner TTY')
        def execute(argv, timeout=30):
            calls.append([str(x) for x in argv])
            assert argv == [installed / 'Contents/MacOS/RegistrationProbe', '--probe-status', source] and timeout == 10
            value = [] if mode == 'malformed-status' else {'registration': 'enabled' if mode == 'registered' else 'notRegistered',
                'hardwareControlAvailable': False, 'hardwareWritesExecuted': 0}
            return subprocess.CompletedProcess(argv, 0, json.dumps(value), '')
        def privileged(argv, alarm=20):
            argv = [str(x) for x in argv]; calls.append(argv)
            if argv[0] == '/bin/launchctl':
                assert argv == ['/bin/launchctl', 'print', 'system/' + probe.DAEMON_ID] and alarm == 5
                code = {'job-loaded': 0, 'alarm': -14, 'sudo-denied': 1}.get(mode, 113)
                return subprocess.CompletedProcess(argv, code, '', '')
            assert argv == ['/bin/mv', '-n', str(installed), str(package / 'retired.bundle')] and alarm == 20
            if mode == 'move-failure': return subprocess.CompletedProcess(argv, 1, '', 'model failure')
            if mode != 'move-noop': shutil.move(str(installed), str(package / 'retired.bundle'))
            return subprocess.CompletedProcess(argv, 0, '', '')
        with patch.object(archive, 'SOURCE', source), patch.object(probe, 'INSTALLED', installed), \
             patch.object(probe, 'machine', return_value=probe.MACHINE), patch.object(probe, 'owner_terminal', side_effect=terminal), \
             patch.object(probe, 'installed_check', side_effect=installed_check), patch.object(archive, 'require_gui_exit', side_effect=exit_check), \
             patch.object(probe, 'execute', side_effect=execute), patch.object(probe, 'privileged', side_effect=privileged), \
             patch('builtins.input', return_value='CANCEL' if mode == 'cancel' else 'CLOSED'):
            if mode == 'complete':
                archive.finish(package, probe)
                assert not installed.exists() and (package / 'archive-completed.json').exists()
                assert probe.tree(package / 'retired.bundle') == probe.tree(source / 'payload.app')
            else:
                try: archive.finish(package, probe); raise AssertionError('Failure ignored')
                except RuntimeError: pass
                assert installed.exists() and not (package / 'archive-completed.json').exists()
                if mode in ('gui-running', 'cancel', 'changed-source', 'archive-collision', 'no-tty'):
                    assert not calls and not (package / 'archive-started.json').exists()
                if mode in ('malformed-status', 'registered', 'job-loaded', 'alarm', 'sudo-denied'):
                    assert not any(c[0] == '/bin/mv' for c in calls)
            if (package / 'archive-started.json').exists():
                before = list(calls)
                try: archive.finish(package, probe); raise AssertionError('Replay allowed')
                except RuntimeError: pass
                assert calls == before
        assert probe.tree(source) == supplied
        assert (protected / 'app').read_text() == 'preserve'
        print('Archive model: ' + mode + ' passed')

# Exercise the real PID polling logic with an injected clock, including close/exit delay.
with tempfile.TemporaryDirectory(prefix='ventilator-archive-pid-', dir=repo / '.build') as directory:
    source = Path(directory); probe.save(source / 'gui.json', {'pid': 1})
    with patch.object(archive, 'SOURCE', source), patch.object(archive.time, 'sleep'), \
         patch.object(archive.time, 'monotonic', side_effect=[0, 1, 2]), \
         patch.object(archive.os, 'kill', side_effect=[None, ProcessLookupError()]):
        archive.require_gui_exit(probe)
    for error in (None, PermissionError()):
        with patch.object(archive, 'SOURCE', source), patch.object(archive.os, 'kill', side_effect=[error]):
            try: archive.require_gui_exit(probe, seconds=0); raise AssertionError('Live/unknown PID ignored')
            except RuntimeError: pass
print('13 archive outcomes + replay/source preservation + bounded GUI exit paths passed. No real commands or signals.')
