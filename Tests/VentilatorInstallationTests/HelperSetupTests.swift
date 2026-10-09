import Darwin
import Foundation
import ServiceManagement
import XCTest
@testable import VentilatorInstallation

final class HelperSetupTests: XCTestCase {
    private func fingerprint(_ char: String = "a") -> InstallationFingerprint {
        .init(applicationSHA256: String(repeating: char, count: 64), helperSHA256: String(repeating: "b", count: 64), launchDaemonSHA256: String(repeating: "c", count: 64))
    }
    private func proof(owned: Bool = true, path: String = SignedBundleInspector.installedPath) -> SignedBundleProof {
        .init(bundleURL: URL(fileURLWithPath: path), teamIdentifier: "ABCDEFGHIJ", applicationCDHash: String(repeating: "a", count: 40),
              helperCDHash: String(repeating: "b", count: 40), fingerprint: fingerprint(), rootOwned: owned)
    }
    private func report(_ registration: String, verified: Bool = false, error: String? = nil) -> HelperServiceReport {
        var result = HelperServiceReport(registration: registration)
        result.fingerprint = fingerprint(); result.trustedBundle = true; result.rootOwned = true; result.installedLocation = true
        result.helperVerified = verified; result.error = error
        return result
    }

    func testGUIGatesRejectChangedOrUninstalledBundleBeforeFrameworkAndClaim() throws {
        for p in [proof(owned: false), proof(path: "/tmp/Ventilator.app")] {
            XCTAssertThrowsError(try HelperServiceController.registerFromGUI(expected: fingerprint(), inspectProcess: { p },
                state: { XCTFail("Unadmitted service query"); return .notFound }, claim: { _ in XCTFail("Unadmitted marker") }, register: { XCTFail("Unadmitted registration") }))
        }
        XCTAssertThrowsError(try HelperServiceController.registerFromGUI(expected: fingerprint("d"), inspectProcess: { self.proof() },
            state: { XCTFail("Changed fingerprint reached framework"); return .notFound }, claim: { _ in XCTFail("Changed claim") }, register: { XCTFail("Changed register") }))
        XCTAssertThrowsError(try HelperServiceController.registerFromGUI(expected: fingerprint(), inspectProcess: { throw InstallationError.runtimeIdentityRejected },
            state: { XCTFail("Rejected process queried framework"); return .notFound }, claim: { _ in XCTFail("Rejected process claimed") }, register: { XCTFail("Rejected process registered") }))
    }

    func testGUILeavesEnabledAndPendingRegistrationAloneWithoutClaimOrPeer() throws {
        for state: SMAppService.Status in [.enabled, .requiresApproval] {
            let result = try HelperServiceController.registerFromGUI(expected: fingerprint(), inspectProcess: { self.proof() }, state: { state },
                claim: { _ in XCTFail("Existing registration consumed marker") }, register: { XCTFail("Existing registration repeated") })
            XCTAssertFalse(result.helperVerified); XCTAssertFalse(result.hardwareControlAvailable)
            XCTAssertEqual(HelperSetupPhase(report: result), state == .enabled ? .registered : .requiresApproval)
        }
    }

    func testClaimPrecedesSoleRegisterAndFailedClaimPreventsIt() throws {
        for before: SMAppService.Status in [.notFound, .notRegistered] {
            var calls: [String] = [], state = before
            let result = try HelperServiceController.registerFromGUI(expected: fingerprint(), inspectProcess: { self.proof() },
                state: { calls.append("state"); return state }, claim: { _ in calls.append("durableClaim") },
                register: { calls.append("register"); state = .requiresApproval })
            XCTAssertEqual(calls, ["state", "durableClaim", "register", "state"])
            XCTAssertEqual(result.registration, "requiresApproval"); XCTAssertFalse(result.helperVerified)
        }
        XCTAssertThrowsError(try HelperServiceController.registerFromGUI(expected: fingerprint(), inspectProcess: { self.proof() }, state: { .notRegistered },
            claim: { _ in throw InstallationError.registrationAlreadyAttempted }, register: { XCTFail("Repeated marker reached register") }))
    }

    func testGUIErrorOneRequiresActualPostStateAndNeverClaimsRootReady() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Error domain needs macOS 15+") }
        for after: SMAppService.Status in [.requiresApproval, .enabled, .notRegistered] {
            var state: SMAppService.Status = .notRegistered
            let result = try HelperServiceController.registerFromGUI(expected: fingerprint(), inspectProcess: { self.proof() }, state: { state }, claim: { _ in },
                register: { state = after; throw NSError(domain: SMAppServiceErrorDomain, code: 1) })
            XCTAssertEqual(result.registrationDiagnostic != nil, after == .requiresApproval)
            XCTAssertEqual(result.error != nil, after != .requiresApproval)
            XCTAssertFalse(result.helperVerified); XCTAssertFalse(result.hardwareControlAvailable)
        }
    }

    func testDisplayedReadinessRequiresInstalledTrustEnabledAndBoundPeer() {
        XCTAssertEqual(HelperSetupPhase(report: report("enabled")), .registered)
        XCTAssertEqual(HelperSetupPhase(report: report("enabled", error: "deadline")), .connectionFailed)
        XCTAssertEqual(HelperSetupPhase(report: report("enabled", verified: true)), .verified)
        XCTAssertEqual(HelperSetupPhase(report: report("requiresApproval", verified: true)), .requiresApproval)
        XCTAssertEqual(HelperSetupPhase(report: report("notRegistered", error: "registrationAlreadyAttempted")), .stopped)
        for field in 0..<4 {
            var untrusted = report("enabled", verified: true)
            if field == 0 { untrusted.trustedBundle = false }
            if field == 1 { untrusted.rootOwned = false }
            if field == 2 { untrusted.installedLocation = false }
            if field == 3 { untrusted.fingerprint = nil }
            XCTAssertEqual(HelperSetupPhase(report: untrusted), .unavailable)
        }
    }

    func testSavedHardwareFailureSurvivesStatusAndDisplaysUnconfirmedRecovery() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("docs/research/evidence/current-hardware-failed-result.json"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(saved["result"] as? [String: Any])
        let audit = try XCTUnwrap(result["audit"] as? [String: Any])
        let authority = try XCTUnwrap(audit["authority"] as? [String: Any])
        let ledger = try XCTUnwrap(authority["ledger"] as? [String: Any])
        let pending = try XCTUnwrap(ledger["pendingRestoration"] as? Bool)
        XCTAssertTrue(pending)

        var peerCalls = 0
        let status = HelperServiceController.status(effectiveUID: 501, inspect: { self.proof() },
            validateProcess: {}, registration: { .enabled }, verify: { _ in peerCalls += 1; return pending })
        XCTAssertEqual(peerCalls, 1)
        XCTAssertTrue(status.helperVerified)
        XCTAssertEqual(status.pendingHardwareRestoration, true)
        XCTAssertFalse(status.hardwareControlAvailable)
        XCTAssertEqual(HelperSetupPhase(report: status), .recoveryUnconfirmed)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any])
        XCTAssertEqual(encoded["pendingHardwareRestoration"] as? Bool, true)
    }

    func testRecoveryWarningRequiresTrustedVerifiedReplyAndNeverClaimsAutoForFalse() {
        var pending = report("enabled", verified: true)
        pending.pendingHardwareRestoration = true
        XCTAssertEqual(HelperSetupPhase(report: pending), .recoveryUnconfirmed)
        pending.helperVerified = false
        XCTAssertEqual(HelperSetupPhase(report: pending), .registered)
        pending.helperVerified = true; pending.error = "deadline"
        XCTAssertEqual(HelperSetupPhase(report: pending), .connectionFailed)
        pending.error = nil; pending.trustedBundle = false
        XCTAssertEqual(HelperSetupPhase(report: pending), .unavailable)
        pending.trustedBundle = true; pending.pendingHardwareRestoration = false
        XCTAssertEqual(HelperSetupPhase(report: pending), .verified)
        XCTAssertFalse(pending.hardwareControlAvailable)
    }

    @MainActor func testPendingRecoveryModelAllowsRefreshWithoutRegistrationOrSettings() async throws {
        var pending = report("enabled", verified: true)
        pending.pendingHardwareRestoration = true
        let saved = pending
        var registerCalls = 0
        let model = HelperSetupModel(read: { saved }, register: { _ in registerCalls += 1; return saved })
        model.refreshIfNeeded()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.phase, .recoveryUnconfirmed)
        XCTAssertFalse(model.canRegister); XCTAssertFalse(model.canOpenSettings)
        model.connect()
        XCTAssertEqual(registerCalls, 0)
        model.refresh()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.phase, .recoveryUnconfirmed)
        XCTAssertEqual(registerCalls, 0)
    }

    func testDurableMarkerSurvivesFailureAndRejectsReplayWithoutOverwriting() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Ventilator/Helper Setup", isDirectory: true)
        XCTAssertFalse(try GUIRegistrationAttempt.exists(fingerprint(), at: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try GUIRegistrationAttempt.record(fingerprint(), at: root)
        let marker = root.appendingPathComponent(try GUIRegistrationAttempt.fileName(fingerprint()))
        let before = try Data(contentsOf: marker)
        XCTAssertTrue(try GUIRegistrationAttempt.exists(fingerprint(), at: root))
        XCTAssertThrowsError(try GUIRegistrationAttempt.record(fingerprint(), at: root)) { XCTAssertEqual($0 as? InstallationError, .registrationAlreadyAttempted) }
        XCTAssertEqual(try Data(contentsOf: marker), before)
        var metadata = stat(); XCTAssertEqual(lstat(marker.path, &metadata), 0); XCTAssertEqual(metadata.st_mode & 0o777, 0o600)
        XCTAssertEqual(metadata.st_uid, geteuid())
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        XCTAssertEqual(saved["ownerUID"] as? UInt32, geteuid())
        XCTAssertEqual(saved["pid"] as? Int32, getpid())
        try GUIRegistrationAttempt.record(fingerprint("d"), at: root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testMarkerRefusesAliasesPublicDirectoryAndMalformedHashes() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let publicParent = base.appendingPathComponent("Public", isDirectory: true)
        try FileManager.default.createDirectory(at: publicParent, withIntermediateDirectories: false)
        XCTAssertEqual(chmod(publicParent.path, 0o755), 0)
        XCTAssertThrowsError(try GUIRegistrationAttempt.record(fingerprint(), at: publicParent.appendingPathComponent("Setup")))
        let alias = base.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: publicParent)
        XCTAssertThrowsError(try GUIRegistrationAttempt.record(fingerprint(), at: alias.appendingPathComponent("Setup")))
        XCTAssertThrowsError(try GUIRegistrationAttempt.record(.init(applicationSHA256: "../escape", helperSHA256: "b", launchDaemonSHA256: "c"), at: base.appendingPathComponent("Other/Setup")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("Other").path))
    }

    @MainActor func testModelWaitsForExplicitRefreshAndCallsRegisterOnceOnMainThread() async throws {
        let initial = report("notRegistered", error: "serviceNotEnabled"), pending = report("requiresApproval")
        var registerCalls = 0
        let model = HelperSetupModel(read: { XCTAssertFalse(Thread.isMainThread); return initial }, register: { expected in
            XCTAssertTrue(Thread.isMainThread); XCTAssertEqual(expected, initial.fingerprint)
            registerCalls += 1; return pending
        })
        XCTAssertEqual(model.phase, .unchecked); XCTAssertFalse(model.canRegister); XCTAssertEqual(registerCalls, 0)
        model.refreshIfNeeded(); model.refresh(); model.connect()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.phase, .notRegistered); XCTAssertTrue(model.canRegister)
        model.connect(); model.connect()
        XCTAssertEqual(model.phase, .requiresApproval); XCTAssertEqual(registerCalls, 1)
        model.refresh()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.phase, .notRegistered); XCTAssertFalse(model.canRegister)
        model.connect(); XCTAssertEqual(registerCalls, 1)
    }
}
