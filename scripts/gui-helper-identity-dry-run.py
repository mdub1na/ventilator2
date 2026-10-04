#!/usr/bin/env python3
"""Fresh identity consent/removal gates using files and fakes only."""
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

repo = Path(__file__).resolve().parent.parent
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
identity = load('identity', repo / 'scripts/gui-helper-identity.py')
fixture_ast = next(n for n in ast.parse((repo / 'scripts/gui-helper-update-dry-run.py').read_text()).body
                   if isinstance(n, ast.FunctionDef) and n.name == 'fixture')
modes = ('verified', 'pending', 'peer-failure', 'old-unregistered', 'certificate-failure', 'old-enabled',
    'new-loaded', 'new-unknown', 'old-loaded', 'old-unknown', 'loaded-before-unregister', 'unknown-before-unregister',
    'unregister-failure', 'changed-protected', 'changed-boot', 'wrong-sequence', 'wrong-identities', 'no-tty',
    'gui-alive', 'connect-cancel', 'on-cancel', 'allow-cancel', 'no-marker', 'bad-marker', 'hardware-not-denied')
for mode in modes:
    g, u = identity.utilities()
    old_fingerprint = g.fingerprint
    namespace = {'update': g, 'u': u, 'repo': repo, 'Path': Path, 'json': json, 'os': os, 'shutil': shutil}
    exec(compile(ast.Module(body=[fixture_ast], type_ignores=[]), '<shared-update-fixture>', 'exec'), namespace)
    with tempfile.TemporaryDirectory(prefix='ventilator-identity-model-', dir=repo / '.build') as directory:
        p, installed, stage, runtime, gui, protected = namespace['fixture'](Path(directory))
        (p / 'payload.app/Contents/Library/LaunchDaemons/dev.ventilator.helper.plist').rename(p / 'payload.app' / identity.PLIST)
        m = json.loads((p / 'manifest.json').read_text())
        m.update(sequence=identity.SEQUENCE, identities=identity.IDENTITIES, bootUUID='boot', payloadFilesSHA256=u.tree(p / 'payload.app'))
        if mode == 'wrong-sequence': m['sequence'] = 'other'
        if mode == 'wrong-identities': m['identities'] = {}
        (p / 'manifest.json').write_text(json.dumps(m))
        previous = u.tree(installed); calls = []; state = {'gui': False, 'old': 'notRegistered' if mode == 'old-unregistered' else 'requiresApproval'}
        if mode == 'changed-protected': (protected / 'original').write_text('external change')
        supplied = u.tree(protected)
        def owner_input(prompt):
            if 'CLOSED' in prompt: return 'CLOSED'
            if 'CONNECTED' in prompt: return 'CANCEL' if mode == 'connect-cancel' else 'CONNECTED'
            if 'введите ON' in prompt: return 'CANCEL' if mode == 'on-cancel' else 'ON'
            return 'CANCEL' if mode == 'allow-cancel' else 'NONE' if mode == 'pending' else 'ALLOW'
        def execute(argv, timeout=30):
            args = [str(x) for x in argv]; calls.append(args)
            def reply(value): return subprocess.CompletedProcess(args, 0, json.dumps(value), '')
            if args[0] == '/usr/bin/codesign':
                target = Path(args[-1]); f = target / 'Contents/MacOS/Ventilator' if target.suffix == '.app' else target
                if target.name == 'VentilatorHelper': assert args[args.index('--identifier') + 1] == identity.IDENTITIES['helper']
                f.write_bytes(f.read_bytes() + b' signed model'); return subprocess.CompletedProcess(args, 0, '', '')
            if '--inspect-signed-bundle' in args:
                target = Path(args[-1]); return reply({'trustedBundle': True, 'rootOwned': True, 'installedLocation': target == installed,
                    'fingerprint': g.fingerprint(target, u), 'registration': 'notQueried', 'helperVerified': False, 'hardwareControlAvailable': False})
            if '--qualify-owner-signature' in args:
                if mode == 'certificate-failure': return subprocess.CompletedProcess(args, 78, '', 'model qualification failure')
                assert timeout == 30
                return reply({'certificateSHA1': g.CERTIFICATE, 'teamIdentifier': g.TEAM, 'positiveRevocation': True,
                    'fingerprint': g.fingerprint(p / 'payload.app', u)})
            if args[0] == '/usr/bin/open':
                assert args == ['/usr/bin/open', '-n', '-a', str(installed), '--args', '--show-helper-setup']
                state['gui'] = True
                if mode != 'no-marker':
                    gui.parent.mkdir(mode=0o700); gui.mkdir(mode=0o700)
                    marker = g.attempt_path(json.loads((p / 'sealed.json').read_text()))
                    u.save(marker, {'ownerUID': os.getuid(), 'pid': 123, 'fingerprint': g.fingerprint(installed, u)})
                    marker.chmod(0o644 if mode == 'bad-marker' else 0o600)
                return subprocess.CompletedProcess(args, 0, '', '')
            if '--helper-status' in args or '--unregister-helper' in args:
                if '--unregister-helper' in args:
                    assert state['old'] == 'requiresApproval' and not state['gui']
                    if mode == 'unregister-failure': return subprocess.CompletedProcess(args, 78, '', 'model removal denied')
                    state['old'] = 'notRegistered'
                reg = ('requiresApproval' if mode == 'pending' else 'enabled') if state['gui'] else ('enabled' if mode == 'old-enabled' else state['old'])
                verified = state['gui'] and reg == 'enabled' and mode != 'peer-failure'
                value = {'trustedBundle': True, 'rootOwned': True, 'installedLocation': True,
                    'fingerprint': g.fingerprint(installed, u) if state['gui'] else old_fingerprint(installed, u),
                    'registration': reg, 'helperVerified': verified, 'hardwareControlAvailable': False}
                if not verified: value['error'] = 'remoteFailure' if reg == 'enabled' else 'serviceNotEnabled'
                return reply(value)
            if '--owner-experiment-status' in args:
                return reply({'hardwareControlAvailable': mode == 'hardware-not-denied', 'hardwareExperiment': None, 'errorCode': 'unsupportedMachine'})
            raise AssertionError('Unexpected native action: ' + str(args))
        def privileged(argv, alarm=20):
            args = [str(x) for x in argv]; calls.append(args)
            if args[0] == '/bin/launchctl':
                assert alarm == 5 and args[:2] == ['/bin/launchctl', 'print']
                label = args[2].removeprefix('system/')
                assert label in (identity.IDENTITIES['helper'], identity.IDENTITIES['previousHelper'])
                code = 113
                if state['gui']: code = 113 if mode == 'pending' else 0
                elif label == identity.IDENTITIES['helper']: code = 0 if mode == 'new-loaded' else 1 if mode == 'new-unknown' else 113
                elif (p / 'removal-started.json').exists(): code = 0 if mode == 'loaded-before-unregister' else 1 if mode == 'unknown-before-unregister' else 113
                else: code = 0 if mode == 'old-loaded' else 1 if mode == 'old-unknown' else 113
                return subprocess.CompletedProcess(args, code, 'loaded model' if code == 0 else '', None)
            assert alarm == 20
            if args[0] == '/bin/mkdir': stage.mkdir()
            elif args[0] == '/usr/bin/ditto': shutil.copytree(Path(args[1]), Path(args[2]), dirs_exist_ok=True)
            elif args[0] in ('/usr/sbin/chown', '/bin/chmod'): pass
            elif args[:2] == ['/bin/mv', '-n']: shutil.move(args[2], args[3])
            else: raise AssertionError('Unexpected privileged action: ' + str(args))
            return subprocess.CompletedProcess(args, 0, '', None)
        def terminal():
            if mode == 'no-tty': raise RuntimeError('model no owner TTY')
        def app_exit(*args, **kwargs):
            if mode == 'gui-alive': raise RuntimeError('model GUI still alive')
        with patch.object(identity, 'STAGE', stage), patch.object(identity, 'boot', return_value='other' if mode == 'changed-boot' else 'boot'), \
             patch.object(g, 'INSTALLED', installed), patch.object(g, 'STAGE', stage), patch.object(g, 'RUNTIME', runtime), patch.object(g, 'GUI_ROOT', gui), \
             patch.object(g, 'require_root_owned'), patch.object(g, 'require_app_exit', side_effect=app_exit), patch.object(u, 'machine', return_value=g.MACHINE), \
             patch.object(u, 'owner_terminal', side_effect=terminal), patch.object(u, 'execute', side_effect=execute), patch.object(u, 'privileged', side_effect=privileged), \
             patch('builtins.input', side_effect=owner_input), contextlib.redirect_stdout(io.StringIO()):
            success = mode in ('verified', 'pending', 'peer-failure', 'old-unregistered')
            if success:
                identity.run(p, g, u); result = json.loads((p / 'result.json').read_text())
                assert result['outcome'] == ('systemApprovalPending' if mode == 'pending' else 'helperNotVerified' if mode == 'peer-failure' else 'readOnlyHelperVerified')
                assert result['hardwareWritesExecuted'] == 0 and result['physicalAutoVerified'] is False
                assert (p / 'owner-on.json').is_file() and u.tree(p / 'previous-installed.bundle') == previous
                assert sum('--unregister-helper' in c for c in calls) == (0 if mode == 'old-unregistered' else 1)
            else:
                try: identity.run(p, g, u); raise AssertionError('Failure ignored: ' + mode)
                except RuntimeError: pass
                assert not (p / 'result.json').exists()
                if mode not in ('connect-cancel', 'on-cancel', 'allow-cancel', 'no-marker', 'bad-marker', 'hardware-not-denied'):
                    assert u.tree(installed) == previous
                    assert not any(c[:2] == ['/bin/mv', '-n'] for c in calls)
                if mode in ('old-enabled', 'new-loaded', 'new-unknown', 'old-loaded', 'old-unknown', 'loaded-before-unregister', 'unknown-before-unregister'):
                    assert not any('--unregister-helper' in c for c in calls)
                if mode in ('no-marker', 'bad-marker', 'on-cancel', 'connect-cancel', 'allow-cancel'):
                    assert sum('--helper-status' in c for c in calls) == 1
            assert not any('--register-helper' in c or '--owner-approve' in c or '--owner-start' in c for c in calls)
            if (p / 'run-started.json').exists():
                count = len(calls)
                try: identity.run(p, g, u); raise AssertionError('Replay allowed')
                except RuntimeError: pass
                assert len(calls) == count
        assert u.tree(protected) == supplied
print('Fresh identity: 25 composition models passed; no real native/system/hardware actions.')
