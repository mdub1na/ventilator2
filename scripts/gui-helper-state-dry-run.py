#!/usr/bin/env python3
"""Filesystem/fake administrative reads only; no native app, sudo or hardware."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import types
from pathlib import Path
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('state_read', repo / 'scripts/gui-helper-state.py')
reader = importlib.util.module_from_spec(spec); spec.loader.exec_module(reader)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def tree(p): return {str(f.relative_to(p)): digest(f) for f in sorted(p.rglob('*')) if f.is_file()}
def save(p, value):
    with p.open('x') as f: json.dump(value, f)

text = '''Records for UID -2:
 #1:
 Identifier: 2.dev.ventilator.macos
 Disposition: [enabled, disallowed, not notified]
 URL: file:///Applications/Ventilator.app/
 #2:
 Identifier: 16.dev.ventilator.helper
 Parent Identifier: dev.ventilator.macos
Records for UID 501:
 #1:
 Identifier: unrelated.example
 Name: Never save this other application
 #2:
 Identifier: 2.dev.ventilator.macos
 Disposition: [enabled, allowed, notified]
'''
records = reader.scoped_btm(text)
assert [r['uid'] for r in records] == [-2, -2, 501]
assert 'unrelated' not in json.dumps(records) and 'Never save' not in json.dumps(records)

modes = ('absent', 'loaded', 'btm-timeout', 'btm-format', 'empty-btm', 'sudo-denied', 'authentication-timeout',
         'unknown-job', 'no-tty', 'changed-source', 'changed-installed', 'changed-gui', 'changed-boot', 'runtime-present',
         'unsafe-marker', 'wrong-marker', 'qualification-failed', 'root-ownership', 'changed-during-read')
for mode in modes:
    with tempfile.TemporaryDirectory(prefix='ventilator-gui-state-model-', dir=repo / '.build') as d:
        base = Path(d); source = base/'source'; installed=base/'installed'; gui=base/'gui'; package=base/'read'; protected=base/'protected'
        for p in (source, installed, gui, package, protected): p.mkdir(mode=0o700)
        (installed/'app').write_text('signed model'); (protected/'older').write_text('preserve')
        fp = {'applicationSHA256':'a'*64, 'helperSHA256':'b'*64, 'launchDaemonSHA256':'c'*64}
        registration = {'registration':'enabled', 'error':'remoteFailure', 'helperVerified':False,
                        'trustedBundle':True,'installedLocation':True,'rootOwned':True,'fingerprint':fp,'hardwareControlAvailable':False}
        attempt = {'pid':99,'ownerUID':os.getuid(),'fingerprint':fp}
        previous = {'outcome':'helperNotVerified','registration':registration,'guiRegistrationAttempt':attempt,
                    'rootJobLoaded':False,'readOnlyHelperVerified':False,'hardwareWritesExecuted':0,'physicalAutoVerified':False}
        marker=gui/'attempt.json'; save(marker, attempt); marker.chmod(0o600)
        save(source/'result.json', previous); save(source/'sealed.json', {'fingerprint':fp,'positiveRevocation':True,'qualification':{'positiveRevocation':True}})
        (package/'session.py').write_text('model only'); (package/'PLAN.md').write_text('One read, no lifecycle actions')
        expected_protected = tree(protected)
        def old_check(*args):
            if mode == 'runtime-present': raise RuntimeError('model runtime present')
            assert tree(protected) == expected_protected
        def ownership(*args):
            if mode == 'root-ownership': raise RuntimeError('model unsafe ownership')
        def identity(value, expected):
            assert value['fingerprint'] == expected and value['hardwareControlAvailable'] is False
        g=types.SimpleNamespace(MACHINE={'build':'model'}, INSTALLED=installed, check=old_check, identity=identity,
                                require_root_owned=ownership, attempt_path=lambda _:marker, gui_files=lambda _:tree(gui))
        calls=[]
        def privileged(argv, alarm):
            calls.append(argv)
            assert (argv,alarm) in list(reader.READS.values())
            if mode == 'authentication-timeout': raise subprocess.TimeoutExpired(argv,180)
            if argv[0]=='/bin/launchctl':
                code = 0 if mode=='loaded' else 1 if mode=='sudo-denied' else 7 if mode=='unknown-job' else 113
                if mode=='changed-during-read': (installed/'app').write_text('changed')
                return subprocess.CompletedProcess(argv,code,'loaded model' if code==0 else '',None)
            return subprocess.CompletedProcess(argv,-14 if mode=='btm-timeout' else 0,
                'unrecognized output' if mode=='btm-format' else 'Records for UID 501:\n' if mode=='empty-btm' else text,None)
        def terminal():
            if mode=='no-tty': raise RuntimeError('model requires owner TTY')
        u=types.SimpleNamespace(tree=tree,digest=digest,save=save,now=lambda:'model time',machine=lambda:g.MACHINE,
                                absent=lambda p:not p.exists(), owner_terminal=terminal,privileged=privileged)
        m={'purpose':'guiHelperAdministrativeReadOnly','ownerUID':os.getuid(),'sessionPath':str(package),'sourcePath':str(source),
           'machine':g.MACHINE,'bootUUID':'same','hardwareWrites':[],'scriptSHA256':digest(package/'session.py'),
           'planSHA256':digest(package/'PLAN.md'),'sourceFilesSHA256':tree(source),'installedFilesSHA256':tree(installed),
           'guiFilesSHA256':tree(gui),'previousResult':previous,'fingerprint':fp}
        save(package/'manifest.json',m)
        if mode=='changed-source': (source/'result.json').write_text('{}')
        if mode=='changed-installed': (installed/'app').write_text('changed')
        if mode=='changed-gui': (gui/'older.json').write_text('{}')
        if mode=='unsafe-marker': marker.chmod(0o644)
        if mode=='wrong-marker': marker.write_text('{}')
        if mode=='qualification-failed': save(source/'other.json',{}); (source/'sealed.json').write_text(json.dumps({'fingerprint':fp,'positiveRevocation':False,'qualification':{'positiveRevocation':True}}))
        before_source=tree(source);before_gui=tree(gui)
        with patch.object(reader,'SOURCE',source), patch.object(reader,'boot',return_value='other' if mode=='changed-boot' else 'same'), contextlib.redirect_stdout(io.StringIO()):
            try: reader.collect(package,g,u)
            except (RuntimeError, KeyError):
                assert mode in ('no-tty','changed-source','changed-installed','changed-gui','changed-boot','runtime-present',
                                'unsafe-marker','wrong-marker','qualification-failed','root-ownership')
                assert not calls
            else:
                result=json.loads((package/'result.json').read_text())
                assert result['helperVerified'] is False and result['registrationStatus'] is None
                assert result['nativeVerificationAttempted'] is False and result['hardwareWritesExecuted']==0
                expected='rootPeerUnverified' if mode=='loaded' else 'rootJobAbsent' if mode in ('absent','empty-btm') else 'diagnosticIncomplete'
                assert result['outcome']==expected
                assert 'Never save' not in (package/'result.json').read_text()
                assert len(calls)==(1 if mode in ('sudo-denied','unknown-job','authentication-timeout','changed-during-read') else 2)
            if (package/'started.json').exists():
                count=len(calls)
                try: reader.collect(package,g,u); raise AssertionError('replay allowed')
                except (RuntimeError,KeyError): pass
                assert len(calls)==count
        assert tree(source)==before_source and tree(gui)==before_gui and tree(protected)==expected_protected
print('GUI administrative read: 19 workflow models and scoped UID parser passed; no real system actions.')
