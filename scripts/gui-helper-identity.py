#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Use a fresh identity through standard GUI consent; preserve the retired package."""
import builtins
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import types
import uuid
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
SOURCE = REPO / '.build/gui-helper-update-owner'
ENABLE = REPO / '.build/gui-helper-enable-owner'
SESSION = REPO / '.build/gui-helper-identity-owner'
STAGE = Path('/Applications/Ventilator-identity-staging.app')
BASE_SHA256 = '13b45ffde55765a2dafa2320b167b6f2bd9e629b1ac5794e283faf5bc9de4161'
SEQUENCE = 'freshIdentityWithScopedLegacyRemoval'
IDENTITIES = {'previousApplication': 'dev.ventilator.macos', 'previousHelper': 'dev.ventilator.helper',
              'application': 'dev.ventilator.app', 'helper': 'dev.ventilator.app.helper'}
PLIST = 'Contents/Library/LaunchDaemons/dev.ventilator.app.helper.plist'

def utilities():
    path = SOURCE / 'session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != BASE_SHA256:
        raise RuntimeError('Preserved GUI update changed')
    g = types.ModuleType('preserved_gui_update'); g.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), g.__dict__)
    return g, g.utilities()

def boot():
    return str(uuid.UUID(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'kern.bootsessionuuid'], text=True, timeout=5).strip()))

def fingerprint(bundle, u):
    return {k: u.digest(bundle / v) for k, v in {'applicationSHA256': 'Contents/MacOS/Ventilator',
        'helperSHA256': 'Contents/MacOS/VentilatorHelper', 'launchDaemonSHA256': PLIST}.items()}

def configure(g):
    g.STAGE = STAGE; g.DAEMON = IDENTITIES['helper']; g.fingerprint = fingerprint

def check(package, g, u, base_check=None):
    m = (base_check or g.check)(package, u)
    if m.get('sequence') != SEQUENCE or m.get('identities') != IDENTITIES or m.get('bootUUID') != boot():
        raise RuntimeError('Identity sequence/boot binding changed')
    return m

def prepare(g, u):
    evidence = json.loads((REPO / 'docs/research/evidence/gui-helper-enable-result.json').read_text())
    previous = json.loads((ENABLE / 'manifest.json').read_text())
    result = json.loads((ENABLE / 'result.json').read_text())
    source = json.loads((REPO / 'docs/research/evidence/helper-identity-source-preparation.json').read_text())
    if (u.tree(ENABLE) != evidence['completedFilesSHA256'] or result.get('outcome') != 'systemApprovalPending' or
        result.get('hardwareWritesExecuted') != 0 or result.get('fingerprintBound') is not True or
        result.get('readOnlyHelperVerified') is not False or result['registration'].get('registration') != 'requiresApproval' or
        result['registration'].get('fingerprint') != previous['fingerprint'] or
        previous['qualification'].get('positiveRevocation') is not True or previous.get('bootUUID') != boot() or
        u.machine() != g.MACHINE or not u.absent(g.RUNTIME) or
        u.tree(g.INSTALLED) != previous['installedFilesSHA256'] or g.gui_files(u) != previous['guiFilesSHA256'] or
        u.tree(REPO / '.build/Ventilator.app') != source['adHocBundleFilesSHA256']):
        raise RuntimeError('Completed ON verification and exact checked source required')
    g.require_root_owned(g.INSTALLED)
    payload = REPO / '.build/Ventilator.app'
    info = plistlib.loads((payload / 'Contents/Info.plist').read_bytes())
    launch = plistlib.loads((payload / PLIST).read_bytes())
    if (info.get('CFBundleIdentifier') != IDENTITIES['application'] or launch.get('Label') != IDENTITIES['helper'] or
        launch.get('MachServices') != {IDENTITIES['helper']: True} or
        set(p.name for p in (payload / PLIST).parent.iterdir()) != {Path(PLIST).name}):
        raise RuntimeError('Fresh app/helper layout required')
    roots = dict(previous['protectedFilesSHA256']); roots[str(ENABLE)] = u.tree(ENABLE)
    for path, expected in roots.items():
        if u.tree(Path(path)) != expected: raise RuntimeError('Protected preparation source changed')
    if not u.absent(SESSION) or not u.absent(STAGE): raise RuntimeError('Identity package/staging already exists')
    SESSION.mkdir(mode=0o700)
    shutil.copytree(payload, SESSION / 'payload.app')
    shutil.copyfile(Path(__file__), SESSION / 'session.py')
    shutil.copyfile(REPO / 'docs/gui-helper-identity-owner.md', SESSION / 'PLAN.md')
    configure(g)
    u.save(SESSION / 'manifest.json', {'purpose': 'guiHelperReadOnlyUpdate', 'sequence': SEQUENCE, 'identities': IDENTITIES,
        'ownerUID': os.getuid(), 'sessionPath': str(SESSION), 'preparedAt': u.now(), 'machine': g.MACHINE, 'bootUUID': boot(),
        'certificate': g.CERTIFICATE, 'team': g.TEAM, 'installedPath': str(g.INSTALLED), 'stagePath': str(STAGE),
        'guiRoot': str(g.GUI_ROOT), 'previousGUIFilesSHA256': g.gui_files(u), 'protectedFilesSHA256': roots,
        'previousInstalledFilesSHA256': u.tree(g.INSTALLED), 'previousFingerprint': previous['fingerprint'],
        'payloadFilesSHA256': u.tree(SESSION / 'payload.app'), 'scriptSHA256': u.digest(SESSION / 'session.py'),
        'planSHA256': u.digest(SESSION / 'PLAN.md'), 'hardwareWrites': []})
    check(SESSION, g, u)
    print('Prepared one fresh-identity GUI session. No signing, registration or system mutations.')

def run(package, g, u):
    original_check, original_execute, original_job = g.check, u.execute, g.root_job
    owner_input = builtins.input
    configure(g)
    old_checked = False
    def guarded_check(p, utils): return check(p, g, utils, original_check)
    def root_job(p, name, utils, absent=False):
        if name in ('job-before-removal', 'job-after-removal', 'job-immediately-before-unregister'):
            label, absent = IDENTITIES['previousHelper'], True
        elif name == 'new-job-before-removal': label, absent = IDENTITIES['helper'], True
        elif name == 'job-after-gui': label = IDENTITIES['helper']
        else: raise RuntimeError('Unplanned system job read')
        r = utils.privileged(['/bin/launchctl', 'print', 'system/' + label], alarm=5)
        utils.save(p / (name + '.json'), {'observedAt': utils.now(), 'serviceIdentifier': label,
            'exitCode': r.returncode, 'stdout': r.stdout, 'stderr': r.stderr})
        if r.returncode not in (0, 113) or (absent and r.returncode != 113):
            raise RuntimeError('Unknown/present system job; preserve state')
        return r.returncode
    def execute(argv, timeout=30):
        nonlocal old_checked
        status = list(argv) == [g.INSTALLED / 'Contents/MacOS/Ventilator', '--helper-status']
        if status and not (package / 'replacement-completed.json').is_file():
            if old_checked or not (package / 'sealed.json').is_file() or not (package / 'stage-inspected.json').is_file():
                raise RuntimeError('Old status requires completed signature and staging')
            guarded_check(package, u); root_job(package, 'new-job-before-removal', u)
            guarded_check(package, u)
            r = original_execute(argv, timeout=timeout)
            value = json.loads(u.require_success(r).stdout)
            if (value.get('registration') not in ('requiresApproval', 'notRegistered', 'notFound') or
                value.get('error') != 'serviceNotEnabled' or value.get('helperVerified') is not False):
                raise RuntimeError('Previous helper no longer pending/unregistered; no removal')
            old_checked = True
            return r
        if list(argv) == [g.INSTALLED / 'Contents/MacOS/Ventilator', '--unregister-helper']:
            if not old_checked: raise RuntimeError('Old state not checked')
            guarded_check(package, u); root_job(package, 'job-immediately-before-unregister', u)
            guarded_check(package, u)
        if status and (package / 'replacement-completed.json').is_file():
            if not (package / 'owner-on.json').is_file(): raise RuntimeError('Explicit owner ON required')
            seal = json.loads((package / 'sealed.json').read_text()); marker = g.attempt_path(seal)
            if u.absent(marker): raise RuntimeError('No actual new GUI registration attempt; preserve state')
            meta = marker.lstat(); attempt = json.loads(marker.read_text())
            if (not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600 or
                attempt.get('ownerUID') != os.getuid() or attempt.get('fingerprint') != seal['fingerprint']):
                raise RuntimeError('New GUI marker binding changed')
        return original_execute(argv, timeout=timeout)
    def gui_input(prompt):
        if not prompt.startswith('В новом окне'): return owner_input(prompt)
        print('В новом окне нажмите «Подключить помощник» один раз, если кнопка включена.', flush=True)
        if owner_input('После нажатия введите CONNECTED; если действие невозможно — CANCEL: ') != 'CONNECTED':
            raise RuntimeError('Owner cancelled GUI connection')
        print('Включите только новую запись Ventilator в фоновой активности. Уже включённую оставьте ON. Если macOS покажет Background Items Added, выберите Allow и подтвердите администратора.', flush=True)
        if owner_input('После проверки включённой фоновой активности введите ON; иначе CANCEL: ') != 'ON':
            raise RuntimeError('Owner ON not confirmed')
        u.save(package / 'owner-on.json', {'reportedAt': u.now(), 'ownerReportedON': True, 'hardwareWritesExecuted': 0})
        return owner_input('ALLOW только после настоящего Allow/admin; NONE если запроса не было; другое отменяет: ')
    try:
        g.check = guarded_check; g.root_job = root_job; u.execute = execute; g.input = gui_input
        g.run(package, u)
    finally:
        g.check = original_check; g.root_job = original_job; u.execute = original_execute
        del g.input

if __name__ == '__main__':
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ''
        g, u = utilities()
        if action == 'prepare': prepare(g, u)
        elif action == 'check':
            configure(g); check(Path(__file__).resolve().parent, g, u); print('Pinned identity package matches; no native/system actions.')
        elif action == 'run': run(Path(__file__).resolve().parent, g, u)
        else: raise RuntimeError('Use source prepare or frozen check/run')
    except Exception as error:
        print('STOP: ' + str(error) + '. Preserve every package/path; do not repeat run/update/register/ready.', file=sys.stderr)
        sys.exit(78)
