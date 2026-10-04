#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One new review/session for the exact installed, never-started signed candidate; no lifecycle."""
import ctypes
import hashlib
import json
import math
import os
import shutil
import stat
import sys
import types
import uuid
from pathlib import Path

REPO = Path('/Users/mdub1na/IdeaProjects/ventilator2')
PREVIOUS = REPO / '.build/current-hardware-owner'
SESSION = REPO / '.build/current-hardware-continuation'

def utilities():
    path = PREVIOUS / 'session.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != 'b08c2a1b8000bf423f547acefec8b208972f404c2af07cf9c68e898b2e910658':
        raise RuntimeError('Completed owner utility changed')
    owner = types.ModuleType('completed_current_owner'); owner.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec'), owner.__dict__)
    g, u = owner.utilities()
    return owner, g, u

def canonical(value): return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()

def clock():
    # Same read-only mach_continuous_time/timebase conversion as HelperClock; no wall-clock expiry guess.
    class Timebase(ctypes.Structure):
        _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    system.mach_timebase_info.argtypes = [ctypes.POINTER(Timebase)]
    system.mach_timebase_info.restype = ctypes.c_int
    system.mach_continuous_time.argtypes = []
    system.mach_continuous_time.restype = ctypes.c_uint64
    info = Timebase()
    if system.mach_timebase_info(ctypes.byref(info)) != 0 or not info.numer or not info.denom:
        raise RuntimeError('Invalid continuous clock')
    value = system.mach_continuous_time() * info.numer / info.denom / 1e9
    if not math.isfinite(value) or value < 0: raise RuntimeError('Invalid continuous clock')
    return value

def expired_challenge(audit, m, now):
    state = audit.get('authority')
    if (str(uuid.UUID(audit['currentBootSession'])) != m['bootUUID'] or audit.get('outcome') is not None or
        state != {'challenge': m['previousChallenge']}):
        raise RuntimeError('Unexpected authority/approval/ledger/outcome; preserve state')
    challenge = state['challenge']
    issued, expires = challenge['issuedAt'], challenge['expiresAt']
    if not all(math.isfinite(x) for x in (issued, expires, now)) or not 0 <= issued < expires <= now:
        raise RuntimeError('Previous challenge has not expired; stop without import or start')

def check(p, owner, g, u):
    m = json.loads((p / 'manifest.json').read_text()); meta = p.lstat()
    if (p.resolve() != p.absolute() or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700 or
        os.geteuid() == 0 or m.get('purpose') != 'unstartedCurrentSignedContinuation' or
        m.get('sessionPath') != str(p) or m.get('ownerUID') != os.getuid() or
        m.get('machine') != owner.MACHINE or u.machine() != owner.MACHINE or m.get('bootUUID') != owner.boot() or
        m.get('installedPath') != str(g.INSTALLED) or m.get('guiRoot') != str(g.GUI_ROOT) or
        m.get('certificate') != g.CERTIFICATE or m.get('team') != g.TEAM or
        u.digest(p / 'session.py') != m.get('scriptSHA256') or u.digest(p / 'PLAN.md') != m.get('planSHA256')):
        raise RuntimeError('Frozen owner/machine/boot/script/PLAN/identity changed')
    for root, hashes in m['protectedFilesSHA256'].items():
        if u.tree(Path(root)) != hashes: raise RuntimeError('Protected package changed: ' + root)
    if u.tree(g.INSTALLED) != m['installedFilesSHA256'] or g.gui_files(u) != m['privateGUIFilesSHA256']:
        raise RuntimeError('Installed signed files/private GUI markers changed')
    g.require_root_owned(g.INSTALLED)
    if not u.absent(owner.STAGE): raise RuntimeError('Unexpected staging')
    r = g.RUNTIME.lstat()
    if g.RUNTIME.resolve() != g.RUNTIME.absolute() or not stat.S_ISDIR(r.st_mode) or r.st_uid != 0 or r.st_mode & 0o022:
        raise RuntimeError('Unsafe or missing current root runtime')
    review = json.loads((p / 'review.json').read_text())
    previous_seal = json.loads((PREVIOUS / 'sealed.json').read_text())
    previous_result = json.loads((PREVIOUS / 'result.json').read_text())
    if (review != {'domain':'hardware','candidate':m['candidate'],'ownerInstructions':(p / 'PLAN.md').read_text()} or
        hashlib.sha256(canonical(review)).hexdigest() != m['reviewSHA256'] or
        m['candidate'] != previous_seal['candidate']['plan'] or m['candidateSHA256'] != previous_seal['candidate']['planSHA256'] or
        m['fingerprint'] != previous_seal['fingerprint'] or
        m['previousChallenge'] != previous_result['audit']['authority']['challenge'] or
        m['candidate']['fixedWrites'] + m['candidate']['restoreWrites'] != m['hardwareWrites']):
        raise RuntimeError('Full signed review/writes binding changed')
    return m

def prepare(owner, g, u):
    evidence = json.loads((REPO / 'docs/research/evidence/current-hardware-declined-result.json').read_text())
    old = json.loads((PREVIOUS / 'manifest.json').read_text()); seal = json.loads((PREVIOUS / 'sealed.json').read_text())
    if (not u.absent(SESSION) or u.tree(PREVIOUS) != evidence['completedFilesSHA256'] or
        evidence['approvalPresent'] or evidence['consumedLedgerPresent'] or evidence['outcomePresent'] or
        evidence['hardwareWritesExecuted'] != 0 or not seal['positiveRevocation'] or
        seal['qualification']['certificateSHA1'] != g.CERTIFICATE or seal['qualification']['teamIdentifier'] != g.TEAM or
        u.tree(g.INSTALLED) != seal['filesSHA256'] or u.machine() != owner.MACHINE or owner.boot() != old['bootUUID']):
        raise RuntimeError('Exact qualified unstarted current installation required')
    instructions = (REPO / 'docs/current-hardware-continuation.md').read_text()
    review = {'domain':'hardware','candidate':seal['candidate']['plan'],'ownerInstructions':instructions}
    if len(instructions.encode()) > 12288 or len(json.dumps(review,ensure_ascii=False,indent=2).encode()) > 16384:
        raise RuntimeError('Complete review exceeds native limits')
    roots = dict(old['protectedFilesSHA256']); roots[str(PREVIOUS)] = evidence['completedFilesSHA256']
    SESSION.mkdir(mode=0o700)
    shutil.copyfile(Path(__file__),SESSION / 'session.py')
    shutil.copyfile(REPO / 'docs/current-hardware-continuation.md',SESSION / 'PLAN.md')
    u.save(SESSION / 'review.json',review)
    u.save(SESSION / 'manifest.json',{'purpose':'unstartedCurrentSignedContinuation','sessionPath':str(SESSION),
        'ownerUID':os.getuid(),'preparedAt':u.now(),'machine':owner.MACHINE,'bootUUID':old['bootUUID'],
        'certificate':g.CERTIFICATE,'team':g.TEAM,'installedPath':str(g.INSTALLED),'guiRoot':str(g.GUI_ROOT),
        'installedFilesSHA256':seal['filesSHA256'],'fingerprint':seal['fingerprint'],
        'privateGUIFilesSHA256':g.gui_files(u),'protectedFilesSHA256':roots,
        'previousChallenge':evidence['afterHardwareCommand']['authority']['challenge'],
        'candidate':review['candidate'],'candidateSHA256':seal['candidate']['planSHA256'],
        'hardwareWrites':review['candidate']['fixedWrites']+review['candidate']['restoreWrites'],
        'scriptSHA256':u.digest(SESSION / 'session.py'),'planSHA256':u.digest(SESSION / 'PLAN.md'),
        'reviewSHA256':hashlib.sha256(canonical(review)).hexdigest()})
    check(SESSION,owner,g,u)
    print('Prepared exact installed continuation; no native/system/approval/hardware actions.')

def run(p, owner, g, u):
    u.owner_terminal(); m = check(p,owner,g,u)
    if not u.absent(p / 'run-started.json'): raise RuntimeError('Continuation already attempted; no retry')
    print((p / 'PLAN.md').read_text(),flush=True)
    u.save(p / 'run-started.json',{'startedAt':u.now(),'hardwareWritesExecuted':0})
    native = g.report(u,[g.INSTALLED / 'Contents/MacOS/Ventilator','--helper-status'])
    g.identity(native,m['fingerprint'])
    u.save(p / 'installed-peer.json',native)
    if native.get('registration') != 'enabled' or native.get('helperVerified') is not True or native.get('error') is not None:
        raise RuntimeError('Exact installed root peer not verified')
    cold = owner.audit(p,'before-review',g,u)
    expired_challenge(cold,m,clock()); check(p,owner,g,u)
    owner.owner_native(['sudo',g.INSTALLED / 'Contents/MacOS/VentilatorHelper',
        '--stage-local-hardware-review',p / 'review.json',m['reviewSHA256']],60)
    u.save(p / 'review-import-completed.json',{'reviewSHA256':m['reviewSHA256'],'hardwareWritesExecuted':0})
    check(p,owner,g,u)
    print('ТЕРМИНАЛ A: здесь позже вводится START с UUID. Полная APPROVE строка вводится только в отдельном B. До успешного одобрения в B ничего здесь не вводите.',flush=True)
    u.save(p / 'hardware-command-started.json',{'planSHA256':m['candidateSHA256'],'reviewSHA256':m['reviewSHA256']})
    failure = None
    try: owner.owner_native([g.INSTALLED / 'Contents/MacOS/Ventilator','--run-owner-experiment',m['reviewSHA256']],360)
    except (owner.subprocess.SubprocessError,RuntimeError) as error: failure = str(error)
    final = owner.audit(p,'after-command',g,u); check(p,owner,g,u)
    no_begin = final.get('authority',{}).get('ledger') is None and final.get('outcome') is None
    value = {'completedAt':u.now(),'installedPeer':native,'audit':final,'clientError':failure,
        'hardwareWriteCountKnown':no_begin,'physicalAutoVerified':False}
    if no_begin: value['hardwareWritesExecuted'] = 0
    u.save(p / 'result.json',value)
    if failure: raise RuntimeError('Client stopped; audit saved; no retry: ' + failure)
    print('Continuation result saved. Stop and report; physical Auto remains unqualified, no retry.')

if __name__ == '__main__':
    try:
        action = sys.argv[1] if len(sys.argv)==2 else ''; owner,g,u = utilities()
        if action == 'prepare': prepare(owner,g,u)
        elif action == 'check': check(Path(__file__).resolve().parent,owner,g,u); print('Frozen continuation matches; no native/system actions.')
        elif action == 'run': run(Path(__file__).resolve().parent,owner,g,u)
        else: raise RuntimeError('Use source prepare or frozen check/run')
    except Exception as error:
        print('STOP: '+str(error)+'. Preserve all packages/root state. Do not repeat either session, APPROVE, START, register, ready or hardware commands; follow PLAN.md.',file=sys.stderr)
        sys.exit(78)
