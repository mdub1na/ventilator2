#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One owner-run diagnostic update; registration happens only in the installed GUI."""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import time
import types
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
SOURCE = REPO / '.build/registration-probe-owner'
SESSION = REPO / '.build/gui-helper-update-owner'
INSTALLED = Path('/Applications/Ventilator.app')
STAGE = Path('/Applications/Ventilator-gui-staging.app')
RUNTIME = Path('/Library/Application Support/Ventilator')
GUI_ROOT = Path.home() / 'Library/Application Support/Ventilator/Helper Setup'
DAEMON = 'dev.ventilator.helper'
MACHINE = {'model': 'Mac15,7', 'version': '27.0.1', 'build': '26A434'}
CERTIFICATE = '4895C06FF7407EAF5F350E78CF23D0B41AD466C9'
TEAM = '4659S5GD6X'

def utilities():
    path = SOURCE / 'session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != '08b0666e17ab81b3c2329d720afb25a7310bf176686996530616688ade37f139':
        raise RuntimeError('Preserved diagnostic utilities changed')
    module = types.ModuleType('preserved_utilities'); module.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module

def fingerprint(bundle, u):
    return {key: u.digest(bundle / name) for key, name in {
        'applicationSHA256': 'Contents/MacOS/Ventilator', 'helperSHA256': 'Contents/MacOS/VentilatorHelper',
        'launchDaemonSHA256': 'Contents/Library/LaunchDaemons/dev.ventilator.helper.plist'}.items()}

def private_directory(path, u):
    if u.absent(path): return
    meta = path.lstat()
    if path.resolve() != path.absolute() or not stat.S_ISDIR(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700:
        raise RuntimeError('Private unaliased owner GUI directory required')

def gui_files(u):
    private_directory(GUI_ROOT.parent, u); private_directory(GUI_ROOT, u)
    return u.tree(GUI_ROOT) if not u.absent(GUI_ROOT) else {}

def attempt_path(seal):
    f = seal['fingerprint']
    return GUI_ROOT / ('-'.join(f[k] for k in ('applicationSHA256', 'helperSHA256', 'launchDaemonSHA256')) + '.json')

def signed_files(package):
    for name in ('sealed.json', 'signature-ready.json'):
        if (package / name).is_file(): return json.loads((package / name).read_text())['filesSHA256']
    return json.loads((package / 'manifest.json').read_text())['payloadFilesSHA256']

def check(package, u):
    m = json.loads((package / 'manifest.json').read_text())
    meta = package.lstat()
    if (os.geteuid() == 0 or package.resolve() != package.absolute() or not stat.S_ISDIR(meta.st_mode) or
        meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700 or m.get('purpose') != 'guiHelperReadOnlyUpdate' or
        m.get('ownerUID') != os.getuid() or m.get('sessionPath') != str(package) or m.get('machine') != MACHINE or
        u.machine() != MACHINE or m.get('certificate') != CERTIFICATE or m.get('team') != TEAM or
        m.get('installedPath') != str(INSTALLED) or m.get('stagePath') != str(STAGE) or m.get('guiRoot') != str(GUI_ROOT) or
        m.get('hardwareWrites') != [] or u.digest(package / 'session.py') != m.get('scriptSHA256') or
        u.digest(package / 'PLAN.md') != m.get('planSHA256') or not u.absent(RUNTIME)):
        raise RuntimeError('Owner/machine/plan/script/runtime binding changed')
    for path, expected in m['protectedFilesSHA256'].items():
        if u.tree(Path(path)) != expected: raise RuntimeError('Protected package changed: ' + path)
    if u.tree(package / 'payload.app') != signed_files(package): raise RuntimeError('Update payload changed')
    backup = package / 'previous-installed.bundle'
    if u.absent(backup):
        if u.tree(INSTALLED) != m['previousInstalledFilesSHA256']: raise RuntimeError('Previous installation changed')
    else:
        if u.tree(backup) != m['previousInstalledFilesSHA256']: raise RuntimeError('Preserved previous installation changed')
        if not u.absent(INSTALLED) and u.tree(INSTALLED) != signed_files(package): raise RuntimeError('New installation changed')
    if not u.absent(STAGE) and u.tree(STAGE) != signed_files(package): raise RuntimeError('Staging changed; preserve partial copy')
    current = gui_files(u)
    if (package / 'gui-open-started.json').is_file():
        seal = json.loads((package / 'sealed.json').read_text())
        current.pop(attempt_path(seal).name, None)
    if current != m['previousGUIFilesSHA256']: raise RuntimeError('Previous GUI attempt files changed')
    return m

def report(u, argv, timeout=10):
    value = json.loads(u.require_success(u.execute(argv, timeout=timeout)).stdout)
    if not isinstance(value, dict): raise RuntimeError('Malformed native report')
    return value

def identity(value, expected, *, registration=None, installed=True):
    if (not all(value.get(k) is True for k in ('trustedBundle', 'rootOwned')) or value.get('installedLocation') is not installed or
        value.get('fingerprint') != expected or value.get('hardwareControlAvailable') is not False):
        raise RuntimeError('Exact installed signature/ownership report required')
    if registration is not None and (value.get('registration') != registration or value.get('error') is not None or value.get('helperVerified') is not False):
        raise RuntimeError('Static inspection queried service or rejected files')

def root_job(package, name, u, absent=False):
    r = u.privileged(['/bin/launchctl', 'print', 'system/' + DAEMON], alarm=5)
    u.save(package / (name + '.json'), {'observedAt': u.now(), 'exitCode': r.returncode, 'stdout': r.stdout, 'stderr': r.stderr})
    if r.returncode not in (0, 113) or (absent and r.returncode != 113): raise RuntimeError('Unknown/present system job; preserve state')
    return r.returncode

def require_root_owned(bundle):
    for path in [bundle, *bundle.rglob('*')]:
        meta = path.lstat()
        if path.resolve() != path.absolute() or meta.st_uid != 0 or meta.st_mode & 0o022 or stat.S_ISLNK(meta.st_mode):
            raise RuntimeError('Root-owned unaliased bundle required')

def require_app_exit(u, seconds=10):
    deadline = time.monotonic() + seconds
    while True:
        listing = u.require_success(u.execute(['/bin/ps', '-axww', '-o', 'pid=,command='], timeout=5)).stdout
        binary = str(INSTALLED / 'Contents/MacOS/Ventilator')
        found = any(len(line.strip().split(None, 1)) == 2 and line.strip().split(None, 1)[1].split(' ', 1)[0] == binary for line in listing.splitlines())
        if not found: return
        if time.monotonic() >= deadline: raise RuntimeError('Installed Ventilator is still running; use Command-Q, preserve state')
        time.sleep(0.1)

def prepare(u):
    original = json.loads((SOURCE / 'manifest.json').read_text())
    archive = json.loads((REPO / 'docs/research/evidence/registration-probe-archive-result.json').read_text())
    roots = {path: hashes for path, hashes in original['protectedFilesSHA256'].items() if path != str(INSTALLED)}
    roots[str(SOURCE)] = archive['sourceFilesSHA256']
    roots[str(REPO / '.build/registration-probe-archive-owner')] = archive['archiveFilesSHA256']
    for path, hashes in roots.items():
        if u.tree(Path(path)) != hashes: raise RuntimeError('Protected preparation source changed')
    if (os.geteuid() == 0 or u.machine() != MACHINE or not u.absent(SESSION) or not u.absent(STAGE) or not u.absent(RUNTIME) or
        u.tree(INSTALLED) != original['protectedFilesSHA256'][str(INSTALLED)]): raise RuntimeError('Pinned unchanged read-only installation required')
    previous_gui = gui_files(u)
    SESSION.mkdir(mode=0o700)
    shutil.copytree(REPO / '.build/Ventilator.app', SESSION / 'payload.app')
    shutil.copyfile(Path(__file__), SESSION / 'session.py')
    shutil.copyfile(REPO / 'docs/gui-helper-owner-update.md', SESSION / 'PLAN.md')
    u.save(SESSION / 'manifest.json', {'purpose': 'guiHelperReadOnlyUpdate', 'ownerUID': os.getuid(), 'sessionPath': str(SESSION),
        'preparedAt': u.now(), 'machine': MACHINE, 'certificate': CERTIFICATE, 'team': TEAM, 'installedPath': str(INSTALLED), 'stagePath': str(STAGE),
        'guiRoot': str(GUI_ROOT), 'previousGUIFilesSHA256': previous_gui, 'protectedFilesSHA256': roots,
        'previousInstalledFilesSHA256': u.tree(INSTALLED), 'previousFingerprint': fingerprint(INSTALLED, u),
        'payloadFilesSHA256': u.tree(SESSION / 'payload.app'), 'scriptSHA256': u.digest(SESSION / 'session.py'),
        'planSHA256': u.digest(SESSION / 'PLAN.md'), 'hardwareWrites': []})
    check(SESSION, u)
    print('Prepared one diagnostic GUI update. No signing, native invocation, registration or system mutations.')

def run(package, u):
    u.owner_terminal(); m = check(package, u)
    if not u.absent(package / 'run-started.json') or not u.absent(STAGE) or not u.absent(package / 'previous-installed.bundle'):
        raise RuntimeError('Update already attempted/staged; no retry')
    print((package / 'PLAN.md').read_text(), flush=True)
    if input('Завершите обычный Ventilator через Command-Q, затем введите CLOSED: ') != 'CLOSED': raise RuntimeError('Owner cancelled before signing/system actions')
    require_app_exit(u); check(package, u)
    u.save(package / 'run-started.json', {'startedAt': u.now(), 'hardwareWritesExecuted': 0})
    app = package / 'payload.app'; binary = app / 'Contents/MacOS/Ventilator'
    for path, extra in [(app / 'Contents/MacOS/VentilatorHelper', ['--identifier', DAEMON]), (app, [])]:
        print('Signing ' + path.name + '; Keychain may request owner authentication.', flush=True)
        r = u.require_success(u.execute(['/usr/bin/codesign', '--force', '--sign', CERTIFICATE, '--options', 'runtime', '--timestamp=none', *extra, path], timeout=180))
        print(r.stderr.strip(), flush=True)
    inspected = report(u, [binary, '--inspect-signed-bundle', app])
    if inspected.get('trustedBundle') is not True or inspected.get('registration') != 'notQueried' or inspected.get('error') is not None:
        raise RuntimeError('Signed payload inspection failed')
    ready = {'filesSHA256': u.tree(app), 'fingerprint': fingerprint(app, u)}
    if inspected.get('fingerprint') != ready['fingerprint']: raise RuntimeError('Signed inspection fingerprint mismatch')
    u.save(package / 'signature-ready.json', ready)
    qualified = report(u, [binary, '--qualify-owner-signature', app, CERTIFICATE], timeout=30)
    if (qualified.get('certificateSHA1') != CERTIFICATE or qualified.get('teamIdentifier') != TEAM or
        qualified.get('positiveRevocation') is not True or qualified.get('fingerprint') != ready['fingerprint'] or
        u.tree(app) != ready['filesSHA256']): raise RuntimeError('Positive certificate qualification required')
    seal = {**ready, 'qualification': qualified, 'positiveRevocation': True}
    u.save(package / 'sealed.json', seal); check(package, u)
    print('Qualified signed hashes: ' + json.dumps(ready['fingerprint']), flush=True)
    if not u.absent(attempt_path(seal)): raise RuntimeError('GUI attempt for this signed fingerprint already exists')
    u.save(package / 'stage-started.json', {'fingerprint': ready['fingerprint']})
    for argv in [ ['/bin/mkdir', '-m', '755', STAGE], ['/usr/bin/ditto', app, STAGE],
                  ['/usr/sbin/chown', '-R', 'root:wheel', STAGE], ['/bin/chmod', '-R', 'go-w', STAGE] ]:
        u.require_success(u.privileged(argv))
    require_root_owned(STAGE); check(package, u)
    stage_report = report(u, [binary, '--inspect-signed-bundle', STAGE])
    identity(stage_report, ready['fingerprint'], registration='notQueried', installed=False)
    u.save(package / 'stage-inspected.json', stage_report)
    require_app_exit(u, seconds=0); check(package, u)
    old = report(u, [INSTALLED / 'Contents/MacOS/Ventilator', '--helper-status'])
    identity(old, m['previousFingerprint'])
    if old.get('registration') not in ('notRegistered', 'notFound', 'requiresApproval', 'enabled'):
        raise RuntimeError('Unknown previous framework state')
    if old['registration'] == 'enabled' and (old.get('helperVerified') is not True or old.get('error') is not None):
        raise RuntimeError('Enabled previous peer is not verified; preserve state')
    root_job(package, 'job-before-removal', u)
    check(package, u)
    u.save(package / 'removal-started.json', old)
    if old['registration'] in ('requiresApproval', 'enabled'):
        removed = report(u, [INSTALLED / 'Contents/MacOS/Ventilator', '--unregister-helper'])
        identity(removed, m['previousFingerprint'])
        if removed.get('registration') != 'notRegistered': raise RuntimeError('Unregister incomplete; no replacement')
    else: removed = old
    u.save(package / 'removal-completed.json', removed)
    root_job(package, 'job-after-removal', u, absent=True)
    check(package, u); require_app_exit(u, seconds=0)
    u.save(package / 'replacement-started.json', {'fingerprint': ready['fingerprint']})
    backup = package / 'previous-installed.bundle'
    if not u.absent(backup): raise RuntimeError('Backup target appeared')
    u.require_success(u.privileged(['/bin/mv', '-n', INSTALLED, backup]))
    if not u.absent(INSTALLED) or u.tree(backup) != m['previousInstalledFilesSHA256']: raise RuntimeError('Previous archival incomplete')
    u.require_success(u.privileged(['/bin/mv', '-n', STAGE, INSTALLED]))
    if not u.absent(STAGE) or u.tree(INSTALLED) != ready['filesSHA256']: raise RuntimeError('Replacement incomplete')
    require_root_owned(INSTALLED); check(package, u)
    new_inspection = report(u, [binary, '--inspect-signed-bundle', INSTALLED])
    identity(new_inspection, ready['fingerprint'], registration='notQueried')
    u.save(package / 'replacement-completed.json', new_inspection)
    u.save(package / 'gui-open-started.json', {'fingerprint': ready['fingerprint']})
    u.require_success(u.execute(['/usr/bin/open', '-n', '-a', INSTALLED, '--args', '--show-helper-setup'], timeout=10))
    answer = input('В новом окне нажмите Подключить помощник один раз, если кнопка включена. ALLOW после системного Allow/admin; NONE если запроса нет; другое отменяет: ')
    if answer not in ('ALLOW', 'NONE'): raise RuntimeError('Owner cancelled; installed copy and markers preserved')
    check(package, u)
    marker = attempt_path(seal); attempt = None
    if not u.absent(marker):
        meta = marker.lstat()
        if not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600: raise RuntimeError('Unsafe GUI attempt file')
        attempt = json.loads(marker.read_text())
        if (not isinstance(attempt, dict) or attempt.get('ownerUID') != os.getuid() or attempt.get('fingerprint') != ready['fingerprint'] or
            type(attempt.get('pid')) is not int or attempt['pid'] <= 0): raise RuntimeError('GUI attempt binding mismatch')
    native = report(u, [INSTALLED / 'Contents/MacOS/Ventilator', '--helper-status'])
    identity(native, ready['fingerprint'])
    if native.get('registration') not in ('notRegistered', 'notFound', 'requiresApproval', 'enabled'): raise RuntimeError('Unknown new framework state')
    job = root_job(package, 'job-after-gui', u)
    peer = native.get('registration') == 'enabled' and native.get('helperVerified') is True and native.get('error') is None and job == 0
    hardware = None
    if peer:
        hardware = report(u, [INSTALLED / 'Contents/MacOS/Ventilator', '--owner-experiment-status'])
        if hardware.get('hardwareControlAvailable') is not False or hardware.get('hardwareExperiment') is not None or hardware.get('errorCode') not in ('unsupportedMachine', 'failed("unsupportedMachine")'):
            raise RuntimeError('Unsupported-profile hardware denial not confirmed')
    check(package, u)
    value = {'completedAt': u.now(), 'ownerActionReported': answer, 'guiRegistrationAttempt': attempt,
        'registration': native, 'rootJobLoaded': job == 0, 'readOnlyHelperVerified': peer, 'hardwareStatus': hardware,
        'hardwareWritesExecuted': 0, 'physicalAutoVerified': False,
        'outcome': 'readOnlyHelperVerified' if peer else 'systemApprovalPending' if native['registration'] == 'requiresApproval' else 'helperNotVerified'}
    u.save(package / 'result.json', value)
    print('Saved GUI helper update: ' + value['outcome'] + '. Stop and report; no retry or hardware experiment.')

if __name__ == '__main__':
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ''
        u = utilities()
        if action == 'prepare': prepare(u)
        elif action == 'run': run(Path(__file__).resolve().parent, u)
        elif action == 'check': check(Path(__file__).resolve().parent, u); print('Pinned GUI update matches; no native/system actions.')
        else: raise RuntimeError('Use source prepare or frozen check/run')
    except Exception as error:
        print(f'STOP: {error}. Preserve all packages and paths; do not repeat sign/update/register/ready.', file=sys.stderr)
        sys.exit(78)
