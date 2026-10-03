#!/usr/bin/env python3
"""Prepare locally; explicit owner commands sign/install/register/run. No SMC payload interface."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

CERTIFICATE = "4895C06FF7407EAF5F350E78CF23D0B41AD466C9"
TEAM = "4659S5GD6X"
INSTALLED = Path("/Applications/Ventilator.app")
REPLACEMENT_STAGE = Path("/Applications/Ventilator-helper-path-staging.app")
REPLACEMENT_BACKUP = Path("/Applications/Ventilator-before-helper-path-fix.app")
LEGACY_BACKUP = Path("/Applications/Ventilator-before-registration-fix.app")
HARDWARE_ROOT = Path("/Library/Application Support/Ventilator")
ROOT = Path(__file__).resolve().parents[1] if Path(__file__).parent.name == "scripts" else None
SESSION = ROOT / ".build/owner-session" if ROOT else Path(__file__).resolve().parent
PREVIOUS_SESSION = None
SIGNED_SESSION = None
FRESH_INSTALL = False
CONTINUE_INSTALLED = False


def sha(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"Expected regular file: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(bundle):
    return {"applicationSHA256": bundle / "Contents/MacOS/Ventilator",
            "helperSHA256": bundle / "Contents/MacOS/VentilatorHelper",
            "launchDaemonSHA256": bundle / "Contents/Library/LaunchDaemons/dev.ventilator.helper.plist"}


def fingerprints(bundle):
    if bundle.is_symlink() or any(p.is_symlink() for p in bundle.rglob("*")):
        raise RuntimeError("Symlink in bundle")
    return {key: sha(path) for key, path in files(bundle).items()}


def save(name, value):
    path = SESSION / name
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write("\n")
    path.chmod(0o600)


def output(command, timeout=5):
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        details = result.stderr.strip() or result.stdout.strip() or "No diagnostic output"
        raise RuntimeError(f"{Path(str(command[0])).name} exited {result.returncode}: {details}")
    return result.stdout


def candidate(bundle):
    result = json.loads(output([files(bundle)["helperSHA256"], "--candidate-plan"]))
    hashes = fingerprints(bundle)
    assert result["hardwareWritesExecuted"] == 0
    assert not result["plan"]["readyForOwnerApproval"]
    assert result["plan"]["binaries"] == {k: hashes[k] for k in ("applicationSHA256", "helperSHA256")}
    canonical = json.dumps(result["plan"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    assert hashlib.sha256(canonical).hexdigest() == result["planSHA256"]
    return result


def package_files(directory, manifest):
    for name, digest in manifest["packageFiles"].items():
        if name not in ["session.py", "PLAN.md"] or sha(directory / name) != digest:
            raise RuntimeError(f"Package changed: {name}")
    if set(manifest["packageFiles"]) != {"session.py", "PLAN.md"}:
        raise RuntimeError("Incomplete package binding")


def check(sealed=False):
    manifest = json.loads((SESSION / "manifest.json").read_text())
    package_files(SESSION, manifest)
    if manifest.get("installedContinuation") is not None and (
            manifest["installedContinuation"] != manifest["fingerprint"] or
            manifest.get("installedReplacement") is not None or manifest.get("freshInstallation")):
        raise RuntimeError("Invalid installed continuation binding")
    reference = manifest["fingerprint"]
    if (SESSION / "signature-ready.json").exists():
        reference = json.loads((SESSION / "signature-ready.json").read_text())["fingerprint"]
    if sealed:
        reference = json.loads((SESSION / "sealed.json").read_text())["fingerprint"]
    if fingerprints(SESSION / "Ventilator.app") != reference:
        if not sealed and not manifest.get("signatureReady") and not (SESSION / "signature-ready.json").exists() and (SESSION / "sign-started.json").exists():
            raise RuntimeError("Signing started but completion is unverified. Preserve files; do not sign or install again")
        raise RuntimeError("Bundle changed")
    if sealed:
        review = json.loads((SESSION / "review.json").read_text())
        canonical = json.dumps(review, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        if hashlib.sha256(canonical).hexdigest() != (SESSION / "review.sha256").read_text().strip():
            raise RuntimeError("Review changed")
        if review["ownerInstructions"] != (SESSION / "PLAN.md").read_text():
            raise RuntimeError("Owner instructions changed")
        if review["candidate"] != candidate(SESSION / "Ventilator.app")["plan"]:
            raise RuntimeError("Signed candidate changed")
    return manifest


def package_status():
    sealed = (SESSION / "sealed.json").exists()
    manifest = check(sealed=sealed)
    signed = manifest.get("signatureReady") is True or (SESSION / "signature-ready.json").exists()
    signing_stopped = not signed and (SESSION / "sign-started.json").exists()
    qualification_stopped = not sealed and (SESSION / "qualification-started.json").exists()
    if sealed:
        if os.path.lexists(SESSION / "registration-started.json"):
            next_step = "Registration already attempted; preserve state and follow PLAN.md, do not repeat setup/register"
        elif manifest.get("installedContinuation"):
            next_step = "setup once in owner Terminal; exact signed copy is already installed"
        else:
            next_step = "Follow PLAN.md for installation; root helper is not yet verified"
    elif signing_stopped or qualification_stopped:
        next_step = "Preserve package for developer diagnosis; do not sign or qualify again"
    elif signed:
        next_step = "qualify (public certificate only); do not sign again"
    else:
        next_step = "sign once in owner Terminal, then qualify"
    return {
        "packagePath": str(SESSION),
        "installationMode": "installed" if manifest.get("installedContinuation") else
            "replacement" if manifest.get("installedReplacement") else "fresh",
        "signature": "complete" if signed else "stopped" if signing_stopped else "notStarted",
        "certificateQualification": "complete" if sealed else
            "stopped" if qualification_stopped else "notStarted",
        "fullReview": "sealed" if sealed else "notSealed",
        "fingerprint": fingerprints(SESSION / "Ventilator.app"),
        "nextStep": next_step,
    }


def signed_source():
    """Import a preserved failed signing package; never rewrite it or access the signing key."""
    manifest = json.loads((SIGNED_SESSION / "manifest.json").read_text())
    package_files(SIGNED_SESSION, manifest)
    started = json.loads((SIGNED_SESSION / "sign-started.json").read_text())
    if manifest.get("certificateSHA1") != CERTIFICATE or manifest.get("teamIdentifier") != TEAM or \
            started.get("certificateSHA1") != CERTIFICATE or started.get("hardwareWritesExecuted") != 0:
        raise RuntimeError("Unexpected source signing identity/state")
    for name in ["sealed.json", "candidate.json", "review.json", "review.sha256",
                 "replacement-started.json", "replacement-completed.json", "install-started.json", "install-completed.json",
                 "registration-started.json", "registration-completed.json", "result.json"]:
        if os.path.lexists(SIGNED_SESSION / name):
            raise RuntimeError(f"Source is not a failed, unsealed signing package: {name}")
    bundle = SIGNED_SESSION / "Ventilator.app"
    return bundle, fingerprints(bundle), {"manifestSHA256": sha(SIGNED_SESSION / "manifest.json"),
        "signStartedSHA256": sha(SIGNED_SESSION / "sign-started.json"), "packageFiles": manifest["packageFiles"],
        "originalFingerprint": manifest["fingerprint"], "installedReplacement": manifest.get("installedReplacement")}


def owner_terminal():
    if os.geteuid() == 0 or not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RuntimeError("This explicit owner action requires a non-root Terminal; do not run through the agent")


def installed_check():
    check(sealed=True)
    seal = json.loads((SESSION / "sealed.json").read_text())
    if fingerprints(INSTALLED) != seal["fingerprint"]:
        raise RuntimeError("Installed bundle differs from seal")
    return seal


def prepare():
    if ROOT is None or os.geteuid() == 0:
        raise RuntimeError("Prepare from repository without root")
    if FRESH_INSTALL and (SIGNED_SESSION is None or PREVIOUS_SESSION is not None):
        raise RuntimeError("Fresh install requires a signed source and no previous installation")
    if CONTINUE_INSTALLED and (SIGNED_SESSION is None or PREVIOUS_SESSION is not None or FRESH_INSTALL):
        raise RuntimeError("Installed continuation requires signed source without fresh/replacement mode")
    if SESSION.exists():
        raise RuntimeError("Package already exists; preserve it, use a new output for a revised package")
    instructions = (ROOT / "docs/owner-session.md").read_text()
    if len(instructions.encode()) > 12288:
        raise RuntimeError("Owner instructions exceed review budget")
    bundle = ROOT / ".build/Ventilator.app"
    imported = None
    if SIGNED_SESSION:
        bundle, signed_hashes, imported = signed_source()
    if CONTINUE_INSTALLED:
        admit_installed_continuation(signed_hashes)
    plan = candidate(bundle)
    SESSION.mkdir(mode=0o700, parents=True)
    shutil.copytree(bundle, SESSION / "Ventilator.app", symlinks=False)
    shutil.copyfile(__file__, SESSION / "session.py")
    (SESSION / "PLAN.md").write_text(instructions)
    manifest = {"schema": 1, "certificateSHA1": CERTIFICATE, "teamIdentifier": TEAM,
        "fingerprint": fingerprints(SESSION / "Ventilator.app"), "candidatePlanSHA256": plan["planSHA256"],
        "packageFiles": {n: sha(SESSION / n) for n in ["session.py", "PLAN.md"]},
        "hardwareWritesExecuted": 0, "signed": False}
    if imported:
        if fingerprints(bundle) != signed_hashes or manifest["fingerprint"] != signed_hashes:
            raise RuntimeError("Signed source changed while copying")
        source_manifest = json.loads((SIGNED_SESSION / "manifest.json").read_text())
        package_files(SIGNED_SESSION, source_manifest)
        if sha(SIGNED_SESSION / "manifest.json") != imported["manifestSHA256"] or \
                sha(SIGNED_SESSION / "sign-started.json") != imported["signStartedSHA256"]:
            raise RuntimeError("Source package changed while copying")
        manifest["signatureReady"] = True
        manifest["resumedFrom"] = imported
        if imported["installedReplacement"] is not None and not FRESH_INSTALL and not CONTINUE_INSTALLED:
            manifest["installedReplacement"] = imported["installedReplacement"]
        if FRESH_INSTALL:
            manifest["freshInstallation"] = True
        if CONTINUE_INSTALLED:
            admit_installed_continuation(signed_hashes)
            manifest["installedContinuation"] = signed_hashes
    if PREVIOUS_SESSION:
        previous = json.loads((PREVIOUS_SESSION / "sealed.json").read_text())
        if previous["certificateSHA1"] != CERTIFICATE or previous["teamIdentifier"] != TEAM or not previous["positiveRevocation"]:
            raise RuntimeError("Unexpected previous signed package")
        if fingerprints(PREVIOUS_SESSION / "Ventilator.app") != previous["fingerprint"]:
            raise RuntimeError("Previous signed package changed")
        if "installedReplacement" in manifest and manifest["installedReplacement"] != previous["fingerprint"]:
            raise RuntimeError("Previous installation conflicts with signed source")
        manifest["installedReplacement"] = previous["fingerprint"]
    save("manifest.json", manifest)
    print(f"Prepared {SESSION}. No signing, install, sudo or hardware writes.")


def sign():
    owner_terminal()
    manifest = check()
    if manifest.get("signatureReady") or os.path.lexists(SESSION / "signature-ready.json"):
        raise RuntimeError("Package is already signed; do not sign again")
    # Signing and public certificate qualification have separate completion markers.
    # A network/trust failure must never be reported as a request to sign the same code again.
    save("sign-started.json", {"certificateSHA1": CERTIFICATE, "hardwareWritesExecuted": 0})
    bundle = SESSION / "Ventilator.app"
    for path, identifier in [(files(bundle)["helperSHA256"], "dev.ventilator.helper"), (bundle, "dev.ventilator.macos")]:
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", CERTIFICATE, "--options", "runtime",
                        "--identifier", identifier, "--timestamp=none", str(path)], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(path)], check=True)
    save("signature-ready.json", {"fingerprint": fingerprints(bundle), "hardwareWritesExecuted": 0})
    print("Signing complete for app and helper. No install or SMC writes.")
    print("Next: qualify (public certificate only, no private key). Do not sign again.")


def qualify():
    # Public certificate reads and local preparation only; no Terminal/private-key/privileged action.
    manifest = check()
    if not manifest.get("signatureReady") and not (SESSION / "signature-ready.json").exists():
        raise RuntimeError("No completed signature; sign once in owner Terminal first")
    for name in ["qualification-started.json", "sealed.json", "candidate.json", "review.json", "review.sha256"]:
        if os.path.lexists(SESSION / name):
            raise RuntimeError("Qualification/sealing was already attempted; preserve package and diagnose, no retry")
    bundle = SESSION / "Ventilator.app"
    before = fingerprints(bundle)
    save("qualification-started.json", {"fingerprint": before, "hardwareWritesExecuted": 0})
    qualification = json.loads(output([files(bundle)["applicationSHA256"], "--qualify-owner-signature", bundle, CERTIFICATE], timeout=20))
    if qualification.get("certificateSHA1") != CERTIFICATE or qualification.get("teamIdentifier") != TEAM or \
            qualification.get("positiveRevocation") is not True or qualification.get("notarizationClaimed") is not False:
        raise RuntimeError("Certificate qualification failed")
    if qualification["fingerprint"] != before or fingerprints(bundle) != before:
        raise RuntimeError("Qualification fingerprint mismatch")
    plan = candidate(bundle)
    review = {"domain": "hardware", "candidate": plan["plan"], "ownerInstructions": (SESSION / "PLAN.md").read_text()}
    canonical = json.dumps(review, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if len(canonical) > 16384:
        raise RuntimeError("Full review exceeds protected-file budget")
    check()
    save("sealed.json", qualification)
    save("candidate.json", plan)
    save("review.json", review)
    with (SESSION / "review.sha256").open("x") as stream:
        stream.write(hashlib.sha256(canonical).hexdigest() + "\n")
    (SESSION / "review.sha256").chmod(0o600)
    check(sealed=True)
    print("Signed and public certificate qualified; no install or SMC writes. Review SHA-256:", hashlib.sha256(canonical).hexdigest())


def admit_fresh_install():
    # Deleting an app does not prove its root runtime or launchd job is gone.
    # lstat also refuses broken aliases and propagates permission errors.
    for path in [INSTALLED, HARDWARE_ROOT, REPLACEMENT_STAGE, REPLACEMENT_BACKUP, LEGACY_BACKUP]:
        try:
            path.lstat()
        except FileNotFoundError:
            continue
        raise RuntimeError(f"Fresh install requires absent path: {path}; preserve state and stop")
    if launchd_job_present():
        raise RuntimeError("Fresh install requires an absent helper job; do not bootout or retry")


def install():
    owner_terminal()
    manifest = check(sealed=True)
    if manifest.get("installedContinuation"):
        raise RuntimeError("Installed continuation cannot install files")
    if manifest.get("installedReplacement") is not None:
        raise RuntimeError("Replacement package cannot perform a fresh install; prepare a new full review")
    admit_fresh_install()
    save("install-started.json", {"fingerprint": fingerprints(SESSION / "Ventilator.app"), "hardwareWritesExecuted": 0})
    admit_fresh_install()
    for command in [["sudo", "/usr/bin/ditto", str(SESSION / "Ventilator.app"), str(INSTALLED)],
                    ["sudo", "/usr/sbin/chown", "-R", "root:wheel", str(INSTALLED)],
                    ["sudo", "/bin/chmod", "-R", "go-w", str(INSTALLED)]]:
        subprocess.run(command, check=True)
    seal = installed_check()
    report = json.loads(output([files(INSTALLED)["applicationSHA256"], "--helper-status"]))
    if not all(report.get(k) is True for k in ["trustedBundle", "rootOwned", "installedLocation"]) or \
            report.get("fingerprint") != seal["fingerprint"] or report.get("hardwareControlAvailable") is not False:
        raise RuntimeError("Installed signed/root-owned bundle not verified; preserve files and stop")
    save("install-completed.json", {"fingerprint": seal["fingerprint"], "hardwareWritesExecuted": 0})
    print("Installed exact signed bundle at", INSTALLED, "; registration has not been requested.")


def admit_replacement(report, actual, previous, hardware_root_exists):
    if hardware_root_exists:
        raise RuntimeError("Hardware journal directory exists; replacement forbidden, retain state for diagnosis")
    if actual != previous or report.get("fingerprint") != previous:
        raise RuntimeError("Installed bundle differs from the pinned previous package")
    if not all(report.get(k) is True for k in ["trustedBundle", "rootOwned", "installedLocation"]):
        raise RuntimeError("Previous installed identity/ownership not verified")
    if report.get("registration") not in ["notFound", "notRegistered", "requiresApproval"] or report.get("error") != "serviceNotEnabled" or \
            report.get("helperVerified") is not False or report.get("hardwareControlAvailable") is not False:
        raise RuntimeError("Replacement requires a disabled, unstarted helper")


def admit_installed_continuation(expected):
    # This is a read-only preparation gate. An initialized root or any job forbids
    # creating a new registration session that might hide earlier runtime authority.
    try:
        HARDWARE_ROOT.lstat()
    except FileNotFoundError:
        pass
    else:
        raise RuntimeError("Runtime state exists; installed continuation forbidden")
    if launchd_job_present():
        raise RuntimeError("Helper job exists; installed continuation forbidden")
    actual = fingerprints(INSTALLED)
    if actual != expected:
        raise RuntimeError("Installed bundle differs from signed continuation source")
    report = json.loads(output([files(INSTALLED)["applicationSHA256"], "--helper-status"], timeout=10))
    admit_replacement(report, actual, expected, False)


def launchd_job_present():
    result = subprocess.run(["/bin/launchctl", "print", "system/dev.ventilator.helper"],
                            capture_output=True, text=True, timeout=5)
    if result.returncode == 113 and 'Could not find service "dev.ventilator.helper"' in result.stderr:
        return False
    if result.returncode != 0:
        raise RuntimeError("Could not establish launchd job state: " + result.stderr.strip())
    fields = [r"managed_by = com\.apple\.xpc\.ServiceManagement",
              r"parent bundle identifier = dev\.ventilator\.macos",
              r"program identifier = Contents/MacOS/VentilatorHelper \(mode: 2\)",
              r"state = (?:not running|spawn scheduled)"]
    if not result.stdout.startswith("system/dev.ventilator.helper = {") or \
            not all(re.search(r"(?m)^\s*" + field + r"\s*$", result.stdout) for field in fields) or \
            re.search(r"(?m)^\s*pid\s*=", result.stdout):
        raise RuntimeError("Launchd job is active or does not match the expected helper")
    return True


def replace_installed():
    owner_terminal()
    manifest = check(sealed=True)
    if manifest.get("installedContinuation"):
        raise RuntimeError("Installed continuation cannot replace files")
    previous = manifest.get("installedReplacement")
    if previous is None:
        raise RuntimeError("This package has no pinned previous installation")

    def verify_previous():
        # lstat fails closed on permission errors; any directory, file or symlink blocks replacement.
        try:
            HARDWARE_ROOT.lstat()
            hardware_exists = True
        except FileNotFoundError:
            hardware_exists = False
        report = json.loads(output([files(INSTALLED)["applicationSHA256"], "--helper-status"]))
        admit_replacement(report, fingerprints(INSTALLED), previous, hardware_exists)

    verify_previous()
    if os.path.lexists(REPLACEMENT_STAGE) or os.path.lexists(REPLACEMENT_BACKUP):
        raise RuntimeError("Replacement staging/backup already exists; preserve it and stop")
    save("replacement-started.json", {"previous": previous, "hardwareWritesExecuted": 0})
    # Owner first disables background permission. The state-root gate proves no initialized
    # runtime/approval/ledger exists; only a verified inactive job may be booted out once.
    if launchd_job_present():
        verify_previous()
        subprocess.run(["sudo", "/bin/launchctl", "bootout", "system/dev.ventilator.helper"], check=True)
    if launchd_job_present():
        raise RuntimeError("Launchd job remains; preserve state and stop")
    for command in [["sudo", "/usr/bin/ditto", str(SESSION / "Ventilator.app"), str(REPLACEMENT_STAGE)],
                    ["sudo", "/usr/sbin/chown", "-R", "root:wheel", str(REPLACEMENT_STAGE)],
                    ["sudo", "/bin/chmod", "-R", "go-w", str(REPLACEMENT_STAGE)]]:
        subprocess.run(command, check=True)
    staged = json.loads(output([files(REPLACEMENT_STAGE)["applicationSHA256"], "--helper-status"]))
    seal = json.loads((SESSION / "sealed.json").read_text())
    if staged.get("trustedBundle") is not True or staged.get("rootOwned") is not True or staged.get("fingerprint") != seal["fingerprint"]:
        raise RuntimeError("Staged signed/root-owned bundle not verified")
    verify_previous()
    if launchd_job_present():
        raise RuntimeError("Launchd job appeared during staging; do not move bundles")
    subprocess.run(["sudo", "/bin/mv", str(INSTALLED), str(REPLACEMENT_BACKUP)], check=True)
    subprocess.run(["sudo", "/bin/mv", str(REPLACEMENT_STAGE), str(INSTALLED)], check=True)
    installed_check()
    save("replacement-completed.json", {"previous": previous, "fingerprint": seal["fingerprint"], "hardwareWritesExecuted": 0})
    print("Replaced exact disabled unstarted bundle; old signed app preserved at", REPLACEMENT_BACKUP)


def service(command):
    owner_terminal(); installed_check()
    subprocess.run([str(files(INSTALLED)["applicationSHA256"]), command], check=True)


def register():
    owner_terminal()
    manifest = check(sealed=True)
    if not manifest.get("freshInstallation") and not manifest.get("installedContinuation"):
        service("--register-helper")
        return
    seal = installed_check()
    if os.path.lexists(SESSION / "registration-started.json"):
        raise RuntimeError("Registration was already attempted; preserve state and diagnose, no retry")

    def report(command):
        try:
            value = json.loads(output([files(INSTALLED)["applicationSHA256"], command], timeout=10))
        except RuntimeError as error:
            raise RuntimeError(f"Registration action {command} failed: {error}") from error
        if not all(value.get(k) is True for k in ["trustedBundle", "rootOwned", "installedLocation"]) or \
                value.get("fingerprint") != seal["fingerprint"] or value.get("hardwareControlAvailable") is not False:
            raise RuntimeError("Installed identity changed during registration; preserve state and stop")
        return value

    status = report("--helper-status")
    if status["registration"] == "enabled":
        print(json.dumps(status, indent=2))
        return status  # Existing effective consent needs verification, not a new mutation.
    if status["registration"] not in ["notFound", "notRegistered", "requiresApproval"] or \
            status.get("error") != "serviceNotEnabled" or status.get("helperVerified") is not False:
        raise RuntimeError("Fresh registration requires a disabled unstarted helper")
    def unstarted():
        try:
            HARDWARE_ROOT.lstat()
        except FileNotFoundError:
            pass
        else:
            raise RuntimeError("Runtime state exists; fresh registration repair forbidden")
        if launchd_job_present():
            raise RuntimeError("Helper job exists; fresh registration repair forbidden")

    unstarted()
    save("registration-started.json", {"fingerprint": seal["fingerprint"], "previousStatus": status["registration"], "hardwareWritesExecuted": 0})
    # A pending service is already registered. Preserve it for administrator consent;
    # unregister/register can leave BTM disabled even when the Settings toggle is on.
    if status["registration"] != "requiresApproval":
        status = report("--register-helper")
    if status["registration"] not in ["enabled", "requiresApproval"]:
        raise RuntimeError("Unexpected registration result; preserve state and stop")
    save("registration-completed.json", status)
    print(json.dumps(status, indent=2))
    if status["registration"] == "requiresApproval":
        print("Registration awaits system approval. Approve Ventilator's system notification with administrator authentication, then follow PLAN.md.")
    return status


def setup():
    owner_terminal()
    if not check(sealed=True).get("installedContinuation"):
        raise RuntimeError("Setup requires an installed continuation package")
    status = register()
    if status["registration"] != "enabled":
        print("Setup paused for system approval. Do not repeat setup/register; follow PLAN.md.")
        return
    ready()  # Root review import only, without approval or hardware start.


def ready():
    owner_terminal(); installed_check()
    status = json.loads(output([files(INSTALLED)["applicationSHA256"], "--verify-installed-helper"]))
    if not status["helperVerified"] or status["fingerprint"] != fingerprints(INSTALLED):
        raise RuntimeError("Installed root helper not verified")
    review_sha = (SESSION / "review.sha256").read_text().strip()
    subprocess.run(["sudo", str(files(INSTALLED)["helperSHA256"]), "--stage-local-hardware-review",
                    str(SESSION / "review.json"), review_sha], check=True)
    print("Ready for local review/approval. No receipt or hardware writes yet.")


def run():
    owner_terminal(); installed_check()
    # Root receipt and spent authority enforce the one-run budget; the client never retries start.
    subprocess.run([str(files(INSTALLED)["applicationSHA256"]), "--run-owner-experiment",
                    (SESSION / "review.sha256").read_text().strip()], check=True)


def collect():
    owner_terminal(); installed_check()
    report = {"seal": json.loads((SESSION / "sealed.json").read_text()), "physicalAutoVerified": False}
    for name, command in [
        ("snapshot", [files(INSTALLED)["helperSHA256"], "--experiment-read-only"]),
        ("status", [files(INSTALLED)["applicationSHA256"], "--owner-experiment-status"]),
        ("audit", ["sudo", files(INSTALLED)["helperSHA256"], "--owner-hardware-audit"])]:
        try:
            report[name] = json.loads(output(command, timeout=10))
        except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
            report[name] = {"error": str(error)}
    outcome = report.get("audit", {}).get("outcome", {})
    report["independentObservations"] = [{"stage": x["stage"], "sample": json.loads(x["sampleJSON"])} for x in outcome.get("observations", [])]
    save("result.json", report)
    print(f"Saved {SESSION / 'result.json'}. Pending retained; no qualification or retry authorized.")


def main():
    global SESSION, PREVIOUS_SESSION, SIGNED_SESSION, FRESH_INSTALL, CONTINUE_INSTALLED
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "check", "sign", "qualify", "install", "replace-installed", "register", "setup", "ready", "run", "collect", "unregister"])
    parser.add_argument("--output", type=Path, help="Repository-only prepare/check output under .build")
    parser.add_argument("--previous-session", type=Path, help="Prepare a pinned replacement from a preserved signed package under .build")
    parser.add_argument("--signed-session", type=Path, help="Prepare from a preserved failed signing package under .build without signing again")
    parser.add_argument("--fresh-install", action="store_true", help="Prepare a new full review from signed source without inheriting its previous-installation pin")
    parser.add_argument("--continue-installed", action="store_true", help="Prepare a new full review for the exact already-installed unstarted signed copy, without installing files")
    args = parser.parse_args()
    if args.fresh_install and (args.command != "prepare" or not args.signed_session or args.previous_session):
        raise RuntimeError("Fresh install allowed only for prepare with signed source and no previous installation")
    if args.continue_installed and (args.command != "prepare" or not args.signed_session or args.previous_session or args.fresh_install):
        raise RuntimeError("Installed continuation allowed only for prepare with signed source and no fresh/replacement mode")
    FRESH_INSTALL = args.fresh_install
    CONTINUE_INSTALLED = args.continue_installed
    if args.output:
        if ROOT is None or args.command not in ["prepare", "check"] or not args.output.resolve().is_relative_to(ROOT / ".build"):
            raise RuntimeError("Custom output allowed only for offline prepare/check under .build")
        SESSION = args.output.resolve()
    if args.previous_session:
        if ROOT is None or args.command != "prepare" or not args.previous_session.resolve().is_relative_to(ROOT / ".build"):
            raise RuntimeError("Previous session allowed only for repository prepare under .build")
        PREVIOUS_SESSION = args.previous_session.resolve()
    if args.signed_session:
        if ROOT is None or args.command != "prepare" or not args.signed_session.resolve().is_relative_to(ROOT / ".build"):
            raise RuntimeError("Signed session allowed only for repository prepare under .build")
        SIGNED_SESSION = args.signed_session.resolve()
    if os.geteuid() == 0:
        raise RuntimeError("Run without root; only listed child commands may use owner sudo")
    actions = {"prepare": prepare, "check": lambda: print(json.dumps(package_status(), indent=2)),
        "sign": sign, "qualify": qualify, "install": install, "replace-installed": replace_installed, "register": register, "setup": setup, "ready": ready,
        "run": run, "collect": collect, "unregister": lambda: service("--unregister-helper")}
    actions[args.command]()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, AssertionError, subprocess.SubprocessError) as error:
        print(f"STOP: {error}. No automatic retry; follow PLAN.md.", file=sys.stderr)
        sys.exit(78)
