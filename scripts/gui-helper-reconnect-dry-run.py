#!/usr/bin/env python3
"""Compose preserved update/OFF admission using files and fakes only."""
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
reconnect=load('reconnect',repo/'scripts/gui-helper-reconnect.py')
fixture_ast=next(n for n in ast.parse((repo/'scripts/gui-helper-update-dry-run.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='fixture')
modes=('verified','pending','peer-failure','certificate-failure','off-ignored','off-cancel','loaded-before-off','unknown-before-off',
       'changed-during-off','unregister-failure','loaded-before-unregister','unknown-before-unregister',
       'new-gui-cancel','changed-protected','changed-boot','wrong-sequence','no-tty','gui-alive')
for mode in modes:
    g=load('base',repo/'scripts/gui-helper-update.py');u=load('utils',repo/'scripts/registration-probe-session.py')
    namespace={'update':g,'u':u,'repo':repo,'Path':Path,'json':json,'os':os,'shutil':shutil}
    exec(compile(ast.Module(body=[fixture_ast],type_ignores=[]),'<shared-update-fixture>','exec'),namespace)
    with tempfile.TemporaryDirectory(prefix='ventilator-reconnect-model-',dir=repo/'.build') as directory:
        p,installed,stage,runtime,gui,protected=namespace['fixture'](Path(directory))
        m=json.loads((p/'manifest.json').read_text());m.update({'sequence':reconnect.SEQUENCE,'bootUUID':'boot'})
        if mode=='wrong-sequence':m['sequence']='other'
        (p/'manifest.json').write_text(json.dumps(m));previous=u.tree(installed);calls=[];answers=[]
        state={'off':False,'gui':False,'old':'enabled'}
        if mode=='changed-protected':(protected/'original').write_text('external change')
        supplied=u.tree(protected)
        def owner_input(prompt):
            answers.append(prompt)
            if 'CLOSED' in prompt:return 'CLOSED'
            if 'OFF' in prompt:
                state['off']=True
                if mode=='changed-during-off':(protected/'original').write_text('external off change')
                if mode!='off-ignored':state['old']='requiresApproval'
                return 'CANCEL' if mode=='off-cancel' else 'OFF'
            return 'CANCEL' if mode=='new-gui-cancel' else 'NONE'
        def execute(argv,timeout=30):
            args=[str(x) for x in argv];calls.append(args)
            def reply(value):return subprocess.CompletedProcess(args,0,json.dumps(value),'')
            if args[0]=='/usr/bin/codesign':
                target=Path(args[-1]);f=target/'Contents/MacOS/Ventilator' if target.suffix=='.app' else target
                f.write_bytes(f.read_bytes()+b' signed model');return subprocess.CompletedProcess(args,0,'','')
            if '--inspect-signed-bundle' in args:
                target=Path(args[-1]);return reply({'trustedBundle':True,'rootOwned':True,'installedLocation':target==installed,
                    'fingerprint':g.fingerprint(target,u),'registration':'notQueried','helperVerified':False,'hardwareControlAvailable':False})
            if '--qualify-owner-signature' in args:
                if mode=='certificate-failure':return subprocess.CompletedProcess(args,78,'','model qualification failure')
                return reply({'certificateSHA1':g.CERTIFICATE,'teamIdentifier':g.TEAM,'positiveRevocation':True,'fingerprint':g.fingerprint(p/'payload.app',u)})
            if args[0]=='/usr/bin/open':
                assert args==['/usr/bin/open','-n','-a',str(installed),'--args','--show-helper-setup'];state['gui']=True
                gui.parent.mkdir(mode=0o700);gui.mkdir(mode=0o700)
                seal=json.loads((p/'sealed.json').read_text());marker=g.attempt_path(seal)
                u.save(marker,{'ownerUID':os.getuid(),'pid':123,'fingerprint':g.fingerprint(installed,u)});marker.chmod(0o600)
                return subprocess.CompletedProcess(args,0,'','')
            if '--helper-status' in args or '--unregister-helper' in args:
                if '--unregister-helper' in args:
                    assert state['off'] and state['old']=='requiresApproval'
                    if mode=='unregister-failure':return subprocess.CompletedProcess(args,78,'','model removal denied')
                    state['old']='notRegistered'
                reg=('requiresApproval' if mode=='pending' else 'enabled') if state['gui'] else state['old']
                verified=state['gui'] and reg=='enabled' and mode!='peer-failure'
                value={'trustedBundle':True,'rootOwned':True,'installedLocation':True,'fingerprint':g.fingerprint(installed,u),
                       'registration':reg,'helperVerified':verified,'hardwareControlAvailable':False}
                if not verified:value['error']='remoteFailure' if reg=='enabled' else 'serviceNotEnabled'
                return reply(value)
            if '--owner-experiment-status' in args:return reply({'hardwareControlAvailable':False,'hardwareExperiment':None,'errorCode':'unsupportedMachine'})
            raise AssertionError('Unexpected native action: '+str(args))
        def privileged(argv,alarm=20):
            args=[str(x) for x in argv];calls.append(args)
            if args[0]=='/bin/launchctl':
                assert args==['/bin/launchctl','print','system/'+g.DAEMON] and alarm==5
                code=0 if state['gui'] and mode!='pending' else 0 if mode=='loaded-before-off' and not state['off'] else 1 if mode=='unknown-before-off' and not state['off'] else 113
                if (p/'removal-started.json').exists() and not state['gui']:
                    if mode=='loaded-before-unregister':code=0
                    if mode=='unknown-before-unregister':code=1
                return subprocess.CompletedProcess(args,code,'loaded model' if code==0 else '',None)
            if args[0]=='/bin/mkdir':stage.mkdir()
            elif args[0]=='/usr/bin/ditto':shutil.copytree(Path(args[1]),Path(args[2]),dirs_exist_ok=True)
            elif args[0] in ('/usr/sbin/chown','/bin/chmod'):pass
            elif args[:2]==['/bin/mv','-n']:shutil.move(args[2],args[3])
            else:raise AssertionError('Unexpected privileged action: '+str(args))
            return subprocess.CompletedProcess(args,0,'',None)
        def terminal():
            if mode=='no-tty':raise RuntimeError('model no owner TTY')
        def app_exit(*args,**kwargs):
            if mode=='gui-alive':raise RuntimeError('model GUI still alive')
        with patch.object(reconnect,'STAGE',stage),patch.object(reconnect,'boot',return_value='other' if mode=='changed-boot' else 'boot'), \
             patch.object(g,'INSTALLED',installed),patch.object(g,'STAGE',stage),patch.object(g,'RUNTIME',runtime),patch.object(g,'GUI_ROOT',gui), \
             patch.object(g,'require_root_owned'),patch.object(g,'require_app_exit',side_effect=app_exit),patch.object(u,'machine',return_value=g.MACHINE), \
             patch.object(u,'owner_terminal',side_effect=terminal),patch.object(u,'execute',side_effect=execute),patch.object(u,'privileged',side_effect=privileged), \
             patch('builtins.input',side_effect=owner_input),contextlib.redirect_stdout(io.StringIO()):
            if mode in ('verified','pending','peer-failure'):
                reconnect.reconnect(p,g,u);r=json.loads((p/'result.json').read_text())
                assert r['outcome']==('readOnlyHelperVerified' if mode=='verified' else 'systemApprovalPending' if mode=='pending' else 'helperNotVerified')
                assert r['hardwareWritesExecuted']==0 and r['physicalAutoVerified'] is False
                assert sum('--unregister-helper' in c for c in calls)==1
            else:
                try:reconnect.reconnect(p,g,u);raise AssertionError('failure ignored')
                except RuntimeError:pass
                assert not (p/'result.json').exists()
                if mode!='new-gui-cancel':assert u.tree(installed)==previous
                if mode in ('off-ignored','off-cancel','loaded-before-off','unknown-before-off','loaded-before-unregister','unknown-before-unregister','changed-during-off','certificate-failure','gui-alive'):
                    assert not any('--unregister-helper' in c or c[:2]==['/bin/mv','-n'] for c in calls)
            assert not any('--register-helper' in c or '--owner-approve' in c or '--owner-start' in c for c in calls)
            if (p/'run-started.json').exists():
                count=len(calls)
                try:reconnect.reconnect(p,g,u);raise AssertionError('replay allowed')
                except RuntimeError:pass
                assert len(calls)==count
        if mode=='changed-during-off':assert (protected/'original').read_text()=='external off change'
        else:assert u.tree(protected)==supplied
print('Guarded reconnect: 18 composition models passed; no real native/system/hardware actions.')
