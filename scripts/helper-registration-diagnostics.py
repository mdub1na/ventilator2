#!/usr/bin/env python3
"""One owner-terminal snapshot of launchd and BTM; no service mutation or app/helper execution."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
from datetime import datetime


COMMANDS = {
    "launchd": ["/usr/bin/sudo", "--", "/usr/bin/perl", "-e",
                'alarm 5; exec "/bin/launchctl", "print", "system/dev.ventilator.helper"; die "exec failed\\n";'],
    "btm": ["/usr/bin/sudo", "--", "/usr/bin/perl", "-e",
            'alarm 20; exec "/usr/bin/sfltool", "dumpbtm"; die "exec failed\\n";'],
}
INSTALLED_FILES = {
    "applicationSHA256": "Contents/MacOS/Ventilator",
    "helperSHA256": "Contents/MacOS/VentilatorHelper",
    "launchDaemonSHA256": "Contents/Library/LaunchDaemons/dev.ventilator.helper.plist",
}
BTM_IDENTIFIERS = {"2.dev.ventilator.macos", "16.dev.ventilator.helper"}
BTM_FIELDS = {"UUID", "Name", "Developer Name", "Team Identifier", "Type", "Flags", "Disposition",
              "Identifier", "URL", "Executable Path", "Generation", "Last Use", "Parent Identifier", "Bundle Identifier"}


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def digest(path):
    for part in (path, *path.parents):
        if stat.S_ISLNK(part.lstat().st_mode):
            raise RuntimeError(f"Alias refused: {part}")
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError(f"Regular file required: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write("\n")


def runtime_metadata():
    path = Path("/Library/Application Support/Ventilator")
    try:
        value = path.lstat()
        return {"path": str(path), "exists": True, "uid": value.st_uid,
                "mode": oct(stat.S_IMODE(value.st_mode)), "symlink": stat.S_ISLNK(value.st_mode)}
    except OSError as error:
        return {"path": str(path), "lstatErrno": error.errno, "exists": False if error.errno == 2 else None}


def scoped_btm(text):
    records, uid, fields = [], None, {}

    def flush():
        if fields.get("Identifier") in BTM_IDENTIFIERS:
            records.append({"uid": uid, "fields": dict(fields)})
        fields.clear()

    for line in text.splitlines():
        header = re.match(r"\s*Records for UID (-?\d+)\s*:", line)
        if header:
            flush()
            uid = int(header.group(1))
        elif re.fullmatch(r" {0,2}#\d+:\s*", line):
            flush()
        elif ":" in line:
            key, value = line.strip().split(":", 1)
            if key in BTM_FIELDS:
                fields[key] = value.strip()
    flush()
    return records


def prepare(repo):
    if os.geteuid() == 0:
        raise RuntimeError("Prepare as the ordinary developer, without sudo")
    owner = repo / ".build/owner-session"
    baseline = json.loads((repo / ".build/continued-owner-package-audit.json").read_text())
    for name, expected in baseline.items():
        if digest(owner / name) != expected:
            raise RuntimeError(f"Sealed owner file changed: {name}")
    names = set(baseline) | {"registration-started.json", "registration-completed.json"}
    actual = {str(p.relative_to(owner)) for p in owner.rglob("*") if p.is_file() or p.is_symlink()}
    if actual != names:
        raise RuntimeError("Unexpected owner files; preserve state and diagnose")
    fingerprint = json.loads((owner / "sealed.json").read_text())["fingerprint"]
    installed = Path("/Applications/Ventilator.app")
    if {key: digest(installed / name) for key, name in INSTALLED_FILES.items()} != fingerprint:
        raise RuntimeError("Installed fingerprint changed")
    package = repo / ".build/helper-registration-diagnostics"
    package.mkdir(mode=0o700)
    shutil.copyfile(Path(__file__), package / "snapshot.py")
    shutil.copyfile(repo / "docs/helper-registration-diagnostics.md", package / "PLAN.md")
    save(package / "manifest.json", {
        "preparedAt": now(), "installedFingerprint": fingerprint,
        "ownerFilesSHA256": {name: digest(owner / name) for name in sorted(names)},
        "scriptSHA256": digest(package / "snapshot.py"), "planSHA256": digest(package / "PLAN.md"),
        "commands": COMMANDS, "hardwareWritesExecuted": 0,
    })
    print(f"Prepared read-only diagnostic package: {package}")


def check(package, installed=Path("/Applications/Ventilator.app")):
    manifest = json.loads((package / "manifest.json").read_text())
    if digest(package / "snapshot.py") != manifest["scriptSHA256"] or digest(package / "PLAN.md") != manifest["planSHA256"]:
        raise RuntimeError("Diagnostic script/plan changed")
    if manifest["commands"] != COMMANDS or manifest["hardwareWritesExecuted"] != 0:
        raise RuntimeError("Diagnostic scope changed")
    owner = package.parent / "owner-session"
    for name, expected in manifest["ownerFilesSHA256"].items():
        if digest(owner / name) != expected:
            raise RuntimeError(f"Owner file changed: {name}")
    actual = {str(p.relative_to(owner)) for p in owner.rglob("*") if p.is_file() or p.is_symlink()}
    if actual != set(manifest["ownerFilesSHA256"]):
        raise RuntimeError("Owner session advanced; preserve state and diagnose")
    if {key: digest(installed / name) for key, name in INSTALLED_FILES.items()} != manifest["installedFingerprint"]:
        raise RuntimeError("Installed fingerprint changed")
    return manifest


def owner_terminal():
    if os.geteuid() == 0 or not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RuntimeError("Run this one explicit action in the owner's non-root Terminal, without sudo")


def collect(package):
    owner_terminal()
    manifest = check(package)
    # Exclusive marker precedes the first privileged command. A stopped attempt is never replayed.
    save(package / "started.json", {"startedAt": now(), "scriptSHA256": manifest["scriptSHA256"], "hardwareWritesExecuted": 0})
    print((package / "PLAN.md").read_text(), flush=True)
    report = {"startedAt": now(), "installedFingerprint": manifest["installedFingerprint"],
              "scriptSHA256": manifest["scriptSHA256"], "planSHA256": manifest["planSHA256"],
              "runtimeBefore": runtime_metadata(), "hardwareWritesExecuted": 0, "steps": {}}
    for name in ("launchd", "btm"):
        print(f"Read-only {name}: sudo authentication in this Terminal; then bounded system read.", flush=True)
        # Inherit stderr so sudo's password prompt and native diagnostics remain visible.
        # The alarm runs after authentication, survives exec and kills the utility itself.
        result = subprocess.run(COMMANDS[name], stdout=subprocess.PIPE, text=True, errors="replace")
        step = {"exitCode": result.returncode, "completedAt": now(), "alarmExpired": result.returncode in (-14, 142)}
        if name == "btm":
            step.update({"records": scoped_btm(result.stdout), "rawOtherApplicationsSaved": False,
                         "complete": result.returncode == 0,
                         "formatRecognized": bool(re.search(r"Records for UID -?\d+\s*:", result.stdout))})
        else:
            step["stdout"] = result.stdout
        report["steps"][name] = step
        save(package / f"{name}.json", step)
        if result.returncode not in ((0, 113) if name == "launchd" else (0,)):
            report["stoppedAt"] = name
            break
    report["runtimeAfter"] = runtime_metadata()
    check(package)  # Fail closed if the owner/installed package changed during collection.
    save(package / "result.json", report)
    print(f"Saved read-only snapshot: {package / 'result.json'}")
    print("Stop here and report that the snapshot was saved. Do not repeat collection/setup/register/ready.")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("prepare", "collect"):
        raise RuntimeError("Use prepare from the repository or collect from the frozen diagnostic package")
    source = Path(__file__).absolute()
    if sys.argv[1] == "prepare":
        prepare(source.parent.parent)
    elif source.parent.name == "helper-registration-diagnostics":
        collect(source.parent)
    else:
        raise RuntimeError("Collect only from the prepared .build/helper-registration-diagnostics/snapshot.py")


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f"STOP: {error or 'Interrupted'}. Preserve the snapshot; no retry.", file=sys.stderr)
        sys.exit(1)
