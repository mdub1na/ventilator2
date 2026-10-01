import Foundation
import Security
import XCTest
import VentilatorControl
@testable import VentilatorInstallation

final class InstallationTests: XCTestCase {
    private let nonce = UUID()
    private func proof(path: String = SignedBundleInspector.installedPath, rootOwned: Bool = true,
                       team: String = "ABCDEFGHIJ", cdhash: String = String(repeating: "a", count: 40)) -> SignedBundleProof {
        .init(bundleURL: URL(fileURLWithPath: path), teamIdentifier: team, applicationCDHash: cdhash,
              helperCDHash: String(repeating: "b", count: 40), fingerprint: .init(applicationSHA256: "app", helperSHA256: "helper", launchDaemonSHA256: "plist"), rootOwned: rootOwned)
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
    private var info: [String: Any] { ["CFBundleIdentifier": "dev.ventilator.macos", "CFBundleExecutable": "Ventilator", "CFBundlePackageType": "APPL"] }

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

    func testUnsignedBundleAndSymlinkAreRejectedBeforeServiceAccess() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = parent.appendingPathComponent("Ventilator.app")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Library/LaunchDaemons"), withIntermediateDirectories: true)
        try plist(info).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try plist(launch).write(to: bundle.appendingPathComponent("Contents/Library/LaunchDaemons/dev.ventilator.helper.plist"))
        for name in ["Ventilator", "VentilatorHelper"] { try Data("unsigned".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/\(name)")) }
        XCTAssertThrowsError(try SignedBundleInspector.inspect(bundle))
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
}
