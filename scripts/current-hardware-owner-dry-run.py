#!/usr/bin/env python3
"""Exercise full owner orchestration using fake native/root/Terminal calls and isolated files."""
import ast
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

repo=Path(__file__).resolve().parent.parent
def load(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
owner=load('current_owner',repo/'scripts/current-hardware-owner.py')
template=json.loads(subprocess.check_output([str(repo/'.build/Ventilator.app/Contents/MacOS/VentilatorHelper'),'--candidate-plan'],text=True))['plan']
fixture_ast=next(n for n in ast.parse((repo/'scripts/gui-helper-update-dry-run.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='fixture')
modes=('verified','client-failure','certificate-failure','old-peer-failure','old-job-absent','unknown-old-job','unregister-failure',
       'old-job-still-loaded','new-peer-pending','new-job-absent','missing-marker','bad-marker','cold-authority-present',
       'cold-wrong-boot','changed-protected','changed-boot','wrong-writes','runtime-before-gui','unsafe-new-runtime',
       'review-import-failure','gui-alive','no-tty','connect-cancel','on-cancel','allow-cancel','close-cancel','partial-copy','move-failure')
for mode in modes:
    g,u=owner.utilities();namespace={'update':g,'u':u,'repo':repo,'Path':Path,'json':json,'os':os,'shutil':shutil}
    exec(compile(ast.Module(body=[fixture_ast],type_ignores=[]),'<shared-fixture>','exec'),namespace)
    with tempfile.TemporaryDirectory(prefix='ventilator-current-owner-model-',dir=repo/'.build') as d:
        p,installed,stage,runtime,gui,protected=namespace['fixture'](Path(d))
        for bundle in (p/'payload.app',installed):
            (bundle/'Contents/Library/LaunchDaemons/dev.ventilator.helper.plist').rename(bundle/owner.PLIST)
        m=json.loads((p/'manifest.json').read_text());boot='11111111-1111-1111-1111-111111111111'
        m.update(purpose='currentProfileOwnerExperimentV4',bootUUID=boot,daemon=owner.DAEMON,
            payloadFilesSHA256=u.tree(p/'payload.app'),previousInstalledFilesSHA256=u.tree(installed),
            previousFingerprint=owner.fingerprint(installed,u),hardwareWrites=template['fixedWrites']+template['restoreWrites'])
        if mode=='wrong-writes':m['hardwareWrites']=[]
        (p/'manifest.json').write_text(json.dumps(m));previous=u.tree(installed);calls=[];state={'gui':False,'removed':False,'client':False}
        if mode=='changed-protected':(protected/'original').write_text('external change')
        supplied=u.tree(protected)
        def reply(args,value):return subprocess.CompletedProcess(args,0,json.dumps(value),'')
        def execute(argv,timeout=30):
            args=[str(x) for x in argv];calls.append(args)
            if args[0]=='/usr/bin/codesign':
                target=Path(args[-1]);f=target/'Contents/MacOS/Ventilator' if target.suffix=='.app' else target
                f.write_bytes(f.read_bytes()+b' signed model');return subprocess.CompletedProcess(args,0,'','')
            if '--inspect-signed-bundle' in args:
                target=Path(args[-1]);return reply(args,{'trustedBundle':True,'rootOwned':True,'installedLocation':target==installed,
                    'fingerprint':owner.fingerprint(target,u),'registration':'notQueried','helperVerified':False,'hardwareControlAvailable':False})
            if '--qualify-owner-signature' in args:
                if mode=='certificate-failure':return subprocess.CompletedProcess(args,78,'','model qualification failure')
                return reply(args,{'positiveRevocation':True,'certificateSHA1':g.CERTIFICATE,'teamIdentifier':g.TEAM,'fingerprint':owner.fingerprint(p/'payload.app',u)})
            if '--candidate-plan' in args:
                proposal=dict(template);proposal['binaries']={k:owner.fingerprint(p/'payload.app',u)[k] for k in ('applicationSHA256','helperSHA256')}
                return reply(args,{'plan':proposal,'planSHA256':owner.hashlib.sha256(owner.canonical(proposal)).hexdigest(),'hardwareWritesExecuted':0})
            if '--unregister-helper' in args or '--helper-status' in args:
                if '--unregister-helper' in args:
                    if mode=='unregister-failure':return subprocess.CompletedProcess(args,78,'','model unregister failure')
                    state['removed']=True
                reg=('requiresApproval' if mode=='new-peer-pending' else 'enabled') if state['gui'] else 'notRegistered' if state['removed'] else 'enabled'
                verified=reg=='enabled' and (state['gui'] or mode!='old-peer-failure')
                if mode=='runtime-before-gui':runtime.mkdir(exist_ok=True)
                value={'trustedBundle':True,'rootOwned':True,'installedLocation':True,'fingerprint':owner.fingerprint(installed,u),
                    'registration':reg,'helperVerified':verified,'hardwareControlAvailable':False}
                if not verified:value['error']='remoteFailure' if reg=='enabled' else 'serviceNotEnabled'
                return reply(args,value)
            if args[0]=='/usr/bin/open':
                state['gui']=True
                if mode=='unsafe-new-runtime':runtime.mkdir()
                if mode!='missing-marker':
                    gui.parent.mkdir(mode=0o700);gui.mkdir(mode=0o700);marker=g.attempt_path(json.loads((p/'sealed.json').read_text()))
                    u.save(marker,{'ownerUID':os.getuid(),'pid':123,'fingerprint':owner.fingerprint(installed,u)})
                    marker.chmod(0o644 if mode=='bad-marker' else 0o600)
                return subprocess.CompletedProcess(args,0,'','')
            raise AssertionError('Unexpected native call '+str(args))
        def privileged(argv,alarm=20):
            args=[str(x) for x in argv];calls.append(args)
            if args[0]=='/bin/launchctl':
                assert args==['/bin/launchctl','print','system/'+owner.DAEMON] and alarm==5
                code=(113 if mode=='new-job-absent' else 0) if state['gui'] else (0 if mode=='old-job-still-loaded' else 113) if state['removed'] else 113 if mode=='old-job-absent' else 1 if mode=='unknown-old-job' else 0
                return subprocess.CompletedProcess(args,code,'','')
            if '--owner-hardware-audit' in args:
                value={'readOnlyAudit':True,'hardwareControlAvailable':False,'physicalAutoVerified':False,'currentBootSession':'22222222-2222-2222-2222-222222222222' if mode=='cold-wrong-boot' else boot}
                if mode=='cold-authority-present':value['authority']={'challenge':{}}
                return reply(args,value)
            if args[0]=='/bin/mkdir':stage.mkdir()
            elif args[0]=='/usr/bin/ditto':
                if mode=='partial-copy':return subprocess.CompletedProcess(args,1,'','model partial copy')
                shutil.copytree(Path(args[1]),Path(args[2]),dirs_exist_ok=True)
            elif args[0] in ('/usr/sbin/chown','/bin/chmod'):pass
            elif args[:2]==['/bin/mv','-n']:
                if mode=='move-failure' and Path(args[2])==stage:return subprocess.CompletedProcess(args,1,'','model move failure')
                shutil.move(args[2],args[3])
            else:raise AssertionError('Unexpected root call '+str(args))
            return subprocess.CompletedProcess(args,0,'','')
        def owner_native(argv,timeout):
            args=[str(x) for x in argv];calls.append(args)
            assert args[0]=='sudo' and '--stage-local-hardware-review' in args or '--run-owner-experiment' in args
            if '--stage-local-hardware-review' in args and mode=='review-import-failure':raise subprocess.CalledProcessError(78,args)
            if '--run-owner-experiment' in args:
                state['client']=True
                if mode=='client-failure':raise subprocess.CalledProcessError(78,args)
            return subprocess.CompletedProcess(args,0)
        def owner_input(prompt):
            if 'CLOSED' in prompt:return 'CANCEL' if mode=='close-cancel' else 'CLOSED'
            if 'CONNECTED' in prompt:return 'CANCEL' if mode=='connect-cancel' else 'CONNECTED'
            if 'ON, иначе' in prompt:return 'CANCEL' if mode=='on-cancel' else 'ON'
            return 'CANCEL' if mode=='allow-cancel' else 'ALLOW'
        def terminal():
            if mode=='no-tty':raise RuntimeError('model no owner TTY')
        def exited(*args,**kwargs):
            if mode=='gui-alive':raise RuntimeError('model GUI alive')
        with patch.object(owner,'STAGE',stage),patch.object(owner,'boot',return_value='other' if mode=='changed-boot' else boot), \
             patch.object(g,'INSTALLED',installed),patch.object(g,'RUNTIME',runtime),patch.object(g,'GUI_ROOT',gui),patch.object(g,'require_root_owned'), \
             patch.object(g,'require_app_exit',side_effect=exited),patch.object(u,'owner_terminal',side_effect=terminal),patch.object(u,'machine',return_value=owner.MACHINE), \
             patch.object(u,'execute',side_effect=execute),patch.object(u,'privileged',side_effect=privileged),patch.object(owner,'owner_native',side_effect=owner_native), \
             patch('builtins.input',side_effect=owner_input),contextlib.redirect_stdout(io.StringIO()):
            if mode=='verified':owner.run(p,g,u)
            else:
                try:owner.run(p,g,u);raise AssertionError('Failure ignored: '+mode)
                except (RuntimeError,subprocess.SubprocessError):pass
            if mode in ('verified','client-failure'):
                result=json.loads((p/'result.json').read_text());assert result['physicalAutoVerified'] is False and result['hardwareWriteCountKnown'] is False
                assert state['client'] and u.tree(p/'previous-installed.bundle')==previous
                assert sum('--run-owner-experiment' in c for c in calls)==1
            else:assert not state['client'] and not (p/'hardware-command-started.json').exists()
            if mode in ('certificate-failure','old-peer-failure','old-job-absent','unknown-old-job','runtime-before-gui','changed-protected','changed-boot','wrong-writes','no-tty','gui-alive','close-cancel','partial-copy'):
                assert u.tree(installed)==previous and not any('--unregister-helper' in c or c[:2]==['/bin/mv','-n'] for c in calls)
            if (p/'run-started.json').exists():
                count=len(calls)
                try:owner.run(p,g,u);raise AssertionError('Replay accepted')
                except RuntimeError:pass
                assert len(calls)==count
        assert u.tree(protected)==supplied
print('Current owner session: 28 file/fake models passed; no real keys, root, registration or hardware commands.')
