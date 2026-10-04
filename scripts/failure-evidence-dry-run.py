#!/usr/bin/env python3
"""Validate diagnostic capture through real child IPC on file models; never access hardware/root."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

repo=Path(__file__).resolve().parent.parent
helper=repo/'.build/Ventilator.app/Contents/MacOS/VentilatorHelper'
if os.geteuid()==0:raise SystemExit('Failure models require non-root')
reports=[]
for mode in ('normal','unobservedUnlock','unobservedUnlockAutoFailures'):
    with tempfile.TemporaryDirectory(prefix='ventilator-failure-evidence-',dir=repo/'.build') as d:
        folder=Path(d)
        run=subprocess.run([str(helper),'--approved-model-parent',d,mode],capture_output=True,text=True,timeout=20)
        assert run.returncode==0,(mode,run.stderr)
        outcome=json.loads((folder/'recovery-result.json').read_text())
        ledger=json.loads((folder/'authority-simulation.json').read_text())['ledger']
        device=json.loads((folder/'simulation-device.json').read_text())
        assert outcome['simulationOnly'] and outcome['sessionID']==ledger['sessionID']
        assert len(ledger['attempts'])==len(set(ledger['attempts'])) and ledger['fixedClosed']
        failures=outcome['failures'];assert len(failures)<=16
        if mode=='normal':
            assert outcome['phase']=='autoCodesObserved' and not failures
            assert ledger['attempts']==list(range(10)) and not ledger['pendingRestoration']
        else:
            assert ledger['attempts']==[0,5,6,7,8,9] and 1 not in ledger['attempts']
            assert failures[0]['phase']=='fixed' and failures[0]['role']=='fixed' and failures[0]['step']==1
            assert failures[0]['error']=='unsafeObservation'
            sample=json.loads(failures[0]['admissionSampleJSON'])
            assert sample['testMode']==0 and [x['mode'] for x in sample['fans']]==[3,3]
            assert 'fixed' not in [x['stage'] for x in outcome['observations']]
            if mode=='unobservedUnlock':
                assert outcome['phase']=='autoCodesObserved' and not ledger['pendingRestoration']
                assert outcome['failedSteps']==[1] and len(failures)==1
            else:
                assert outcome['phase']=='recoveryRequired' and outcome['reason']=='restoreStepFailure'
                assert ledger['pendingRestoration'] and not ledger['autoCodesObserved']
                assert ledger['successfulReturns']==[0,7,8,9] and outcome['failedSteps']==[1,5,6]
                assert [x['step'] for x in failures]==[1,5,6]
                assert [x['error'] for x in failures]==['unsafeObservation','failedStep','failedStep']
                assert [x['role'] for x in failures]==['fixed','restore','restore']
                assert [x['stage'] for x in outcome['observations']]==['baseline']
                assert device['effects']==[0,7,8,9]
        reports.append({'mode':mode,'phase':outcome['phase'],'reason':outcome.get('reason'),
            'reservedSteps':ledger['attempts'],'successfulReturns':ledger['successfulReturns'],
            'failedSteps':outcome['failedSteps'],'pending':ledger['pendingRestoration'],
            'failures':failures,'independentStages':[x['stage'] for x in outcome['observations']]})
value={'verifiedAt':datetime.datetime.now().astimezone().isoformat(),'UID':os.geteuid(),
    'helperSHA256':hashlib.sha256(helper.read_bytes()).hexdigest(),'cases':reports,
    'matchingReservationPatternDoesNotIdentifyHardwareCause':True,'hardwareWritesExecuted':0,
    'physicalAutoVerified':False,'installedOrRootStateChanged':False}
(repo/'docs/research/evidence/failure-evidence-models.json').write_text(json.dumps(value,indent=2)+'\n')
print('Three real IPC/file models passed: detailed errors/admission samples retained; no extra attempts or independent Auto claims. No hardware/root operations.')
