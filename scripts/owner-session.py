#!/usr/bin/env python3
"""Prepare locally; explicit owner commands sign/install/register/run. No SMC payload interface."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

CERTIFICATE = "4895C06FF7407EAF5F350E78CF23D0B41AD466C9"
TEAM = "568959LQ99"
INSTALLED = Path("/Applications/Ventilator.app")
ROOT = Path(__file__).resolve().parents[1] if Path(__file__).parent.name == "scripts" else None
SESSION = ROOT / ".build/owner-session" if ROOT else Path(__file__).resolve().parent


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
    return subprocess.run([str(x) for x in command], check=True, capture_output=True,
                          text=True, timeout=timeout).stdout


def candidate(bundle):
    result = json.loads(output([files(bundle)["helperSHA256"], "--candidate-plan"]))
    hashes = fingerprints(bundle)
    assert result["hardwareWritesExecuted"] == 0
    assert not result["plan"]["readyForOwnerApproval"]
    assert result["plan"]["binaries"] == {k: hashes[k] for k in ("applicationSHA256", "helperSHA256")}
    canonical = json.dumps(result["plan"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    assert hashlib.sha256(canonical).hexdigest() == result["planSHA256"]
    return result


def check(sealed=False):
    manifest = json.loads((SESSION / "manifest.json").read_text())
    for name, digest in manifest["packageFiles"].items():
        if sha(SESSION / name) != digest:
            raise RuntimeError(f"Package changed: {name}")
    reference = json.loads((SESSION / "sealed.json").read_text())["fingerprint"] if sealed else manifest["fingerprint"]
    if fingerprints(SESSION / "Ventilator.app") != reference:
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
    if SESSION.exists():
        raise RuntimeError("Package already exists; preserve it, use a new output for a revised package")
    instructions = (ROOT / "docs/owner-session.md").read_text()
    if len(instructions.encode()) > 12288:
        raise RuntimeError("Owner instructions exceed review budget")
    plan = candidate(ROOT / ".build/Ventilator.app")
    SESSION.mkdir(mode=0o700, parents=True)
    shutil.copytree(ROOT / ".build/Ventilator.app", SESSION / "Ventilator.app", symlinks=False)
    shutil.copyfile(__file__, SESSION / "session.py")
    (SESSION / "PLAN.md").write_text(instructions)
    save("manifest.json", {"schema": 1, "certificateSHA1": CERTIFICATE, "teamIdentifier": TEAM,
        "fingerprint": fingerprints(SESSION / "Ventilator.app"), "candidatePlanSHA256": plan["planSHA256"],
        "packageFiles": {n: sha(SESSION / n) for n in ["session.py", "PLAN.md"]},
        "hardwareWritesExecuted": 0, "signed": False})
    print(f"Prepared {SESSION}. No signing, install, sudo or hardware writes.")


def sign():
    owner_terminal(); check()
    # A failed signing/qualification is preserved for diagnosis, never retried by this command.
    save("sign-started.json", {"certificateSHA1": CERTIFICATE, "hardwareWritesExecuted": 0})
    bundle = SESSION / "Ventilator.app"
    for path, identifier in [(files(bundle)["helperSHA256"], "dev.ventilator.helper"), (bundle, "dev.ventilator.macos")]:
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", CERTIFICATE, "--options", "runtime",
                        "--identifier", identifier, "--timestamp=none", str(path)], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(path)], check=True)
    qualification = json.loads(output([files(bundle)["applicationSHA256"], "--qualify-owner-signature", bundle, CERTIFICATE], timeout=20))
    if qualification["teamIdentifier"] != TEAM or not qualification["positiveRevocation"] or qualification["notarizationClaimed"]:
        raise RuntimeError("Certificate qualification failed")
    if qualification["fingerprint"] != fingerprints(bundle):
        raise RuntimeError("Qualification fingerprint mismatch")
    plan = candidate(bundle)
    review = {"domain": "hardware", "candidate": plan["plan"], "ownerInstructions": (SESSION / "PLAN.md").read_text()}
    canonical = json.dumps(review, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if len(canonical) > 16384:
        raise RuntimeError("Full review exceeds protected-file budget")
    save("sealed.json", qualification)
    save("candidate.json", plan)
    save("review.json", review)
    (SESSION / "review.sha256").write_text(hashlib.sha256(canonical).hexdigest() + "\n")
    (SESSION / "review.sha256").chmod(0o600)
    check(sealed=True)
    print("Signed and public certificate qualified; no install or SMC writes. Review SHA-256:", hashlib.sha256(canonical).hexdigest())


def install():
    owner_terminal(); check(sealed=True)
    if os.path.lexists(INSTALLED):
        raise RuntimeError("Installed path exists; stop without replacing it")
    for command in [["sudo", "/usr/bin/ditto", str(SESSION / "Ventilator.app"), str(INSTALLED)],
                    ["sudo", "/usr/sbin/chown", "-R", "root:wheel", str(INSTALLED)],
                    ["sudo", "/bin/chmod", "-R", "go-w", str(INSTALLED)]]:
        subprocess.run(command, check=True)
    installed_check()
    print("Copied exact signed bundle; registration has not been requested.")


def service(command):
    owner_terminal(); installed_check()
    subprocess.run([str(files(INSTALLED)["applicationSHA256"]), command], check=True)


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
        except (subprocess.SubprocessError, ValueError) as error:
            report[name] = {"error": str(error)}
    outcome = report.get("audit", {}).get("outcome", {})
    report["independentObservations"] = [{"stage": x["stage"], "sample": json.loads(x["sampleJSON"])} for x in outcome.get("observations", [])]
    save("result.json", report)
    print(f"Saved {SESSION / 'result.json'}. Pending retained; no qualification or retry authorized.")


def main():
    global SESSION
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "check", "sign", "install", "register", "ready", "run", "collect", "unregister"])
    parser.add_argument("--output", type=Path, help="Repository-only prepare/check output under .build")
    args = parser.parse_args()
    if args.output:
        if ROOT is None or args.command not in ["prepare", "check"] or not args.output.resolve().is_relative_to(ROOT / ".build"):
            raise RuntimeError("Custom output allowed only for offline prepare/check under .build")
        SESSION = args.output.resolve()
    if os.geteuid() == 0:
        raise RuntimeError("Run without root; only listed child commands may use owner sudo")
    actions = {"prepare": prepare, "check": lambda: print(json.dumps(check(sealed=(SESSION / "sealed.json").exists()), indent=2)),
        "sign": sign, "install": install, "register": lambda: service("--register-helper"), "ready": ready,
        "run": run, "collect": collect, "unregister": lambda: service("--unregister-helper")}
    actions[args.command]()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, AssertionError, subprocess.SubprocessError) as error:
        print(f"STOP: {error}. No automatic retry; follow PLAN.md.", file=sys.stderr)
        sys.exit(78)
