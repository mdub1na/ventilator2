#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One owner-terminal administrative read, pinned to the completed GUI update."""
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import types
import uuid
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
SOURCE = REPO / '.build/gui-helper-update-owner'
SESSION = REPO / '.build/gui-helper-state-owner'
UPDATE_SCRIPT_SHA256 = '13b45ffde55765a2dafa2320b167b6f2bd9e629b1ac5794e283faf5bc9de4161'
IDENTIFIERS = {'2.dev.ventilator.macos', '16.dev.ventilator.helper'}
FIELDS = {'UUID', 'Name', 'Developer Name', 'Team Identifier', 'Type', 'Flags', 'Disposition',
          'Identifier', 'URL', 'Executable Path', 'Generation', 'Last Use', 'Parent Identifier', 'Bundle Identifier'}
READS = {'launchd': (['/bin/launchctl', 'print', 'system/dev.ventilator.helper'], 5),
         'btm': (['/usr/bin/sfltool', 'dumpbtm'], 20)}

def utilities():
    path = SOURCE / 'session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != UPDATE_SCRIPT_SHA256:
        raise RuntimeError('Completed GUI update script changed')
    module = types.ModuleType('completed_gui_update'); module.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module, module.utilities()

def boot():
    return str(uuid.UUID(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'kern.bootsessionuuid'], text=True, timeout=5).strip()))

def admitted_source(g, u):
    g.check(SOURCE, u)
    result = json.loads((SOURCE / 'result.json').read_text())
    seal = json.loads((SOURCE / 'sealed.json').read_text())
    g.require_root_owned(g.INSTALLED)
    g.identity(result['registration'], seal['fingerprint'])
    if (result.get('outcome') != 'helperNotVerified' or result['registration'].get('registration') != 'enabled' or
        result['registration'].get('error') != 'remoteFailure' or result['registration'].get('helperVerified') is not False or
        result.get('rootJobLoaded') is not False or result.get('readOnlyHelperVerified') is not False or
        result.get('hardwareWritesExecuted') != 0 or result.get('physicalAutoVerified') is not False or
        seal.get('positiveRevocation') is not True or seal['qualification'].get('positiveRevocation') is not True):
        raise RuntimeError('Exact completed GUI failure required; no new service request')
    marker = g.attempt_path(seal)
    meta = marker.lstat()
    if (marker.resolve() != marker.absolute() or not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or
        stat.S_IMODE(meta.st_mode) != 0o600 or json.loads(marker.read_text()) != result.get('guiRegistrationAttempt')):
        raise RuntimeError('Preserved GUI attempt changed')
    return result, seal

def check(package, g, u):
    m = json.loads((package / 'manifest.json').read_text()); meta = package.lstat()
    if (os.geteuid() == 0 or package.resolve() != package.absolute() or not stat.S_ISDIR(meta.st_mode) or
        meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700 or
        m.get('purpose') != 'guiHelperAdministrativeReadOnly' or m.get('ownerUID') != os.getuid() or
        m.get('sessionPath') != str(package) or m.get('sourcePath') != str(SOURCE) or
        m.get('machine') != g.MACHINE or u.machine() != g.MACHINE or m.get('bootUUID') != boot() or
        m.get('hardwareWrites') != [] or m.get('scriptSHA256') != u.digest(package / 'session.py') or
        m.get('planSHA256') != u.digest(package / 'PLAN.md')):
        raise RuntimeError('Owner/boot/plan/script binding changed')
    result, seal = admitted_source(g, u)
    if (u.tree(SOURCE) != m['sourceFilesSHA256'] or u.tree(g.INSTALLED) != m['installedFilesSHA256'] or
        g.gui_files(u) != m['guiFilesSHA256'] or result != m['previousResult'] or seal['fingerprint'] != m['fingerprint']):
        raise RuntimeError('Completed update/installation/GUI history changed')
    return m

def scoped_btm(text):
    records, uid, fields = [], None, {}
    def flush():
        if fields.get('Identifier') in IDENTIFIERS:
            records.append({'uid': uid, 'fields': dict(fields)})
        fields.clear()
    for line in text.splitlines():
        header = re.match(r'\s*Records for UID (-?\d+)\s*:', line)
        if header: flush(); uid = int(header.group(1))
        elif re.fullmatch(r' {0,2}#\d+:\s*', line): flush()
        elif ':' in line:
            key, value = line.strip().split(':', 1)
            if key in FIELDS: fields[key] = value.strip()
    flush()
    return records

def prepare(g, u):
    result, seal = admitted_source(g, u)
    if not u.absent(SESSION): raise RuntimeError('Read-only packet already exists; preserve it')
    SESSION.mkdir(mode=0o700)
    shutil.copyfile(Path(__file__), SESSION / 'session.py')
    shutil.copyfile(REPO / 'docs/gui-helper-state-owner.md', SESSION / 'PLAN.md')
    u.save(SESSION / 'manifest.json', {'purpose': 'guiHelperAdministrativeReadOnly', 'ownerUID': os.getuid(),
        'sessionPath': str(SESSION), 'sourcePath': str(SOURCE), 'preparedAt': u.now(), 'machine': g.MACHINE, 'bootUUID': boot(),
        'sourceFilesSHA256': u.tree(SOURCE), 'installedFilesSHA256': u.tree(g.INSTALLED), 'guiFilesSHA256': g.gui_files(u),
        'previousResult': result, 'fingerprint': seal['fingerprint'], 'scriptSHA256': u.digest(SESSION / 'session.py'),
        'planSHA256': u.digest(SESSION / 'PLAN.md'), 'hardwareWrites': []})
    check(SESSION, g, u)
    print('Prepared one administrative read. No native app invocation or system mutation.')

def collect(package, g, u):
    u.owner_terminal(); m = check(package, g, u)
    if not u.absent(package / 'started.json'): raise RuntimeError('Collection already attempted; preserve state, no retry')
    print((package / 'PLAN.md').read_text(), flush=True)
    print('PLAN SHA-256: ' + m['planSHA256'] + '\nScript SHA-256: ' + m['scriptSHA256'], flush=True)
    u.save(package / 'started.json', {'startedAt': u.now(), 'hardwareWritesExecuted': 0})
    steps, stopped, integrity_error = {}, None, None
    for name, (argv, alarm) in READS.items():
        print('Read-only ' + name + ': authenticate sudo in this Terminal if prompted.', flush=True)
        try:
            r = u.privileged(argv, alarm=alarm)
            step = {'exitCode': r.returncode, 'completedAt': u.now(), 'alarmExpired': r.returncode in (-14, 142)}
            if name == 'btm':
                step.update({'records': scoped_btm(r.stdout), 'complete': r.returncode == 0,
                    'formatRecognized': bool(re.search(r'Records for UID -?\d+\s*:', r.stdout)), 'rawOtherApplicationsSaved': False})
            else: step['stdout'] = r.stdout
        except subprocess.TimeoutExpired:
            step = {'exitCode': None, 'completedAt': u.now(), 'authenticationOrReadTimeout': True}
        steps[name] = step; u.save(package / (name + '.json'), step)
        if step['exitCode'] not in ((0, 113) if name == 'launchd' else (0,)) or (name == 'btm' and not step['formatRecognized']):
            stopped = name; break
        try: check(package, g, u)
        except RuntimeError as error:
            stopped = 'integrity'; integrity_error = str(error); break
    try: check(package, g, u)
    except RuntimeError as error: stopped = 'integrity'; integrity_error = str(error)
    job = steps['launchd']['exitCode']
    outcome = 'diagnosticIncomplete' if stopped else 'rootJobAbsent' if job == 113 else 'rootPeerUnverified'
    u.save(package / 'result.json', {'completedAt': u.now(), 'steps': steps, 'stoppedAt': stopped, 'integrityError': integrity_error,
        'outcome': outcome, 'rootJobLoaded': job == 0 if job in (0, 113) else None, 'registrationStatus': None,
        'previousGUIUpdateResult': m['previousResult'], 'nativeVerificationAttempted': False, 'helperVerified': False,
        'hardwareWritesExecuted': 0, 'physicalAutoVerified': False})
    print('Saved administrative snapshot: ' + outcome + '. Stop and report; do not repeat collection/update/register/ready.')

if __name__ == '__main__':
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ''
        g, u = utilities()
        if action == 'prepare': prepare(g, u)
        elif action == 'check': check(Path(__file__).resolve().parent, g, u); print('Pinned read-only packet matches; no system actions.')
        elif action == 'collect': collect(Path(__file__).resolve().parent, g, u)
        else: raise RuntimeError('Use source prepare or frozen check/collect')
    except Exception as error:
        print('STOP: ' + str(error) + '. Preserve all packages; do not repeat collection/update/register/ready.', file=sys.stderr)
        sys.exit(78)
