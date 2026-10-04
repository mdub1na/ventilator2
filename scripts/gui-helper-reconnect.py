#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compose the preserved GUI update with one explicit owner OFF admission."""
import builtins
import hashlib
import json
import os
import shutil
import subprocess
import sys
import types
import uuid
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
SOURCE = REPO / '.build/gui-helper-update-owner'
READ = REPO / '.build/gui-helper-state-owner'
SESSION = REPO / '.build/gui-helper-reconnect-owner'
STAGE = Path('/Applications/Ventilator-reconnect-staging.app')
SEQUENCE = 'mainAppIsolationWithGuardedOFFRemovalAndGUIRegister'
BASE_SHA256 = '13b45ffde55765a2dafa2320b167b6f2bd9e629b1ac5794e283faf5bc9de4161'

def utilities():
    path = SOURCE / 'session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != BASE_SHA256: raise RuntimeError('Preserved GUI update changed')
    g = types.ModuleType('preserved_gui_update'); g.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), g.__dict__)
    return g, g.utilities()

def boot():
    return str(uuid.UUID(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'kern.bootsessionuuid'], text=True, timeout=5).strip()))

def check(package, g, u, base_check=None):
    m = (base_check or g.check)(package, u)
    if m.get('sequence') != SEQUENCE or m.get('bootUUID') != boot(): raise RuntimeError('Reconnect sequence/boot changed')
    return m

def prepare(g, u):
    original = g.check(SOURCE, u); g.require_root_owned(g.INSTALLED)
    read = json.loads((READ / 'result.json').read_text())
    read_manifest = json.loads((READ / 'manifest.json').read_text())
    read_evidence = json.loads((REPO / 'docs/research/evidence/gui-helper-state-result.json').read_text())
    source_result = json.loads((SOURCE / 'result.json').read_text())
    source_seal = json.loads((SOURCE / 'sealed.json').read_text())
    if (read.get('outcome') != 'rootJobAbsent' or read.get('stoppedAt') is not None or read.get('integrityError') is not None or
        read.get('rootJobLoaded') is not False or read.get('nativeVerificationAttempted') is not False or
        read.get('hardwareWritesExecuted') != 0 or read.get('previousGUIUpdateResult') != source_result or
        read['steps']['launchd'].get('exitCode') != 113 or read['steps']['btm'].get('complete') is not True or
        read['steps']['btm'].get('formatRecognized') is not True or read_manifest.get('bootUUID') != boot() or
        u.tree(READ) != read_evidence['packageFilesSHA256'] or u.tree(SOURCE) != read_manifest['sourceFilesSHA256'] or
        u.tree(g.INSTALLED) != source_seal['filesSHA256'] or source_seal.get('positiveRevocation') is not True):
        raise RuntimeError('Completed exact administrative read and signed installation required')
    source_check = json.loads((REPO / 'docs/research/evidence/mainapp-status-isolation.json').read_text())
    if ('SMAppService.mainApp' in (REPO / 'Sources/Ventilator/MonitorStore.swift').read_text() or
        u.tree(REPO / '.build/Ventilator.app') != source_check['adHocBundleFilesSHA256']):
        raise RuntimeError('Checked startup-isolated payload required')
    if not u.absent(SESSION) or not u.absent(STAGE): raise RuntimeError('Reconnect/staging already exists; preserve state')
    protected = dict(original['protectedFilesSHA256'])
    protected.update({str(SOURCE): u.tree(SOURCE), str(READ): u.tree(READ)})
    SESSION.mkdir(mode=0o700)
    shutil.copytree(REPO / '.build/Ventilator.app', SESSION / 'payload.app')
    shutil.copyfile(Path(__file__), SESSION / 'session.py')
    shutil.copyfile(REPO / 'docs/gui-helper-reconnect-owner.md', SESSION / 'PLAN.md')
    g.STAGE = STAGE
    u.save(SESSION / 'manifest.json', {'purpose': 'guiHelperReadOnlyUpdate', 'sequence': SEQUENCE, 'ownerUID': os.getuid(),
        'sessionPath': str(SESSION), 'preparedAt': u.now(), 'machine': g.MACHINE, 'bootUUID': boot(),
        'certificate': g.CERTIFICATE, 'team': g.TEAM, 'installedPath': str(g.INSTALLED), 'stagePath': str(STAGE),
        'guiRoot': str(g.GUI_ROOT), 'previousGUIFilesSHA256': g.gui_files(u), 'protectedFilesSHA256': protected,
        'previousInstalledFilesSHA256': u.tree(g.INSTALLED), 'previousFingerprint': g.fingerprint(g.INSTALLED, u),
        'payloadFilesSHA256': u.tree(SESSION / 'payload.app'), 'scriptSHA256': u.digest(SESSION / 'session.py'),
        'planSHA256': u.digest(SESSION / 'PLAN.md'), 'hardwareWrites': []})
    check(SESSION, g, u)
    print('Prepared one guarded reconnect. No signing, permission change, service mutation or hardware action.')

def reconnect(package, g, u):
    original_check, original_execute = g.check, u.execute
    owner_input = builtins.input
    off_done = False
    g.STAGE = STAGE
    def guarded_check(p, utils): return check(p, g, utils, original_check)
    def execute(argv, timeout=30):
        nonlocal off_done
        if list(argv) == [g.INSTALLED / 'Contents/MacOS/Ventilator', '--unregister-helper']:
            if not off_done or not (package / 'owner-off.json').is_file(): raise RuntimeError('Old removal without confirmed OFF refused')
            guarded_check(package, u)
            g.root_job(package, 'job-before-old-unregister', u, absent=True)
            guarded_check(package, u)
        if not off_done and list(argv) == [g.INSTALLED / 'Contents/MacOS/Ventilator', '--helper-status']:
            if not (package / 'sealed.json').is_file() or not (package / 'stage-inspected.json').is_file():
                raise RuntimeError('OFF admission attempted before signature/staging qualification')
            guarded_check(package, u)
            g.root_job(package, 'job-before-owner-off', u, absent=True)
            guarded_check(package, u)
            print('В настройках macOS выключите только фоновую активность Ventilator. Если записи нет или это невозможно, отмените. Установленное приложение уже закрыто.', flush=True)
            if owner_input('Введите OFF после выключения; другое отменяет: ') != 'OFF': raise RuntimeError('Owner cancelled before old service removal')
            u.save(package / 'owner-off.json', {'reportedAt': u.now(), 'action': 'OFF', 'hardwareWritesExecuted': 0})
            guarded_check(package, u)
            r = original_execute(argv, timeout=timeout)
            value = json.loads(u.require_success(r).stdout)
            if value.get('registration') not in ('requiresApproval', 'notRegistered', 'notFound') or value.get('error') != 'serviceNotEnabled' or value.get('helperVerified') is not False:
                raise RuntimeError('OFF not confirmed by actual framework state; preserve installation, no removal')
            off_done = True
            return r
        return original_execute(argv, timeout=timeout)
    def gui_input(prompt):
        if prompt.startswith('В новом окне'):
            print('В новом окне нажмите «Подключить помощник» один раз, если кнопка включена. Затем включите только Ventilator в фоновой активности. Подтвердите системное Allow/admin, если macOS покажет запрос.', flush=True)
            return owner_input('ALLOW после Allow/admin подтверждения и включения; NONE если запроса нет и Ventilator включён; другое отменяет: ')
        return owner_input(prompt)
    try:
        g.check = guarded_check; u.execute = execute; g.input = gui_input
        g.run(package, u)
    finally:
        g.check = original_check; u.execute = original_execute
        del g.input

if __name__ == '__main__':
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ''
        g, u = utilities()
        if action == 'prepare': prepare(g, u)
        elif action == 'check':
            g.STAGE = STAGE; check(Path(__file__).resolve().parent, g, u); print('Pinned reconnect matches; no native/system actions.')
        elif action == 'reconnect': reconnect(Path(__file__).resolve().parent, g, u)
        else: raise RuntimeError('Use source prepare or frozen check/reconnect')
    except Exception as error:
        print('STOP: ' + str(error) + '. Preserve every package/path; do not repeat reconnect/update/register/ready.', file=sys.stderr)
        sys.exit(78)
