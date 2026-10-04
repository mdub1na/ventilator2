#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One reviewed owner session: qualified update, exact review, local approval, one experiment."""
import builtins
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import uuid
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
SESSION = REPO / '.build/current-hardware-owner'
PREVIOUS = REPO / '.build/gui-helper-identity-owner'
STAGE = Path('/Applications/Ventilator-current-experiment-staging.app')
DAEMON = 'dev.ventilator.app.helper'
PLIST = 'Contents/Library/LaunchDaemons/dev.ventilator.app.helper.plist'
MACHINE = {'model': 'Mac15,7', 'version': '27.0.1', 'build': '26A434'}

def utilities():
    path = REPO / '.build/gui-helper-update-owner/session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != '13b45ffde55765a2dafa2320b167b6f2bd9e629b1ac5794e283faf5bc9de4161':
        raise RuntimeError('Preserved diagnostic utilities changed')
    import types
    g = types.ModuleType('preserved_gui_update'); g.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), g.__dict__)
    return g, g.utilities()

def boot():
    return str(uuid.UUID(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'kern.bootsessionuuid'], text=True, timeout=5).strip()))

def fingerprint(app, u):
    return {k: u.digest(app / v) for k, v in {'applicationSHA256': 'Contents/MacOS/Ventilator',
        'helperSHA256': 'Contents/MacOS/VentilatorHelper', 'launchDaemonSHA256': PLIST}.items()}

def canonical(value): return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()

def candidate(app, g, u):
    value = g.report(u, [app / 'Contents/MacOS/VentilatorHelper', '--candidate-plan'])
    p = value['plan']; fp = fingerprint(app, u)
    if (p.get('schemaVersion') != 4 or (p.get('modelIdentifier'), p.get('macOSVersion'), p.get('macOSBuild')) !=
        (MACHINE['model'], MACHINE['version'], MACHINE['build']) or p.get('stage') != 'candidate-unapproved' or
        p.get('readyForOwnerApproval') is not False or p.get('binaries') != {k: fp[k] for k in ('applicationSHA256','helperSHA256')} or
        hashlib.sha256(canonical(p)).hexdigest() != value.get('planSHA256') or value.get('hardwareWritesExecuted') != 0):
        raise RuntimeError('Exact current unapproved candidate required')
    return value

def check(p, g, u):
    m = json.loads((p / 'manifest.json').read_text()); meta = p.lstat()
    if (p.resolve() != p.absolute() or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700 or
        os.geteuid() == 0 or m.get('purpose') != 'currentProfileOwnerExperimentV4' or m.get('ownerUID') != os.getuid() or
        m.get('sessionPath') != str(p) or m.get('machine') != MACHINE or u.machine() != MACHINE or m.get('bootUUID') != boot() or
        m.get('certificate') != g.CERTIFICATE or m.get('team') != g.TEAM or m.get('installedPath') != str(g.INSTALLED) or
        m.get('stagePath') != str(STAGE) or m.get('guiRoot') != str(g.GUI_ROOT) or m.get('daemon') != DAEMON or
        u.digest(p / 'session.py') != m.get('scriptSHA256') or u.digest(p / 'PLAN.md') != m.get('planSHA256')):
        raise RuntimeError('Owner/machine/boot/identity/PLAN/script binding changed')
    for root, expected in m['protectedFilesSHA256'].items():
        if u.tree(Path(root)) != expected: raise RuntimeError('Protected package changed: ' + root)
    files = m['payloadFilesSHA256']
    for name in ('sealed.json', 'signature-ready.json'):
        if (p / name).is_file(): files = json.loads((p / name).read_text())['filesSHA256']; break
    if u.tree(p / 'payload.app') != files: raise RuntimeError('Payload changed; preserve partial signature')
    backup = p / 'previous-installed.bundle'
    if u.absent(backup): expected = m['previousInstalledFilesSHA256']
    else:
        if u.tree(backup) != m['previousInstalledFilesSHA256']: raise RuntimeError('Old backup changed')
        expected = files
    if not u.absent(g.INSTALLED) and u.tree(g.INSTALLED) != expected: raise RuntimeError('Installation changed')
    if u.absent(backup) and u.absent(g.INSTALLED): raise RuntimeError('Previous installation absent')
    if not u.absent(STAGE) and u.tree(STAGE) != files: raise RuntimeError('Partial/stale staging; preserve it')
    current = g.gui_files(u)
    if (p / 'gui-open-started.json').is_file(): current.pop(g.attempt_path(json.loads((p / 'sealed.json').read_text())).name, None)
    if current != m['previousGUIFilesSHA256']: raise RuntimeError('Previous private GUI markers changed')
    if not (p / 'gui-open-started.json').is_file():
        if not u.absent(g.RUNTIME): raise RuntimeError('Previous whole root runtime appeared')
    elif not u.absent(g.RUNTIME):
        r = g.RUNTIME.lstat()
        if g.RUNTIME.resolve() != g.RUNTIME.absolute() or not stat.S_ISDIR(r.st_mode) or r.st_uid != 0 or r.st_mode & 0o022:
            raise RuntimeError('Unsafe new root runtime')
    if (p / 'sealed.json').is_file():
        seal = json.loads((p / 'sealed.json').read_text()); review = json.loads((p / 'review.json').read_text())
        if (review != {'domain':'hardware','candidate':seal['candidate']['plan'],'ownerInstructions':(p / 'PLAN.md').read_text()} or
            hashlib.sha256(canonical(review)).hexdigest() != seal['reviewSHA256'] or
            (p / 'review.sha256').read_text().strip() != seal['reviewSHA256'] or
            seal['candidate']['plan']['fixedWrites'] + seal['candidate']['plan']['restoreWrites'] != m['hardwareWrites']):
            raise RuntimeError('Sealed full review/writes changed')
    return m

def prepare(g, u):
    instructions = (REPO / 'docs/current-hardware-owner.md').read_text()
    if not instructions.strip() or len(instructions.encode()) > 12288:
        raise RuntimeError('Complete owner PLAN must fit native review limit before signing')
    evidence = json.loads((REPO / 'docs/research/evidence/gui-helper-identity-result.json').read_text())
    source = json.loads((REPO / 'docs/research/evidence/current-experiment-source.json').read_text())
    previous = json.loads((PREVIOUS / 'manifest.json').read_text()); result = json.loads((PREVIOUS / 'result.json').read_text())
    seal = json.loads((PREVIOUS / 'sealed.json').read_text())
    if (u.tree(PREVIOUS) != evidence['completedFilesSHA256'] or result.get('readOnlyHelperVerified') is not True or
        u.tree(g.INSTALLED) != seal['filesSHA256'] or u.machine() != MACHINE or previous['bootUUID'] != boot() or
        not u.absent(g.RUNTIME) or not u.absent(SESSION) or not u.absent(STAGE) or
        u.tree(REPO / '.build/Ventilator.app') != source['adHocBundleFilesSHA256'] or source.get('tests', {}).get('failures') != 0 or
        source.get('orchestrationModels') != 28 or source.get('hardwareWritesExecuted') != 0):
        raise RuntimeError('Verified unchanged cold installation and tested v4 payload required')
    roots = dict(previous['protectedFilesSHA256']); roots[str(PREVIOUS)] = u.tree(PREVIOUS)
    for root, files in roots.items():
        if u.tree(Path(root)) != files: raise RuntimeError('Protected preparation source changed')
    g.require_root_owned(g.INSTALLED)
    proposal = candidate(REPO / '.build/Ventilator.app', g, u)
    if len(json.dumps({'domain':'hardware','candidate':proposal['plan'],'ownerInstructions':instructions}, ensure_ascii=False, indent=2).encode()) > 16384:
        raise RuntimeError('Complete review exceeds native import limit before signing')
    SESSION.mkdir(mode=0o700)
    shutil.copytree(REPO / '.build/Ventilator.app', SESSION / 'payload.app')
    shutil.copyfile(Path(__file__), SESSION / 'session.py')
    shutil.copyfile(REPO / 'docs/current-hardware-owner.md', SESSION / 'PLAN.md')
    u.save(SESSION / 'manifest.json', {'purpose':'currentProfileOwnerExperimentV4','ownerUID':os.getuid(),'sessionPath':str(SESSION),
        'machine':MACHINE,'bootUUID':boot(),'preparedAt':u.now(),'certificate':g.CERTIFICATE,'team':g.TEAM,'daemon':DAEMON,
        'installedPath':str(g.INSTALLED),'stagePath':str(STAGE),'guiRoot':str(g.GUI_ROOT),'previousFingerprint':seal['fingerprint'],
        'previousInstalledFilesSHA256':u.tree(g.INSTALLED),'previousGUIFilesSHA256':g.gui_files(u),'protectedFilesSHA256':roots,
        'payloadFilesSHA256':u.tree(SESSION / 'payload.app'),'scriptSHA256':u.digest(SESSION / 'session.py'),
        'planSHA256':u.digest(SESSION / 'PLAN.md'),'hardwareWrites':proposal['plan']['fixedWrites']+proposal['plan']['restoreWrites']})
    check(SESSION, g, u); print('Prepared one current-profile unapproved owner session; no signing/system/hardware actions.')

def root_job(p, name, u, expected):
    r = u.privileged(['/bin/launchctl','print','system/' + DAEMON], alarm=5)
    u.save(p / (name + '.json'), {'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'observedAt':u.now()})
    if r.returncode != expected: raise RuntimeError('Unexpected root job state; preserve installation')

def audit(p, name, g, u):
    r = u.require_success(u.privileged([g.INSTALLED / 'Contents/MacOS/VentilatorHelper','--owner-hardware-audit'], alarm=5))
    value = json.loads(r.stdout)
    if value.get('readOnlyAudit') is not True or value.get('hardwareControlAvailable') is not False or value.get('physicalAutoVerified') is not False:
        raise RuntimeError('Invalid bounded root audit')
    u.save(p / (name + '.json'), value); return value

def owner_native(argv, timeout):
    # Keep the real Terminal descriptors: the issuer/import rechecks both TTYs.
    return subprocess.run([str(x) for x in argv], timeout=timeout, check=True)

def run(p, g, u):
    u.owner_terminal(); m = check(p,g,u)
    if not u.absent(p / 'run-started.json') or not u.absent(STAGE) or not u.absent(p / 'previous-installed.bundle'):
        raise RuntimeError('Session already attempted; no retry')
    print((p / 'PLAN.md').read_text(), flush=True)
    if builtins.input('Завершите Ventilator через Command-Q; затем CLOSED, иначе CANCEL: ') != 'CLOSED': raise RuntimeError('Owner cancelled')
    g.require_app_exit(u); check(p,g,u)
    u.save(p / 'run-started.json', {'startedAt':u.now(),'hardwareWritesExecuted':0})
    app = p / 'payload.app'; binary = app / 'Contents/MacOS/Ventilator'
    for path, extra in [(app / 'Contents/MacOS/VentilatorHelper',['--identifier',DAEMON]),(app,[])]:
        print('Signing ' + path.name + '; Keychain may request owner authentication.',flush=True)
        r=u.require_success(u.execute(['/usr/bin/codesign','--force','--sign',g.CERTIFICATE,'--options','runtime','--timestamp=none',*extra,path],timeout=180))
        print(r.stderr.strip(),flush=True)
    static=g.report(u,[binary,'--inspect-signed-bundle',app])
    ready={'filesSHA256':u.tree(app),'fingerprint':fingerprint(app,u)}
    if static.get('trustedBundle') is not True or static.get('error') is not None or static.get('registration')!='notQueried' or static.get('fingerprint')!=ready['fingerprint']:
        raise RuntimeError('Signed static inspection failed')
    u.save(p / 'signature-ready.json',ready)
    qualified=g.report(u,[binary,'--qualify-owner-signature',app,g.CERTIFICATE],timeout=30)
    if qualified.get('positiveRevocation') is not True or qualified.get('certificateSHA1')!=g.CERTIFICATE or qualified.get('teamIdentifier')!=g.TEAM or qualified.get('fingerprint')!=ready['fingerprint']:
        raise RuntimeError('Positive qualification required before lifecycle')
    proposal=candidate(app,g,u); review={'domain':'hardware','candidate':proposal['plan'],'ownerInstructions':(p / 'PLAN.md').read_text()}
    review_sha=hashlib.sha256(canonical(review)).hexdigest()
    if len(review['ownerInstructions'].encode())>12288: raise RuntimeError('Full review exceeds native limit')
    u.save(p / 'review.json',review)
    with (p / 'review.sha256').open('x') as f: f.write(review_sha+'\n')
    (p / 'review.sha256').chmod(0o600)
    seal={**ready,'qualification':qualified,'positiveRevocation':True,'candidate':proposal,'reviewSHA256':review_sha}
    u.save(p / 'sealed.json',seal); check(p,g,u)
    print('Qualified signed fingerprint: '+json.dumps(ready['fingerprint'])+'; plan '+proposal['planSHA256']+'; full review '+review_sha,flush=True)
    if not u.absent(g.attempt_path(seal)): raise RuntimeError('GUI attempt already exists')
    for argv in [ ['/bin/mkdir','-m','755',STAGE],['/usr/bin/ditto',app,STAGE],['/usr/sbin/chown','-R','root:wheel',STAGE],['/bin/chmod','-R','go-w',STAGE] ]:
        u.require_success(u.privileged(argv))
    g.require_root_owned(STAGE); check(p,g,u)
    g.identity(g.report(u,[binary,'--inspect-signed-bundle',STAGE]),ready['fingerprint'],registration='notQueried',installed=False)
    g.require_app_exit(u,seconds=0)
    old=g.report(u,[g.INSTALLED / 'Contents/MacOS/Ventilator','--helper-status']);g.identity(old,m['previousFingerprint'])
    if old.get('registration')!='enabled' or old.get('helperVerified') is not True or old.get('error') is not None:
        raise RuntimeError('Exact old enabled root peer required before removal')
    root_job(p,'job-before-removal',u,0); check(p,g,u)
    u.save(p / 'removal-started.json',old)
    removed=g.report(u,[g.INSTALLED / 'Contents/MacOS/Ventilator','--unregister-helper']);g.identity(removed,m['previousFingerprint'])
    if removed.get('registration')!='notRegistered': raise RuntimeError('Guarded unregister incomplete')
    u.save(p / 'removal-completed.json',removed);root_job(p,'job-after-removal',u,113);check(p,g,u)
    g.require_app_exit(u,seconds=0)
    u.save(p / 'replacement-started.json',ready)
    backup=p / 'previous-installed.bundle'
    u.require_success(u.privileged(['/bin/mv','-n',g.INSTALLED,backup]))
    if not u.absent(g.INSTALLED) or u.tree(backup)!=m['previousInstalledFilesSHA256']: raise RuntimeError('Old archival incomplete')
    u.require_success(u.privileged(['/bin/mv','-n',STAGE,g.INSTALLED]))
    if not u.absent(STAGE) or u.tree(g.INSTALLED)!=ready['filesSHA256']: raise RuntimeError('Replacement incomplete')
    g.require_root_owned(g.INSTALLED);check(p,g,u)
    g.identity(g.report(u,[binary,'--inspect-signed-bundle',g.INSTALLED]),ready['fingerprint'],registration='notQueried')
    u.save(p / 'gui-open-started.json',ready)
    u.require_success(u.execute(['/usr/bin/open','-n','-a',g.INSTALLED,'--args','--show-helper-setup'],timeout=10))
    if builtins.input('В новом окне подключите помощник один раз, если кнопка включена; CONNECTED, иначе CANCEL: ')!='CONNECTED': raise RuntimeError('Owner cancelled GUI connection')
    if builtins.input('Проверьте, что только новая Ventilator включена в фоновой активности; ON, иначе CANCEL: ')!='ON': raise RuntimeError('Owner ON missing')
    answer=builtins.input('ALLOW после настоящего Allow/admin; NONE если запроса нет; другое отменяет: ')
    if answer not in ('ALLOW','NONE'): raise RuntimeError('Owner cancelled system consent')
    u.save(p / 'owner-on.json',{'reportedAt':u.now(),'ownerReportedON':True,'systemConsentReported':answer})
    check(p,g,u); marker=g.attempt_path(seal)
    if u.absent(marker): raise RuntimeError('No actual GUI attempt; no review import')
    meta=marker.lstat();attempt=json.loads(marker.read_text())
    if not stat.S_ISREG(meta.st_mode) or meta.st_uid!=os.getuid() or stat.S_IMODE(meta.st_mode)!=0o600 or attempt.get('fingerprint')!=ready['fingerprint'] or attempt.get('ownerUID')!=os.getuid() or type(attempt.get('pid')) is not int or attempt['pid']<=0:
        raise RuntimeError('Invalid private GUI attempt')
    native=g.report(u,[g.INSTALLED / 'Contents/MacOS/Ventilator','--helper-status']);g.identity(native,ready['fingerprint'])
    u.save(p / 'installed-peer.json',native)
    if native.get('registration')!='enabled' or native.get('helperVerified') is not True or native.get('error') is not None:
        raise RuntimeError('New root peer not verified; no review import or experiment')
    root_job(p,'job-after-gui',u,0)
    cold=audit(p,'before-hardware-review',g,u)
    if cold.get('authority') is not None or cold.get('outcome') is not None or str(uuid.UUID(cold['currentBootSession']))!=m['bootUUID']:
        raise RuntimeError('Fresh current authority required; preserve existing state')
    check(p,g,u)
    owner_native(['sudo',g.INSTALLED / 'Contents/MacOS/VentilatorHelper','--stage-local-hardware-review',p / 'review.json',review_sha],60)
    u.save(p / 'review-import-completed.json',{'reviewSHA256':review_sha,'hardwareWritesExecuted':0});check(p,g,u)
    print('Полный review импортирован; аппаратных записей ещё нет. Следующий клиент покажет команду для Terminal B. APPROVE и START означают отдельное явное одобрение и запуск точного опыта.',flush=True)
    u.save(p / 'hardware-command-started.json',{'planSHA256':proposal['planSHA256'],'reviewSHA256':review_sha})
    failure=None
    try: owner_native([g.INSTALLED / 'Contents/MacOS/Ventilator','--run-owner-experiment',review_sha],360)
    except (subprocess.SubprocessError,RuntimeError) as error: failure=str(error)
    final=audit(p,'after-hardware-command',g,u);check(p,g,u)
    u.save(p / 'result.json',{'completedAt':u.now(),'installedPeer':native,'audit':final,'clientError':failure,
        'hardwareWriteCountKnown':False,'physicalAutoVerified':False,'interpretation':'Review actual audit/outcome; never retry Fixed or erase pending.'})
    if failure: raise RuntimeError('Hardware client stopped; audit saved; no retry: '+failure)
    print('Owner session result saved. Stop and report; physical Auto remains unqualified, no retry.')

if __name__=='__main__':
    try:
        action=sys.argv[1] if len(sys.argv)==2 else '';g,u=utilities()
        if action=='prepare': prepare(g,u)
        elif action=='check': check(Path(__file__).resolve().parent,g,u);print('Pinned current owner package matches; no native/system actions.')
        elif action=='run': run(Path(__file__).resolve().parent,g,u)
        else: raise RuntimeError('Use source prepare or frozen check/run')
    except Exception as error:
        print('STOP: '+str(error)+'. Preserve all packages/root state. Do not repeat run/register/ready or hardware commands; follow PLAN.md.',file=sys.stderr)
        sys.exit(78)
