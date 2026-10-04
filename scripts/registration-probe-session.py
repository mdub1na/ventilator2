#!/usr/bin/env python3
"""One owner-run isolated SMAppService test. All system mutations target only the probe."""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from datetime import datetime
from pathlib import Path

APP_ID = "dev.ventilator.registration-probe"
DAEMON_ID = APP_ID + ".daemon"
CERTIFICATE = "4895C06FF7407EAF5F350E78CF23D0B41AD466C9"
TEAM = "4659S5GD6X"
INSTALLED = Path("/Applications/Ventilator Registration Probe.app")
MACHINE = {"model": "Mac15,7", "version": "27.0.1", "build": "26A434"}
PLAN = "docs/registration-probe-owner.md"

def now(): return datetime.now().astimezone().isoformat()

def digest(path):
    path = Path(path)
    if path.resolve() != path.absolute() or not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError(f"Unaliased regular file required: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()

def tree(path):
    return {str(p.relative_to(path)): digest(p) for p in sorted(path.rglob("*")) if p.is_file() or p.is_symlink()}

def save(path, value):
    with path.open("x") as output:
        json.dump(value, output, ensure_ascii=False, indent=2); output.write("\n")

def execute(argv, timeout=30):
    return subprocess.run([str(x) for x in argv], text=True, capture_output=True, timeout=timeout)

def require_success(result):
    if result.returncode != 0: raise RuntimeError(f"Command exited {result.returncode}: {(result.stderr or '').strip()}")
    return result

def machine():
    return {k: require_success(execute(command, timeout=5)).stdout.strip() for k, command in {
        "model": ["/usr/sbin/sysctl", "-n", "hw.model"], "version": ["/usr/bin/sw_vers", "-productVersion"],
        "build": ["/usr/bin/sw_vers", "-buildVersion"]}.items()}

def absent(path):
    try: path.lstat()
    except FileNotFoundError: return True
    return False

def protected_paths(repo):
    baseline = json.loads((repo / ".build/bundle-inspection-preservation-before.json").read_text())
    roots = {key: Path("/Applications/Ventilator.app") if key == "installed" else Path("/Applications/Ventilator-before-profile-fix.bundle-backup") if key == "backup" else repo / ".build" / key for key in baseline}
    for key, path in roots.items():
        if tree(path) != baseline[key]: raise RuntimeError(f"Protected Ventilator package changed: {key}")
    roots["helper-after-restart"] = repo / ".build/helper-after-restart"
    restart_proof = json.loads((repo / "docs/research/evidence/after-restart-result.json").read_text())
    if tree(roots["helper-after-restart"]) != restart_proof["packageFilesSHA256"]:
        raise RuntimeError("Completed post-restart proof changed")
    return {str(path): tree(path) for path in roots.values()}

def prepare(repo):
    if os.geteuid() == 0: raise RuntimeError("Prepare without sudo")
    if machine() != MACHINE or not absent(INSTALLED): raise RuntimeError("Pinned machine and absent probe installation required")
    if not absent(Path("/Library/Application Support/Ventilator")): raise RuntimeError("Preserve existing Ventilator runtime")
    source = repo / ".build/registration-probe-build/Ventilator Registration Probe.app"
    before = protected_paths(repo)
    package = repo / ".build/registration-probe-owner"
    package.mkdir(mode=0o700)
    shutil.copytree(source, package / "payload.app")
    shutil.copyfile(Path(__file__), package / "session.py")
    shutil.copyfile(repo / PLAN, package / "PLAN.md")
    save(package / "manifest.json", {"purpose": "isolatedRegistrationProbe", "sessionPath": str(package), "ownerUID": os.getuid(),
         "preparedAt": now(), "machine": MACHINE, "certificate": CERTIFICATE, "team": TEAM, "installedPath": str(INSTALLED),
         "bundleFilesSHA256": tree(package / "payload.app"), "protectedFilesSHA256": before,
         "scriptSHA256": digest(package / "session.py"), "planSHA256": digest(package / "PLAN.md"), "hardwareWrites": []})
    check(package)
    print(f"Prepared isolated owner probe: {package}. No signing, registration or hardware actions.")

def check(package):
    manifest = json.loads((package / "manifest.json").read_text())
    if (os.geteuid() == 0 or package.resolve() != package.absolute() or stat.S_IMODE(package.stat().st_mode) != 0o700 or
        manifest.get("purpose") != "isolatedRegistrationProbe" or manifest.get("sessionPath") != str(package) or
        manifest.get("ownerUID") != os.getuid() or manifest.get("machine") != MACHINE or machine() != MACHINE or
        manifest.get("certificate") != CERTIFICATE or manifest.get("team") != TEAM or manifest.get("installedPath") != str(INSTALLED) or
        manifest.get("hardwareWrites") != [] or digest(package / "session.py") != manifest.get("scriptSHA256") or
        digest(package / "PLAN.md") != manifest.get("planSHA256")):
        raise RuntimeError("Owner/machine/script/plan/probe binding changed")
    for path, expected in manifest["protectedFilesSHA256"].items():
        if tree(Path(path)) != expected: raise RuntimeError(f"Protected Ventilator files changed: {path}")
    if not absent(Path("/Library/Application Support/Ventilator")): raise RuntimeError("Ventilator runtime appeared; preserve state")
    stage = "sealed.json" if (package / "sealed.json").exists() else "signature-ready.json"
    expected = json.loads((package / stage).read_text())["fingerprint"] if (package / stage).exists() else manifest["bundleFilesSHA256"]
    if tree(package / "payload.app") != expected: raise RuntimeError("Probe payload changed")
    return manifest

def owner_terminal():
    if os.geteuid() == 0 or not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RuntimeError("Use the owner's ordinary non-root Terminal, without outer sudo")

def privileged(argv, alarm=20):
    # Authentication completes before perl starts the bounded system utility.
    result = subprocess.run([str(x) for x in ["/usr/bin/sudo", "--", "/usr/bin/perl", "-e", f'alarm {alarm}; exec @ARGV; die "exec failed\\n";', *argv]],
                            text=True, stdout=subprocess.PIPE, stderr=None, timeout=180)
    return result

def root_job(package, name, expected=None):
    result = privileged(["/bin/launchctl", "print", "system/" + DAEMON_ID], alarm=5)
    save(package / (name + ".json"), {"observedAt": now(), "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    if result.returncode not in (0, 113) or (expected is not None and result.returncode != expected):
        raise RuntimeError(f"Probe job read {name}: exit {result.returncode}; preserve state")
    return result.returncode

def inspect(executable, bundle, qualify=False):
    result = require_success(execute([executable, "--qualify-probe" if qualify else "--inspect-probe", bundle], timeout=30))
    value = json.loads(result.stdout)
    if not isinstance(value, dict) or value.get("team") != TEAM or value.get("certificate") != CERTIFICATE or value.get("positiveRevocation") != qualify:
        raise RuntimeError("Invalid static probe reply")
    if value.get("fingerprint") != tree(bundle): raise RuntimeError("Static signed fingerprint mismatch")
    return value

def installed_check(package):
    check(package)
    seal = json.loads((package / "sealed.json").read_text())
    if seal.get("positiveRevocation") is not True or tree(INSTALLED) != seal["fingerprint"]:
        raise RuntimeError("Exact qualified installed probe required")
    for path in [INSTALLED, *INSTALLED.rglob("*")]:
        meta = path.lstat()
        if meta.st_uid != 0 or meta.st_mode & 0o022 or stat.S_ISLNK(meta.st_mode): raise RuntimeError("Root-owned unaliased probe required")

def run(package):
    owner_terminal(); check(package)
    if not absent(INSTALLED): raise RuntimeError("Probe already installed; no replacement")
    print((package / "PLAN.md").read_text(), flush=True)
    save(package / "run-started.json", {"startedAt": now(), "hardwareWritesExecuted": 0})
    app = package / "payload.app"; binary = app / "Contents/MacOS/RegistrationProbe"
    daemon = app / "Contents/MacOS/RegistrationProbeDaemon"
    for path, extra in [(daemon, ["--identifier", DAEMON_ID]), (app, [])]:
        result = require_success(execute(["/usr/bin/codesign", "--force", "--sign", CERTIFICATE, "--timestamp=none", *extra, path], timeout=180))
        print(result.stderr.strip(), flush=True)
    ready = inspect(binary, app)
    save(package / "signature-ready.json", ready)
    seal = inspect(binary, app, qualify=True)
    save(package / "sealed.json", seal)
    print("Подписанные хеши перед установкой: " + json.dumps(seal["fingerprint"], ensure_ascii=False), flush=True)
    check(package)
    root_job(package, "job-before-install", expected=113)
    if not absent(INSTALLED): raise RuntimeError("Probe target appeared; no overwrite")
    require_success(privileged(["/bin/mkdir", "-m", "755", INSTALLED]))
    require_success(privileged(["/usr/bin/ditto", app, INSTALLED]))
    require_success(privileged(["/usr/sbin/chown", "-R", "root:wheel", INSTALLED]))
    require_success(privileged(["/bin/chmod", "-R", "go-w", INSTALLED]))
    installed_check(package)
    save(package / "installation.json", {"fingerprint": tree(INSTALLED), "hardwareWritesExecuted": 0})
    require_success(execute(["/usr/bin/open", "-n", "-a", INSTALLED, "--args", "--owner-probe-session", package], timeout=10))
    answer = input("В probe нажмите Зарегистрировать один раз. ALLOW после Allow/admin подтверждения; NONE если запроса нет; другое отменяет: ")
    if answer not in ("ALLOW", "NONE"): raise RuntimeError("Owner cancelled; use the separate cleanup action if installed")
    installed_check(package)
    registration = json.loads((package / "registration.json").read_text())
    result = require_success(execute([INSTALLED / "Contents/MacOS/RegistrationProbe", "--probe-status", package], timeout=10))
    status_reply = json.loads(result.stdout)
    if not isinstance(status_reply, dict) or status_reply.get("registration") not in ("enabled", "requiresApproval", "notRegistered", "notFound", "unknown"):
        raise RuntimeError("Unknown native registration reply")
    job = root_job(package, "job-after-registration")
    save(package / "result.json", {"completedAt": now(), "ownerActionReported": answer, "registrationAttempt": registration,
         "registrationStatus": status_reply["registration"], "rootJobLoaded": job == 0,
         "isolatedBootstrapConfirmed": status_reply["registration"] == "enabled" and job == 0,
         "ventilatorRootPeerVerified": False, "hardwareWritesExecuted": 0,
         "interpretation": "Tests only this new GUI identity; does not repair or establish cause for Ventilator."})
    cleanup(package)
    print(f"Saved isolated probe result: {package / 'result.json'}. Probe removed from /Applications. Stop and report.")

def cleanup(package):
    owner_terminal()
    if (package / "cleanup-started.json").exists(): raise RuntimeError("Cleanup already attempted; preserve state, no retry")
    installed_check(package)
    if not (package / "installation.json").exists(): raise RuntimeError("No completed isolated installation; preserve partial state")
    result = require_success(execute([INSTALLED / "Contents/MacOS/RegistrationProbe", "--probe-cleanup", package], timeout=10))
    reply = json.loads(result.stdout)
    if not isinstance(reply, dict) or reply.get("diagnostic") is not None or reply.get("registration") not in ("notRegistered", "notFound"):
        raise RuntimeError("Probe cleanup not confirmed; do not repeat")
    root_job(package, "job-after-cleanup", expected=113)
    answer = input("Закройте только окно Ventilator — отдельная проверка регистрации. Затем введите CLOSED: ")
    if answer != "CLOSED": raise RuntimeError("Probe window closure not confirmed; preserve state")
    if (package / "gui.json").exists():
        pid = json.loads((package / "gui.json").read_text())["pid"]
        if not isinstance(pid, int) or pid <= 0: raise RuntimeError("Invalid GUI process identifier")
        try: os.kill(pid, 0)  # Liveness check only; no signal is delivered.
        except ProcessLookupError: pass
        except PermissionError: raise RuntimeError("GUI process exit unknown; preserve state")
        else: raise RuntimeError("Probe GUI still running; preserve state")
    installed_check(package)
    if not absent(package / "retired.bundle"): raise RuntimeError("Archive exists; no overwrite")
    require_success(privileged(["/bin/mv", INSTALLED, package / "retired.bundle"]))
    if not absent(INSTALLED) or tree(package / "retired.bundle") != json.loads((package / "sealed.json").read_text())["fingerprint"]:
        raise RuntimeError("Probe archival not confirmed")
    check(package)
    save(package / "cleanup-completed.json", {"completedAt": now(), "registeredProbeRemoved": True, "archivedExactSignedBundle": True, "hardwareWritesExecuted": 0})

def main():
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    if action == "prepare": prepare(Path(__file__).resolve().parent.parent)
    elif action in ("run", "cleanup", "check"):
        package = Path(__file__).resolve().parent
        if action == "check": check(package); print("Pinned isolated probe and protected Ventilator files match; no action.")
        elif action == "run": run(package)
        else: cleanup(package)
    else: raise RuntimeError("Use source prepare or frozen check/run/cleanup")

if __name__ == "__main__":
    try: main()
    except Exception as error:
        print(f"STOP: {error}. Preserve the package; no retry. Follow PLAN.md.", file=sys.stderr); sys.exit(78)
