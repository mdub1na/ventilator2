#!/usr/bin/env python3
"""Continuation ordering/authority models; all native, root and TTY operations are fake."""
import contextlib
import importlib.util
import io
import json
import subprocess
import tempfile
import types
from pathlib import Path
from unittest.mock import patch

repo=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('continuation',repo/'scripts/current-hardware-continuation.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
original,g,u=c.utilities()
modes=('verified','client-failure','peer-pending','peer-error','approval-present','ledger-present','outcome-present',
       'wrong-boot','changed-challenge','unexpired','invalid-clock','review-import-failure','no-tty','pins-changed')
for mode in modes:
    with tempfile.TemporaryDirectory(prefix='ventilator-continuation-model-',dir=repo/'.build') as d:
        p=Path(d);(p/'PLAN.md').write_text('Model only; no native/hardware actions.')
        challenge={'issuedAt':50,'expiresAt':80,'id':'11111111-1111-1111-1111-111111111111'}
        boot='22222222-2222-2222-2222-222222222222'
        m={'bootUUID':boot,'previousChallenge':challenge,'fingerprint':{'model':'exact'},'reviewSHA256':'a'*64,'candidateSHA256':'b'*64}
        calls=[]
        def checked(*args):
            if mode=='pins-changed':raise RuntimeError('model changed pin')
            return m
        def terminal():
            if mode=='no-tty':raise RuntimeError('model no TTY')
        def report(*args):
            calls.append('peer');value={'fingerprint':m['fingerprint'],'registration':'enabled','helperVerified':True}
            if mode=='peer-pending':value.update(registration='requiresApproval',helperVerified=False)
            if mode=='peer-error':value['error']='model peer failure'
            return value
        def audit(package,name,*args):
            calls.append(name)
            value={'currentBootSession':boot,'readOnlyAudit':True,'hardwareControlAvailable':False,'physicalAutoVerified':False,
                   'authority':{'challenge':dict(challenge)}}
            if mode=='approval-present':value['authority']['approval']={}
            if mode=='ledger-present':value['authority']['ledger']={}
            if mode=='outcome-present':value['outcome']={}
            if mode=='wrong-boot':value['currentBootSession']='33333333-3333-3333-3333-333333333333'
            if mode=='changed-challenge':value['authority']['challenge']['id']='other'
            u.save(package/(name+'.json'),value);return value
        def native(argv,timeout):
            args=[str(x) for x in argv];calls.append(args)
            if '--stage-local-hardware-review' in args and mode=='review-import-failure':raise subprocess.CalledProcessError(78,args)
            if '--run-owner-experiment' in args and mode=='client-failure':raise subprocess.CalledProcessError(78,args)
            assert '--stage-local-hardware-review' in args or '--run-owner-experiment' in args
        fake_owner=types.SimpleNamespace(audit=audit,owner_native=native,subprocess=subprocess)
        fake_g=types.SimpleNamespace(INSTALLED=Path('/model/Ventilator.app'),report=report,identity=lambda value,fp:None)
        with patch.object(c,'check',side_effect=checked),patch.object(c,'clock',return_value=77 if mode=='unexpired' else float('nan') if mode=='invalid-clock' else 100), \
             patch.object(u,'owner_terminal',side_effect=terminal),contextlib.redirect_stdout(io.StringIO()):
            if mode=='verified':c.run(p,fake_owner,fake_g,u)
            else:
                try:c.run(p,fake_owner,fake_g,u);raise AssertionError('Failure accepted: '+mode)
                except (RuntimeError,subprocess.SubprocessError):pass
            clients=[x for x in calls if isinstance(x,list) and '--run-owner-experiment' in x]
            imports=[x for x in calls if isinstance(x,list) and '--stage-local-hardware-review' in x]
            if mode in ('verified','client-failure'):
                assert len(clients)==1 and len(imports)==1 and calls.count('after-command')==1
                result=json.loads((p/'result.json').read_text())
                assert result['hardwareWritesExecuted']==0 and result['physicalAutoVerified'] is False
                assert bool(result['clientError'])==(mode=='client-failure')
            else:
                assert not clients and not (p/'hardware-command-started.json').exists()
                assert len(imports)==(1 if mode=='review-import-failure' else 0)
            if (p/'run-started.json').exists():
                previous=len(calls)
                try:c.run(p,fake_owner,fake_g,u);raise AssertionError('Replay accepted')
                except RuntimeError:pass
                assert len(calls)==previous
print('Continuation: 14 ordering/authority models passed; no real native/root/TTY calls. Frozen file bindings checked separately.')
