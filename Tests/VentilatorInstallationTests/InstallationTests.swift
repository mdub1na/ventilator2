import Foundation
import Security
import ServiceManagement
import XCTest
import VentilatorControl
@testable import VentilatorInstallation

final class InstallationTests: XCTestCase {
    func testRegistrationErrorNeedsActualPendingApprovalState() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("SMAppService error domain is available on macOS 15+") }
        let error = NSError(domain: SMAppServiceErrorDomain, code: 1)
        XCTAssertTrue(HelperServiceController.registrationAwaitsApproval(error, status: .requiresApproval))
        for status: SMAppService.Status in [.enabled, .notRegistered, .notFound] {
            XCTAssertFalse(HelperServiceController.registrationAwaitsApproval(error, status: status))
        }
        XCTAssertFalse(HelperServiceController.registrationAwaitsApproval(NSError(domain: "other", code: 1), status: .requiresApproval))
        XCTAssertFalse(HelperServiceController.registrationAwaitsApproval(NSError(domain: SMAppServiceErrorDomain, code: 2), status: .requiresApproval))
    }

    func testLoadedExecutablePathMatchesSecurityCodeIdentity() throws {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        let current = try XCTUnwrap(code)
        XCTAssertEqual(SecCodeCopyStaticCode(current, [], &staticCode), errSecSuccess)
        XCTAssertEqual(SecCodeCopySigningInformation(try XCTUnwrap(staticCode), SecCSFlags(rawValue: kSecCSSigningInformation), &info), errSecSuccess)
        let securityPath = try XCTUnwrap((info as? [String: Any])?[kSecCodeInfoMainExecutable as String] as? URL)
        // Xcode launches xctest through a symlink; Security returns its resolved code path.
        XCTAssertEqual(try CurrentExecutable.url().resolvingSymlinksInPath(), securityPath.resolvingSymlinksInPath())
    }

    private let nonce = UUID()
    private func proof(path: String = SignedBundleInspector.installedPath, rootOwned: Bool = true,
                       team: String = "ABCDEFGHIJ", cdhash: String = String(repeating: "a", count: 40)) -> SignedBundleProof {
        .init(bundleURL: URL(fileURLWithPath: path), teamIdentifier: team, applicationCDHash: cdhash,
              helperCDHash: String(repeating: "b", count: 40), fingerprint: .init(applicationSHA256: "app", helperSHA256: "helper", launchDaemonSHA256: "plist"), rootOwned: rootOwned)
    }

    func testStatusRejectsUnadmittedBundleBeforeServiceOrPeerAccess() {
        for (path, owned, expected): (String, Bool, InstallationError) in [
            ("/Applications/Ventilator-profile-staging.app", true, .installedLocationRequired),
            ("/tmp/Ventilator.app", true, .installedLocationRequired),
            (SignedBundleInspector.installedPath, false, .rootOwnershipRequired)
        ] {
            var calls: [String] = []
            let report = HelperServiceController.status(effectiveUID: 501, inspect: {
                calls.append("inspect"); return self.proof(path: path, rootOwned: owned)
            }, validateProcess: { calls.append("process") }, registration: {
                calls.append("service"); return .enabled
            }, verify: { _ in calls.append("peer") })
            XCTAssertEqual(calls, ["inspect"])
            XCTAssertEqual(report.registration, "notQueried")
            XCTAssertEqual(report.error, String(describing: expected))
            XCTAssertEqual(report.fingerprint, proof().fingerprint)
            XCTAssertTrue(report.trustedBundle)
            XCTAssertFalse(report.helperVerified)
            XCTAssertFalse(report.hardwareControlAvailable)
        }
    }

    func testStatusRejectsRootSignatureOrProcessFailureBeforeServiceAccess() {
        for mode in ["root", "signature", "process"] {
            var calls: [String] = []
            let report = HelperServiceController.status(effectiveUID: mode == "root" ? 0 : 501, inspect: {
                calls.append("inspect")
                if mode == "signature" { throw InstallationError.appleSignatureRequired }
                return self.proof()
            }, validateProcess: {
                calls.append("process"); throw InstallationError.runtimeIdentityRejected
            }, registration: { calls.append("service"); return .enabled }, verify: { _ in calls.append("peer") })
            XCTAssertEqual(calls, mode == "root" ? [] : mode == "signature" ? ["inspect"] : ["inspect", "process"])
            XCTAssertEqual(report.registration, "notQueried")
            let expected: InstallationError = mode == "root" ? .nonRootApplicationRequired : mode == "signature" ? .appleSignatureRequired : .runtimeIdentityRejected
            XCTAssertEqual(report.error, String(describing: expected))
            XCTAssertFalse(report.helperVerified)
        }
    }

    func testStatusQueriesOnlyAdmittedProcessAndVerifiesOnlyEnabledPeer() {
        for state: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            var calls: [String] = []
            let report = HelperServiceController.status(effectiveUID: 501, inspect: {
                calls.append("inspect"); return self.proof()
            }, validateProcess: { calls.append("process") }, registration: {
                calls.append("service"); return state
            }, verify: { inspected in
                calls.append("peer"); XCTAssertEqual(inspected.fingerprint, self.proof().fingerprint)
            })
            XCTAssertEqual(calls, ["inspect", "process", "service"] + (state == .enabled ? ["peer"] : []))
            XCTAssertEqual(report.helperVerified, state == .enabled)
            XCTAssertEqual(report.error, state == .enabled ? nil : "serviceNotEnabled")
            XCTAssertNotEqual(report.registration, "notQueried")
            XCTAssertFalse(report.hardwareControlAvailable)
        }
        let failedPeer = HelperServiceController.status(effectiveUID: 501, inspect: { self.proof() },
            validateProcess: {}, registration: { .enabled }, verify: { _ in throw InstallationError.peerIdentity })
        XCTAssertEqual(failedPeer.registration, "enabled")
        XCTAssertEqual(failedPeer.error, "peerIdentity")
        XCTAssertFalse(failedPeer.helperVerified)
    }

    func testStaticInspectionReportsFilesWithoutInstalledAdmission() {
        let inspected = proof(path: "/Applications/Ventilator-profile-staging.app", rootOwned: false)
        let report = HelperServiceController.inspectBundle(effectiveUID: 501, inspect: { inspected })
        XCTAssertTrue(report.trustedBundle)
        XCTAssertEqual(report.fingerprint, inspected.fingerprint)
        XCTAssertEqual(report.registration, "notQueried")
        XCTAssertFalse(report.installedLocation)
        XCTAssertFalse(report.rootOwned)
        XCTAssertFalse(report.helperVerified)
        XCTAssertFalse(report.hardwareControlAvailable)
        XCTAssertNil(report.error)
        let root = HelperServiceController.inspectBundle(effectiveUID: 0, inspect: {
            XCTFail("Root must not inspect files"); return inspected
        })
        XCTAssertEqual(root.error, "nonRootApplicationRequired")
        let invalid = HelperServiceController.inspectBundle(effectiveUID: 501, inspect: { throw InstallationError.invalidLayout })
        XCTAssertFalse(invalid.trustedBundle)
        XCTAssertEqual(invalid.registration, "notQueried")
        XCTAssertEqual(invalid.error, "invalidLayout")
    }

    private func reply(nonce: UUID? = nil, pending: Bool = false, phase: String = "idle") -> HelperInstallationReply {
        let proof = proof()
        return .init(nonce: nonce ?? self.nonce, processIdentifier: 42, effectiveUID: 0, teamIdentifier: proof.teamIdentifier,
            applicationCDHash: proof.applicationCDHash, helperCDHash: proof.helperCDHash,
            applicationSHA256: proof.fingerprint.applicationSHA256, helperSHA256: proof.fingerprint.helperSHA256,
            launchDaemonSHA256: proof.fingerprint.launchDaemonSHA256, pendingHardwareRestoration: pending, simulationPhase: phase)
    }
    private func validate(_ reply: HelperInstallationReply, peerPID: Int32 = 42, peerUID: UInt32 = 0, now: Double = 11) throws {
        try InstalledHelperClient.validate(reply, proof: proof(), nonce: nonce, peerPID: peerPID, peerUID: peerUID, started: 10, now: now)
    }
    private func plist(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }
    private var launch: [String: Any] { ["Label": SignedBundleInspector.machService, "BundleProgram": "Contents/MacOS/VentilatorHelper", "MachServices": [SignedBundleInspector.machService: true]] }
    private var info: [String: Any] { ["CFBundleIdentifier": "dev.ventilator.app", "CFBundleExecutable": "Ventilator", "CFBundlePackageType": "APPL"] }

    func testLaunchLayoutRejectsAnotherExecutableExtraArgumentsOrMachService() throws {
        try SignedBundleInspector.validateLayout(launchData: plist(launch), infoData: plist(info))
        for (key, value): (String, Any) in [("Program", "/bin/sh"), ("ProgramArguments", ["/bin/sh"]),
                                           ("BundleProgram", "/tmp/helper"), ("Label", "other"),
                                           ("MachServices", ["other": true]), ("MachServices", [SignedBundleInspector.machService: 1])] {
            var changed = launch; changed[key] = value
            XCTAssertThrowsError(try SignedBundleInspector.validateLayout(launchData: plist(changed), infoData: plist(info)))
        }
        var otherApp = info; otherApp["CFBundleExecutable"] = "Other"
        XCTAssertThrowsError(try SignedBundleInspector.validateLayout(launchData: plist(launch), infoData: plist(otherApp)))
    }

    func testRetiredApplicationOrHelperIdentityIsRejected() throws {
        var oldInfo = info
        oldInfo["CFBundleIdentifier"] = "dev.ventilator.macos"
        XCTAssertThrowsError(try SignedBundleInspector.validateLayout(launchData: plist(launch), infoData: plist(oldInfo))) {
            XCTAssertEqual($0 as? InstallationError, .invalidLayout)
        }
        var oldLaunch = launch
        oldLaunch["Label"] = "dev.ventilator.helper"
        oldLaunch["MachServices"] = ["dev.ventilator.helper": true]
        for appInfo in [info, oldInfo] {
            XCTAssertThrowsError(try SignedBundleInspector.validateLayout(launchData: plist(oldLaunch), infoData: plist(appInfo))) {
                XCTAssertEqual($0 as? InstallationError, .invalidLayout)
            }
        }
        for (role, identifier) in [(SignedBundleInspector.Role.application, "dev.ventilator.app"), (.helper, "dev.ventilator.app.helper")] {
            let requirement = try SignedBundleInspector.requirement(role: role, proof: proof())
            XCTAssertTrue(requirement.contains("identifier \"\(identifier)\""))
            XCTAssertTrue(requirement.contains("anchor apple generic"))
            XCTAssertTrue(requirement.contains("cdhash H\""))
        }
    }

    func testPinnedRequirementsCompileAndRejectInjection() throws {
        for role in [SignedBundleInspector.Role.application, .helper] {
            let text = try SignedBundleInspector.requirement(role: role, proof: proof())
            var requirement: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
            XCTAssertNotNil(requirement)
            XCTAssertTrue(text.contains("cdhash H\""))
        }
        XCTAssertThrowsError(try SignedBundleInspector.requirement(role: .application, proof: proof(team: "bad\" or true")))
        XCTAssertThrowsError(try SignedBundleInspector.requirement(role: .application, proof: proof(cdhash: String(repeating: "z", count: 40))))
    }

    func testStagingLocationOrWritableOwnershipCannotRegister() throws {
        XCTAssertThrowsError(try SignedBundleInspector.requireInstalled(proof(path: "/tmp/Ventilator.app")))
        XCTAssertThrowsError(try SignedBundleInspector.requireInstalled(proof(rootOwned: false)))
        try SignedBundleInspector.requireInstalled(proof()) // Policy fixture only, no native signature/service invoked.
    }

    func testPeerAuditUIDAndPIDOverrideReplyClaims() throws {
        try validate(reply())
        XCTAssertThrowsError(try validate(reply(), peerUID: 501))
        XCTAssertThrowsError(try validate(reply(), peerPID: 43))
        XCTAssertThrowsError(try validate(reply(), peerPID: 0))
    }

    func testWrongNonceFingerprintVersionOrHardwareClaimCannotVerify() throws {
        XCTAssertThrowsError(try validate(reply(nonce: UUID())))
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply())) as! [String: Any]
        for (key, value): (String, Any) in [("teamIdentifier", "OTHERTEAM0"), ("applicationCDHash", "wrong"),
                                           ("helperCDHash", "wrong"), ("applicationSHA256", "wrong"),
                                           ("helperSHA256", "wrong"), ("launchDaemonSHA256", "wrong"),
                                           ("protocolVersion", 2), ("hardwareControlAvailable", true), ("simulationPhase", "unknown")] {
            var changed = original; changed[key] = value
            let altered = try JSONDecoder().decode(HelperInstallationReply.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertThrowsError(try validate(altered), key)
        }
    }

    func testLateOrBrokenClockNeverVerifiesDaemon() throws {
        for now in [Double.nan, .infinity, 9, 12] { XCTAssertThrowsError(try validate(reply(), now: now)) }
    }

    func testHardenedRuntimeCannotOptIntoDebuggingOrInjectedCode() throws {
        let runtime = SecCodeSignatureFlags.runtime.rawValue
        try SignedBundleInspector.validateRuntimePolicy(flags: runtime, entitlements: [:])
        XCTAssertThrowsError(try SignedBundleInspector.validateRuntimePolicy(flags: 0, entitlements: [:]))
        for key in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                    "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory",
                    "com.apple.security.cs.allow-jit"] {
            XCTAssertThrowsError(try SignedBundleInspector.validateRuntimePolicy(flags: runtime, entitlements: [key: true]))
            XCTAssertThrowsError(try SignedBundleInspector.validateRuntimePolicy(flags: runtime, entitlements: [key: "false"]))
        }
    }

    func testPendingRecoveryOrActiveSimulationBlocksRemoval() throws {
        try HelperServiceController.admitRemoval(reply())
        try HelperServiceController.admitRemoval(reply(phase: "autoCodeObserved"))
        XCTAssertThrowsError(try HelperServiceController.admitRemoval(reply(pending: true)))
        for phase in ["waitingForFixed", "fixedObserved", "restoring", "recoveryRequired", "unknown"] {
            XCTAssertThrowsError(try HelperServiceController.admitRemoval(reply(phase: phase)))
        }
    }

    func testUnapprovedUnstartedRemovalRequiresAbsentRuntimeRoot() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = parent.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try HelperServiceController.admitUnstartedRemoval(status: .requiresApproval, stateURL: state)
        for status: SMAppService.Status in [.enabled, .notFound, .notRegistered] {
            XCTAssertThrowsError(try HelperServiceController.admitUnstartedRemoval(status: status, stateURL: state))
        }
        try Data().write(to: state)
        XCTAssertThrowsError(try HelperServiceController.admitUnstartedRemoval(status: .requiresApproval, stateURL: state))
        try FileManager.default.removeItem(at: state)
        try FileManager.default.createSymbolicLink(at: state, withDestinationURL: parent.appendingPathComponent("missing"))
        XCTAssertThrowsError(try HelperServiceController.admitUnstartedRemoval(status: .requiresApproval, stateURL: state))
    }

    func testUnsignedBundleAndSymlinkAreRejectedBeforeServiceAccess() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = parent.appendingPathComponent("Ventilator.app")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Library/LaunchDaemons"), withIntermediateDirectories: true)
        try plist(info).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try plist(launch).write(to: bundle.appendingPathComponent("Contents/Library/LaunchDaemons/dev.ventilator.app.helper.plist"))
        for name in ["Ventilator", "VentilatorHelper"] { try Data("unsigned".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/\(name)")) }
        XCTAssertThrowsError(try SignedBundleInspector.inspect(bundle))
        let obsolete = bundle.appendingPathComponent("Contents/Library/LaunchDaemons/dev.ventilator.helper.plist")
        try Data("obsolete daemon".utf8).write(to: obsolete)
        XCTAssertThrowsError(try SignedBundleInspector.inspect(bundle)) { XCTAssertEqual($0 as? InstallationError, .invalidLayout) }
        try FileManager.default.removeItem(at: obsolete)
        let helper = bundle.appendingPathComponent("Contents/MacOS/VentilatorHelper")
        try FileManager.default.removeItem(at: helper)
        try FileManager.default.createSymbolicLink(at: helper, withDestinationURL: bundle.appendingPathComponent("Contents/MacOS/Ventilator"))
        XCTAssertThrowsError(try SignedBundleInspector.inspect(bundle)) { XCTAssertEqual($0 as? InstallationError, .invalidLayout) }
    }

    func testOwnerClientRejectsModelReplyUnknownPhaseOrPhysicalQualification() throws {
        let good = HelperReply(control: .init(phase: .idle), hardwareExperiment: .init(domain: "hardware", sessionID: UUID(),
            phase: "fixed", pending: true, fixedRPMObserved: false))
        try InstalledHelperSession.validate(good)
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as! [String: Any]
        for (key, value): (String, Any) in [("domain", "simulation"), ("phase", "unlimited"), ("physicalAutoVerified", true)] {
            var altered = original
            var report = altered["hardwareExperiment"] as! [String: Any]; report[key] = value; altered["hardwareExperiment"] = report
            let reply = try JSONDecoder().decode(HelperReply.self, from: JSONSerialization.data(withJSONObject: altered))
            XCTAssertThrowsError(try InstalledHelperSession.validate(reply), key)
        }
    }

    func testValidationFlagsAreAcceptedByNativeAPIAndRejectWrongRequirement() throws {
        // This uses the real signed XCTest bundle, not a hand-crafted flag equality assertion.
        let bundle = Bundle(for: InstallationTests.self).bundleURL
        var code: SecStaticCode?, good: SecRequirement?, wrong: SecRequirement?
        XCTAssertEqual(SecStaticCodeCreateWithPath(bundle as CFURL, [], &code), errSecSuccess)
        let executable = try XCTUnwrap(code)
        XCTAssertEqual(SecRequirementCreateWithString("true" as CFString, [], &good), errSecSuccess)
        XCTAssertEqual(SecRequirementCreateWithString("identifier \"dev.ventilator.not-this-test\"" as CFString, [], &wrong), errSecSuccess)
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | SignedBundleInspector.offlineFlags.rawValue)
        XCTAssertEqual(SecStaticCodeCheckValidity(executable, flags, good), errSecSuccess)
        XCTAssertNotEqual(SecStaticCodeCheckValidity(executable, flags, wrong), errSecSuccess)
        var running: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &running), errSecSuccess)
        XCTAssertEqual(SecCodeCheckValidity(try XCTUnwrap(running), SignedBundleInspector.offlineFlags, good), errSecSuccess)
    }

    func testFirstRegistrationDoesNotRequireExistingServiceRecord() throws {
        for status in [SMAppService.Status.notFound, .notRegistered, .enabled, .requiresApproval] {
            var calls = 0
            try HelperServiceController.registerIfNeeded(status: status) { calls += 1 }
            XCTAssertEqual(calls, status == .notFound || status == .notRegistered ? 1 : 0)
        }
    }

    func testFirstRegistrationPreservesFrameworkErrorWithoutRetry() {
        let failure = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        var calls = 0
        XCTAssertThrowsError(try HelperServiceController.registerIfNeeded(status: .notFound) {
            calls += 1
            throw failure
        }) { XCTAssertEqual($0 as NSError, failure) }
        XCTAssertEqual(calls, 1)
    }
}
