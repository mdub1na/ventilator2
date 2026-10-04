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
READ_ONLY_SOURCE = "owner-profile-update-resume"
READ_ONLY_SNAPSHOT = "helper-read-only-approval"
READ_ONLY_BACKUP = Path("/Applications/Ventilator-before-profile-fix.bundle-backup")
READ_ONLY_MACHINE = {"model": "Mac15,7", "version": "27.0.1", "build": "26A434"}


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def digest(path):
    for part in (path, *path.parents):
        if stat.S_ISLNK(part.lstat().st_mode):
            raise RuntimeError(f"Alias refused: {part}")
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError(f"Regular file required: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_files(path):
    return {str(p.relative_to(path)): digest(p) for p in sorted(path.rglob("*")) if p.is_file() or p.is_symlink()}


def machine():
    commands = {"model": ["/usr/sbin/sysctl", "-n", "hw.model"],
                "version": ["/usr/bin/sw_vers", "-productVersion"], "build": ["/usr/bin/sw_vers", "-buildVersion"]}
    return {key: subprocess.check_output(command, text=True, timeout=5).strip() for key, command in commands.items()}


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


def unstarted_job_absent():
    metadata = runtime_metadata()
    if metadata.get("lstatErrno") != 2:
        raise RuntimeError("Runtime state exists or cannot be inspected; system permission cycle refused")
    result = subprocess.run(["/bin/launchctl", "print", "system/dev.ventilator.helper"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
    if result.returncode != 113:
        raise RuntimeError("Job exists or its absence is uncertain; system permission cycle refused")
    return metadata


def approval_prerequisite(repo):
    previous = repo / ".build/helper-registration-diagnostics"
    manifest = check(previous)
    result = json.loads((previous / "result.json").read_text())
    if (result.get("scriptSHA256") != manifest["scriptSHA256"] or result.get("planSHA256") != manifest["planSHA256"] or
            result.get("installedFingerprint") != manifest["installedFingerprint"] or
            result.get("hardwareWritesExecuted") != 0 or result.get("steps", {}).get("launchd", {}).get("exitCode") != 113):
        raise RuntimeError("Exact previous administrative snapshot required")
    if (result.get("runtimeBefore", {}).get("lstatErrno") != 2 or
            result.get("runtimeAfter", {}).get("lstatErrno") != 2 or
            result["steps"]["launchd"] != json.loads((previous / "launchd.json").read_text()) or
            result["steps"]["btm"] != json.loads((previous / "btm.json").read_text())):
        raise RuntimeError("Previous runtime absence and matching step records required")
    btm = result.get("steps", {}).get("btm", {})
    if btm.get("exitCode") != 0 or btm.get("complete") is not True or btm.get("formatRecognized") is not True:
        raise RuntimeError("Complete recognized administrative BTM snapshot required")
    parents = {r["uid"]: r["fields"] for r in btm.get("records", [])
               if r["fields"].get("Identifier") == "2.dev.ventilator.macos"}
    for uid in (-2, os.getuid()):
        if (parents.get(uid, {}).get("URL") != "/Applications/Ventilator.app" or
                "pending authorization" not in parents.get(uid, {}).get("Disposition", "")):
            raise RuntimeError("Canonical pending app records for this owner required")
    children = [r["fields"] for r in btm["records"] if r["fields"].get("Identifier") == "16.dev.ventilator.helper"]
    if (len(children) != 1 or children[0].get("Parent Identifier") != "2.dev.ventilator.macos" or
            children[0].get("URL") != "Contents/Library/LaunchDaemons/dev.ventilator.helper.plist" or
            children[0].get("Executable Path") != "Contents/MacOS/VentilatorHelper" or
            not children[0].get("Disposition", "").startswith("[enabled, allowed,")):
        raise RuntimeError("Exact helper/parent association required")
    paths = ["snapshot.py", "PLAN.md", "manifest.json", "started.json", "launchd.json", "btm.json", "result.json"]
    return {"ownerUID": os.getuid(), "sourceFilesSHA256": {name: digest(previous / name) for name in paths}}


def prepare(repo, approval=False):
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
    prerequisite = approval_prerequisite(repo) if approval else None
    if approval:
        unstarted_job_absent()
    package = repo / (".build/helper-registration-approval" if approval else ".build/helper-registration-diagnostics")
    package.mkdir(mode=0o700)
    shutil.copyfile(Path(__file__), package / "snapshot.py")
    plan_name = "helper-registration-approval.md" if approval else "helper-registration-diagnostics.md"
    shutil.copyfile(repo / "docs" / plan_name, package / "PLAN.md")
    save(package / "manifest.json", {
        "preparedAt": now(), "installedFingerprint": fingerprint,
        "ownerFilesSHA256": {name: digest(owner / name) for name in sorted(names)},
        "scriptSHA256": digest(package / "snapshot.py"), "planSHA256": digest(package / "PLAN.md"),
        "commands": COMMANDS, "hardwareWritesExecuted": 0,
        "purpose": "oneSystemApprovalCycle" if approval else "readOnlySnapshot",
        "approvalPrerequisite": prerequisite,
    })
    print(f"Prepared owner system session: {package}")


def prepare_read_only(repo, installed=Path("/Applications/Ventilator.app")):
    if os.geteuid() == 0:
        raise RuntimeError("Prepare as the ordinary developer, without sudo")
    source = repo / ".build" / READ_ONLY_SOURCE
    source_files = tree_files(source)
    backup_files = tree_files(READ_ONLY_BACKUP)
    manifest = json.loads((source / "manifest.json").read_text())
    expected = {"Ventilator.app", "manifest.json", "PLAN.md", "session.py", "qualification-started.json",
                "sealed.json", "update-started.json", "removal-started.json", "removal-completed.json",
                "replacement-started.json", "replacement-completed.json", "registration-started.json", "registration-completed.json"}
    if {p.name for p in source.iterdir()} != expected or manifest.get("readOnlyUpdate") is not True or \
            manifest.get("readOnlyMachine") != READ_ONLY_MACHINE or machine() != READ_ONLY_MACHINE:
        raise RuntimeError("Exact stopped read-only update on the pinned unsupported machine required")
    for name, expected_digest in manifest["packageFiles"].items():
        if name not in ("PLAN.md", "session.py") or digest(source / name) != expected_digest:
            raise RuntimeError("Stopped source binding changed")
    if set(manifest["packageFiles"]) != {"PLAN.md", "session.py"}:
        raise RuntimeError("Incomplete source binding")
    seal = json.loads((source / "sealed.json").read_text())
    replacement = json.loads((source / "replacement-completed.json").read_text())
    registration = json.loads((source / "registration-completed.json").read_text())
    fingerprint = {key: digest(source / "Ventilator.app" / name) for key, name in INSTALLED_FILES.items()}
    previous = manifest["installedReplacement"]
    if (seal.get("fingerprint") != fingerprint or seal.get("positiveRevocation") is not True or
            seal.get("certificateSHA1") != manifest.get("certificateSHA1") or seal.get("teamIdentifier") != manifest.get("teamIdentifier") or
            replacement != {"fingerprint": fingerprint, "previous": previous, "hardwareWritesExecuted": 0} or
            registration.get("fingerprint") != fingerprint or registration.get("registration") != "requiresApproval" or
            registration.get("hardwareControlAvailable") is not False or
            any(registration.get(key) is not True for key in ["trustedBundle", "rootOwned", "installedLocation"])):
        raise RuntimeError("Completed read-only replacement and pending registration required")
    if {key: digest(installed / name) for key, name in INSTALLED_FILES.items()} != fingerprint or \
            {key: digest(READ_ONLY_BACKUP / name) for key, name in INSTALLED_FILES.items()} != previous:
        raise RuntimeError("Exact installed copy and previous backup required")
    if runtime_metadata().get("lstatErrno") != 2:
        raise RuntimeError("Runtime must remain absent before this diagnostic session")
    package = repo / ".build" / READ_ONLY_SNAPSHOT
    package.mkdir(mode=0o700)
    shutil.copyfile(Path(__file__), package / "snapshot.py")
    shutil.copyfile(repo / "docs/helper-read-only-approval.md", package / "PLAN.md")
    if tree_files(source) != source_files or tree_files(READ_ONLY_BACKUP) != backup_files:
        raise RuntimeError("Source or backup changed while preparing; preserve package")
    save(package / "manifest.json", {
        "preparedAt": now(), "purpose": "readOnlyApprovalInspection", "ownerUID": os.getuid(),
        "ownerSource": READ_ONLY_SOURCE, "ownerFilesSHA256": source_files,
        "installedFingerprint": fingerprint, "backupFilesSHA256": backup_files,
        "scriptSHA256": digest(package / "snapshot.py"), "planSHA256": digest(package / "PLAN.md"),
        "commands": COMMANDS, "readOnlyMachine": READ_ONLY_MACHINE, "hardwareWritesExecuted": 0,
    })
    check(package, installed=installed)
    print(f"Prepared owner read-only consent inspection: {package}")


def check(package, installed=Path("/Applications/Ventilator.app")):
    manifest = json.loads((package / "manifest.json").read_text())
    if digest(package / "snapshot.py") != manifest["scriptSHA256"] or digest(package / "PLAN.md") != manifest["planSHA256"]:
        raise RuntimeError("Diagnostic script/plan changed")
    if manifest["commands"] != COMMANDS or manifest["hardwareWritesExecuted"] != 0:
        raise RuntimeError("Diagnostic scope changed")
    read_only = manifest.get("purpose") == "readOnlyApprovalInspection"
    if read_only and (manifest.get("ownerSource") != READ_ONLY_SOURCE or manifest.get("ownerUID") != os.getuid() or
                      manifest.get("readOnlyMachine") != READ_ONLY_MACHINE or machine() != READ_ONLY_MACHINE):
        raise RuntimeError("Read-only diagnostic owner/machine binding changed")
    owner = package.parent / (READ_ONLY_SOURCE if read_only else "owner-session")
    for name, expected in manifest["ownerFilesSHA256"].items():
        if digest(owner / name) != expected:
            raise RuntimeError(f"Owner file changed: {name}")
    actual = {str(p.relative_to(owner)) for p in owner.rglob("*") if p.is_file() or p.is_symlink()}
    if actual != set(manifest["ownerFilesSHA256"]):
        raise RuntimeError("Owner session advanced; preserve state and diagnose")
    if {key: digest(installed / name) for key, name in INSTALLED_FILES.items()} != manifest["installedFingerprint"]:
        raise RuntimeError("Installed fingerprint changed")
    if manifest.get("purpose") == "oneSystemApprovalCycle":
        proof = manifest["approvalPrerequisite"]
        if proof["ownerUID"] != os.getuid():
            raise RuntimeError("The original owner account is required")
        previous = package.parent / "helper-registration-diagnostics"
        for name, expected in proof["sourceFilesSHA256"].items():
            if digest(previous / name) != expected:
                raise RuntimeError(f"Previous administrative evidence changed: {name}")
    elif read_only:
        if tree_files(READ_ONLY_BACKUP) != manifest["backupFilesSHA256"]:
            raise RuntimeError("Previous backup changed")
    elif manifest.get("purpose", "readOnlySnapshot") != "readOnlySnapshot":
        raise RuntimeError("Unknown diagnostic purpose")
    return manifest


def owner_terminal():
    if os.geteuid() == 0 or not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RuntimeError("Run this one explicit action in the owner's non-root Terminal, without sudo")


def collect(package):
    owner_terminal()
    manifest = check(package)
    approval = manifest.get("purpose") == "oneSystemApprovalCycle"
    read_only = manifest.get("purpose") == "readOnlyApprovalInspection"
    if approval:
        unstarted_job_absent()
    if read_only and runtime_metadata().get("lstatErrno") != 2:
        raise RuntimeError("Runtime exists or cannot be inspected; preserve state before owner action")
    # Exclusive marker precedes the first privileged command. A stopped attempt is never replayed.
    save(package / "started.json", {"startedAt": now(), "scriptSHA256": manifest["scriptSHA256"], "hardwareWritesExecuted": 0})
    print((package / "PLAN.md").read_text(), flush=True)
    report = {"startedAt": now(), "installedFingerprint": manifest["installedFingerprint"],
              "scriptSHA256": manifest["scriptSHA256"], "planSHA256": manifest["planSHA256"],
              "runtimeBefore": runtime_metadata(), "hardwareWritesExecuted": 0, "steps": {}}
    if approval:
        answer = input("One Ventilator off/on cycle in System Settings, authenticate if prompted; then type DONE here: ")
        if answer != "DONE":
            raise RuntimeError("Owner cycle not confirmed; no administrative snapshot requested")
        report["ownerActionReported"] = "One off/on cycle of Ventilator; authentication if prompted"
        save(package / "owner-action.json", {"reportedAt": now(), "action": report["ownerActionReported"], "hardwareWritesExecuted": 0})
    if read_only:
        answer = input("Inspect only Ventilator's Background Items Added notification. ALLOW after Allow/admin confirmation; NONE if absent; anything else cancels: ")
        if answer not in ("ALLOW", "NONE"):
            raise RuntimeError("Inspection cancelled; no administrative snapshot or helper request")
        report["ownerActionReported"] = answer
        save(package / "owner-action.json", {"reportedAt": now(), "action": answer, "hardwareWritesExecuted": 0})
        check(package)
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
    if read_only:
        report["helperVerified"] = False
        report["outcome"] = "diagnosticIncomplete" if report.get("stoppedAt") else "systemApprovalPending"
        loaded = not report.get("stoppedAt") and report["steps"]["launchd"]["exitCode"] == 0
        if loaded and report["runtimeAfter"].get("lstatErrno") != 2:
            report["outcome"] = "runtimeStatePresent"
        elif loaded:
            report["outcome"] = "rootPeerUnverified"
            # Exactly one bounded diagnostic XPC request, only on the pinned unsupported machine.
            executable = Path("/Applications/Ventilator.app/Contents/MacOS/Ventilator")
            command = [str(executable), "--verify-installed-helper"]
            try:
                result = subprocess.run(command, capture_output=True, text=True, timeout=10)
                step = {"exitCode": result.returncode, "stderr": result.stderr}
                text = result.stdout or result.stderr.removeprefix("Ventilator installation: ")
                try:
                    reply = json.loads(text)
                except ValueError:
                    reply = None
                if reply is not None:
                    step["reply"] = reply
                    if (result.returncode == 0 and reply.get("helperVerified") is True and reply.get("error") is None and
                            reply.get("registration") == "enabled" and reply.get("hardwareControlAvailable") is False and
                            reply.get("fingerprint") == manifest["installedFingerprint"] and
                            all(reply.get(key) is True for key in ["trustedBundle", "rootOwned", "installedLocation"])):
                        report["helperVerified"] = True
                        report["outcome"] = "readOnlyHelperVerified"
            except subprocess.TimeoutExpired:
                step = {"timedOut": True}
            report["steps"]["verification"] = step
            save(package / "verification.json", step)
            check(package)
        report["runtimeAfter"] = runtime_metadata()
    save(package / "result.json", report)
    print(f"Saved read-only snapshot: {package / 'result.json'}")
    if read_only:
        print(f"Outcome: {report['outcome']}; helperVerified={report['helperVerified']}. No hardware experiment.")
    print("Stop here and report that the snapshot was saved. Do not repeat collection/setup/register/ready.")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("prepare", "prepare-approval", "prepare-read-only", "collect"):
        raise RuntimeError("Use prepare from the repository or collect from the frozen diagnostic package")
    source = Path(__file__).absolute()
    if sys.argv[1] in ("prepare", "prepare-approval"):
        prepare(source.parent.parent, approval=sys.argv[1] == "prepare-approval")
    elif sys.argv[1] == "prepare-read-only":
        prepare_read_only(source.parent.parent)
    elif source.parent.name in ("helper-registration-diagnostics", "helper-registration-approval", READ_ONLY_SNAPSHOT):
        collect(source.parent)
    else:
        raise RuntimeError("Collect only from the prepared .build/helper-registration-diagnostics/snapshot.py")


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f"STOP: {error or 'Interrupted'}. Preserve the snapshot; no retry.", file=sys.stderr)
        sys.exit(1)
