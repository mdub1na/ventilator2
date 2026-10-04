#!/usr/bin/env python3
"""Run update orchestration on files/fakes; no keys, system changes or hardware."""
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module
update = load('update', repo / 'scripts/gui-helper-update.py')
u = load('utils', repo / 'scripts/registration-probe-session.py')

def fixture(root):
    p = root / 'session'; p.mkdir(mode=0o700)
    app = p / 'payload.app'; app.mkdir()
    for name in ('Contents/Info.plist', 'Contents/MacOS/Ventilator', 'Contents/MacOS/VentilatorHelper', 'Contents/_CodeSignature/CodeResources', 'Contents/Library/LaunchDaemons/dev.ventilator.helper.plist'):
        f = app / name; f.parent.mkdir(parents=True, exist_ok=True); f.write_text('new model bytes')
    installed = root / 'installed.app'; shutil.copytree(app, installed)
    (installed / 'Contents/MacOS/Ventilator').write_text('previous signed bytes')
    protected = root / 'protected'; protected.mkdir(); (protected / 'original').write_text('preserve')
    stage, runtime, gui = root / 'stage.app', root / 'runtime', root / 'User/Ventilator/Helper Setup'
    gui.parent.parent.mkdir(mode=0o700)
    (p / 'session.py').write_text('model script'); (p / 'PLAN.md').write_text('model review')
    u.save(p / 'manifest.json', {'purpose': 'guiHelperReadOnlyUpdate', 'ownerUID': os.getuid(), 'sessionPath': str(p),
        'machine': update.MACHINE, 'certificate': update.CERTIFICATE, 'team': update.TEAM,
        'installedPath': str(installed), 'stagePath': str(stage), 'guiRoot': str(gui), 'previousGUIFilesSHA256': {},
        'protectedFilesSHA256': {str(protected): u.tree(protected)}, 'previousInstalledFilesSHA256': u.tree(installed),
        'previousFingerprint': update.fingerprint(installed, u), 'payloadFilesSHA256': u.tree(app),
        'scriptSHA256': u.digest(p / 'session.py'), 'planSHA256': u.digest(p / 'PLAN.md'), 'hardwareWrites': []})
    return p, installed, stage, runtime, gui, protected

modes = ('verified', 'pending', 'no-gui-attempt', 'peer-failure', 'certificate-failure', 'unknown-native', 'bad-identity',
         'hardware-not-denied', 'gui-alive', 'changed-protected', 'stage-present', 'partial-copy', 'job-stale',
         'root-alarm', 'sudo-denied', 'move-failure', 'runtime-appeared', 'bad-gui-marker', 'cancel')
for mode in modes:
    with tempfile.TemporaryDirectory(prefix='ventilator-gui-update-model-', dir=repo / '.build') as d:
        p, installed, stage, runtime, gui, protected = fixture(Path(d))
        previous = u.tree(installed); calls = []; state = {'gui': False, 'old': 'requiresApproval'}
        if mode == 'changed-protected': (protected / 'original').write_text('external change')
        if mode == 'stage-present': stage.mkdir()
        supplied = u.tree(protected)
        answers = iter(['CLOSED', 'CANCEL' if mode == 'cancel' else 'NONE' if mode == 'pending' else 'ALLOW'])
        def execute(argv, timeout=30):
            args = [str(x) for x in argv]; calls.append(args)
            def reply(value): return subprocess.CompletedProcess(args, 0, json.dumps(value), '')
            if args[0] == '/usr/bin/codesign':
                target = Path(args[-1]); f = target / 'Contents/MacOS/Ventilator' if target.suffix == '.app' else target
                f.write_bytes(f.read_bytes() + b' signed model'); return subprocess.CompletedProcess(args, 0, '', '')
            if '--inspect-signed-bundle' in args:
                target = Path(args[-1]); return reply({'trustedBundle': True, 'rootOwned': True, 'installedLocation': target == installed,
                    'fingerprint': update.fingerprint(target, u), 'registration': 'notQueried', 'helperVerified': False, 'hardwareControlAvailable': False})
            if '--qualify-owner-signature' in args:
                if mode == 'certificate-failure': return subprocess.CompletedProcess(args, 78, '', 'model revocation unavailable')
                assert timeout == 30
                return reply({'certificateSHA1': update.CERTIFICATE, 'teamIdentifier': update.TEAM, 'positiveRevocation': True,
                              'fingerprint': update.fingerprint(p / 'payload.app', u)})
            if args[0] == '/usr/bin/open':
                assert args == ['/usr/bin/open', '-n', '-a', str(installed), '--args', '--show-helper-setup']
                state['gui'] = True
                if mode != 'no-gui-attempt':
                    gui.parent.mkdir(mode=0o700); gui.mkdir(mode=0o700)
                    seal = json.loads((p / 'sealed.json').read_text()); marker = update.attempt_path(seal)
                    u.save(marker, {'ownerUID': os.getuid(), 'pid': 123, 'fingerprint': update.fingerprint(installed, u)})
                    marker.chmod(0o644 if mode == 'bad-gui-marker' else 0o600)
                return subprocess.CompletedProcess(args, 0, '', '')
            if '--helper-status' in args or '--unregister-helper' in args:
                if '--unregister-helper' in args: state['old'] = 'notRegistered'
                if mode == 'runtime-appeared' and not state['gui']: runtime.mkdir()
                registration = ('requiresApproval' if mode == 'pending' else 'unknown' if mode == 'unknown-native' else 'enabled') if state['gui'] else state['old']
                value = {'trustedBundle': True, 'rootOwned': True, 'installedLocation': True, 'fingerprint': update.fingerprint(installed, u),
                         'registration': registration, 'helperVerified': state['gui'] and mode not in ('pending', 'peer-failure'), 'hardwareControlAvailable': False}
                if mode == 'bad-identity' and state['gui']: value['trustedBundle'] = False
                if registration != 'enabled': value['error'] = 'serviceNotEnabled'
                if mode == 'peer-failure' and state['gui']: value['error'] = 'deadline'
                return reply(value)
            if '--owner-experiment-status' in args:
                return reply({'hardwareControlAvailable': mode == 'hardware-not-denied', 'errorCode': 'failed("unsupportedMachine")'})
            raise AssertionError('Unexpected native invocation: ' + str(args))
        def privileged(argv, alarm=20):
            args = [str(x) for x in argv]; calls.append(args)
            if args[0] == '/bin/launchctl':
                assert args == ['/bin/launchctl', 'print', 'system/dev.ventilator.helper'] and alarm == 5
                code = -14 if mode == 'root-alarm' else 1 if mode == 'sudo-denied' else 0 if state['gui'] and mode != 'pending' or mode == 'job-stale' and state['old'] == 'notRegistered' else 113
                return subprocess.CompletedProcess(args, code, '', '')
            assert alarm == 20
            if args[0] == '/bin/mkdir': stage.mkdir()
            elif args[0] == '/usr/bin/ditto':
                if mode == 'partial-copy': return subprocess.CompletedProcess(args, 1, '', 'partial model copy')
                shutil.copytree(p / 'payload.app', stage, dirs_exist_ok=True)
            elif args[0] in ('/usr/sbin/chown', '/bin/chmod'): pass
            elif args[0] == '/bin/mv':
                assert args[1] == '-n'
                if mode == 'move-failure' and Path(args[2]) == stage: return subprocess.CompletedProcess(args, 1, '', 'model move failure')
                shutil.move(args[2], args[3])
            else: raise AssertionError('Unexpected privileged action: ' + str(args))
            return subprocess.CompletedProcess(args, 0, '', '')
        def exited(*args, **kwargs):
            if mode == 'gui-alive': raise RuntimeError('model GUI alive')
        with patch.object(update, 'INSTALLED', installed), patch.object(update, 'STAGE', stage), patch.object(update, 'RUNTIME', runtime), \
             patch.object(update, 'GUI_ROOT', gui), patch.object(update, 'require_root_owned'), patch.object(update, 'require_app_exit', side_effect=exited), \
             patch.object(u, 'owner_terminal'), patch.object(u, 'machine', return_value=update.MACHINE), patch.object(u, 'execute', side_effect=execute), \
             patch.object(u, 'privileged', side_effect=privileged), patch('builtins.input', side_effect=lambda _: next(answers)):
            if mode in ('verified', 'pending', 'no-gui-attempt', 'peer-failure'):
                update.run(p, u)
                result = json.loads((p / 'result.json').read_text())
                assert result['readOnlyHelperVerified'] == (mode in ('verified', 'no-gui-attempt'))
                assert (result['guiRegistrationAttempt'] is None) == (mode == 'no-gui-attempt')
                assert u.tree(p / 'previous-installed.bundle') == previous and not stage.exists()
                assert result['physicalAutoVerified'] is False and result['hardwareWritesExecuted'] == 0
            else:
                try: update.run(p, u); raise AssertionError('Failure ignored: ' + mode)
                except RuntimeError: pass
                assert not (p / 'result.json').exists()
                if mode in ('certificate-failure', 'gui-alive', 'changed-protected', 'stage-present'):
                    assert not any(c[0] in ('/bin/mkdir', '/bin/mv', '/bin/launchctl') for c in calls)
                if mode in ('partial-copy', 'job-stale', 'root-alarm', 'sudo-denied', 'runtime-appeared'):
                    assert not any(c[0] == '/bin/mv' for c in calls)
                if mode in ('runtime-appeared', 'root-alarm', 'sudo-denied'):
                    assert not any('--unregister-helper' in c for c in calls)
                if mode == 'move-failure': assert not installed.exists() and u.tree(p / 'previous-installed.bundle') == previous and stage.exists()
            before = list(calls)
            if (p / 'run-started.json').exists():
                try: update.run(p, u); raise AssertionError('Replay admitted')
                except RuntimeError: pass
                assert calls == before
        assert u.tree(protected) == supplied
        assert not any('--register-helper' in c or '--run-owner-experiment' in c or '--approve-local-hardware' in c for c in calls)
        if not (p / 'previous-installed.bundle').exists(): assert u.tree(installed) == previous
        print('GUI update model: ' + mode + ' passed')
print('19 GUI update outcomes + source preservation/replay/no CLI register/no hardware calls passed; no real native or root commands.')
