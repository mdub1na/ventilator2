#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Finish a stopped probe's archival without repeating registration or unregister."""
import json
import os
import shutil
import sys
import time
import types
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
SOURCE = REPO / '.build/registration-probe-owner'
DESTINATION = REPO / '.build/registration-probe-archive-owner'
PLAN = REPO / 'docs/registration-probe-archive-owner.md'
SOURCE_SCRIPT_SHA256 = '08b0666e17ab81b3c2329d720afb25a7310bf176686996530616688ade37f139'

def frozen_source():
    # Execute verified source bytes without adding a __pycache__ to the preserved session.
    import hashlib
    path = SOURCE / 'session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_SCRIPT_SHA256:
        raise RuntimeError('Frozen probe script changed')
    module = types.ModuleType('frozen_probe')
    module.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module

def check(package, probe):
    manifest = json.loads((package / 'manifest.json').read_text())
    if (os.geteuid() == 0 or package.resolve() != package.absolute() or
        package.stat().st_mode & 0o777 != 0o700 or package.stat().st_uid != os.getuid() or
        manifest.get('purpose') != 'archiveUnregisteredProbe' or manifest.get('ownerUID') != os.getuid() or
        manifest.get('sessionPath') != str(package) or manifest.get('sourcePath') != str(SOURCE) or
        manifest.get('installedPath') != str(probe.INSTALLED) or manifest.get('hardwareWrites') != [] or
        probe.digest(package / 'session.py') != manifest.get('scriptSHA256') or
        probe.digest(package / 'PLAN.md') != manifest.get('planSHA256') or
        probe.tree(SOURCE) != manifest.get('sourceFilesSHA256')):
        raise RuntimeError('Archive owner/source/script/plan binding changed')
    probe.check(SOURCE)
    cleanup = json.loads((SOURCE / 'cleanup.json').read_text())
    job = json.loads((SOURCE / 'job-after-cleanup.json').read_text())
    if (cleanup.get('diagnostic') is not None or cleanup.get('registration') not in ('notRegistered', 'notFound') or
        job.get('exitCode') != 113 or not (SOURCE / 'cleanup-started.json').is_file() or
        not probe.absent(SOURCE / 'cleanup-completed.json') or not probe.absent(SOURCE / 'retired.bundle')):
        raise RuntimeError('Completed unregister and stopped-before-archive proof required')
    return manifest

def require_gui_exit(probe, seconds=10):
    pid = json.loads((SOURCE / 'gui.json').read_text())['pid']
    if type(pid) is not int or pid <= 0: raise RuntimeError('Invalid saved GUI PID')
    deadline = time.monotonic() + seconds
    while True:
        try: os.kill(pid, 0)  # Existence check only; sends no signal.
        except ProcessLookupError: return
        except PermissionError: raise RuntimeError('GUI exit unknown; preserve state')
        if time.monotonic() >= deadline:
            raise RuntimeError('Probe still running. Quit its app with Command-Q; preserve state')
        time.sleep(0.1)

def prepare(probe):
    proof = json.loads((REPO / 'docs/research/evidence/registration-probe-result.json').read_text())
    if probe.tree(SOURCE) != proof['packageFilesSHA256']: raise RuntimeError('Stopped probe snapshot changed')
    probe.installed_check(SOURCE)
    if not probe.absent(DESTINATION): raise RuntimeError('Archive continuation already exists; no overwrite')
    DESTINATION.mkdir(mode=0o700)
    shutil.copyfile(Path(__file__), DESTINATION / 'session.py')
    shutil.copyfile(PLAN, DESTINATION / 'PLAN.md')
    probe.save(DESTINATION / 'manifest.json', {
        'purpose': 'archiveUnregisteredProbe', 'ownerUID': os.getuid(), 'sessionPath': str(DESTINATION),
        'sourcePath': str(SOURCE), 'installedPath': str(probe.INSTALLED), 'preparedAt': probe.now(),
        'sourceFilesSHA256': probe.tree(SOURCE), 'scriptSHA256': probe.digest(DESTINATION / 'session.py'),
        'planSHA256': probe.digest(DESTINATION / 'PLAN.md'), 'hardwareWrites': []})
    check(DESTINATION, probe)
    print('Prepared archive-only continuation; no native/system actions.')

def finish(package, probe):
    probe.owner_terminal()
    check(package, probe)
    if not probe.absent(package / 'archive-started.json'): raise RuntimeError('Archive already attempted; no retry')
    if not probe.absent(package / 'retired.bundle'): raise RuntimeError('Archive target exists; no overwrite')
    probe.installed_check(SOURCE)
    print((package / 'PLAN.md').read_text(), flush=True)
    answer = input('Завершите только тестовое приложение через Command-Q. Затем введите CLOSED: ')
    if answer != 'CLOSED': raise RuntimeError('Owner cancelled; no system actions')
    require_gui_exit(probe)
    check(package, probe)
    probe.installed_check(SOURCE)
    probe.save(package / 'archive-started.json', {'startedAt': probe.now(), 'hardwareWritesExecuted': 0})
    result = probe.require_success(probe.execute([
        probe.INSTALLED / 'Contents/MacOS/RegistrationProbe', '--probe-status', SOURCE], timeout=10))
    status = json.loads(result.stdout)
    probe.save(package / 'status-before-archive.json', status)
    if (not isinstance(status, dict) or status.get('registration') not in ('notRegistered', 'notFound') or
        status.get('diagnostic') is not None or status.get('hardwareControlAvailable') is not False or
        status.get('hardwareWritesExecuted') != 0):
        raise RuntimeError('Current probe state does not confirm removal; no unregister/retry')
    probe.root_job(package, 'job-before-archive', expected=113)
    check(package, probe)
    probe.installed_check(SOURCE)
    require_gui_exit(probe, seconds=0)
    target = package / 'retired.bundle'
    if not probe.absent(target): raise RuntimeError('Archive target appeared; no overwrite')
    probe.require_success(probe.privileged(['/bin/mv', '-n', probe.INSTALLED, target]))
    seal = json.loads((SOURCE / 'sealed.json').read_text())
    if not probe.absent(probe.INSTALLED) or probe.tree(target) != seal['fingerprint']:
        raise RuntimeError('Exact archival not confirmed; preserve both paths')
    check(package, probe)
    probe.save(package / 'archive-completed.json', {'completedAt': probe.now(),
        'installedProbeAbsent': True, 'archivedExactSignedBundle': True, 'sourceUnchanged': True,
        'fingerprint': probe.tree(target), 'hardwareWritesExecuted': 0})
    print('Probe archive complete. No registration or unregister repeated. Stop and report.')

if __name__ == '__main__':
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ''
        probe = frozen_source()
        if action == 'prepare': prepare(probe)
        elif action == 'finish': finish(Path(__file__).resolve().parent, probe)
        elif action == 'check': check(Path(__file__).resolve().parent, probe); print('Archive bindings match; no native/system actions.')
        else: raise RuntimeError('Use source prepare or frozen check/finish')
    except Exception as error:
        print(f'STOP: {error}. Preserve both sessions; do not repeat run/cleanup/archive.', file=sys.stderr)
        sys.exit(78)
