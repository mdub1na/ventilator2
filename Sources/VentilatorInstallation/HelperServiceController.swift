import Darwin
import Foundation
import ServiceManagement
import VentilatorControl

public struct HelperServiceReport: Encodable, Sendable {
    public var registration: String
    public var trustedBundle = false
    public var installedLocation = false
    public var rootOwned = false
    public var helperVerified = false
    /// nil means no authenticated reply; false does not establish physical Auto recovery.
    public var pendingHardwareRestoration: Bool?
    public let hardwareControlAvailable = false
    public var fingerprint: InstallationFingerprint?
    public var error: String?
    public var registrationDiagnostic: String?
    public init(registration: String) { self.registration = registration }
}

/// Explicit app CLI actions only. No registration during status, GUI launch, signing or build.
public enum HelperServiceController {
    /// Checks bundle files only. Never creates an SMAppService or contacts the helper.
    public static func inspectBundle(_ bundle: URL? = nil) -> HelperServiceReport {
        inspectBundle(effectiveUID: geteuid(), inspect: {
            try SignedBundleInspector.inspect(bundle ?? SignedBundleInspector.currentBundleURL())
        })
    }

    public static func status() -> HelperServiceReport {
        status(effectiveUID: geteuid(), inspect: {
            try SignedBundleInspector.inspect(SignedBundleInspector.currentBundleURL())
        }, validateProcess: {
            _ = try SignedBundleInspector.requireCurrentProcess(role: .application)
        }, registration: {
            SMAppService.daemon(plistName: SignedBundleInspector.plistName).status
        }, verify: {
            try InstalledHelperClient.verify($0).pendingHardwareRestoration
        })
    }

    internal static func inspectBundle(effectiveUID: uid_t, inspect: () throws -> SignedBundleProof) -> HelperServiceReport {
        var report = HelperServiceReport(registration: "notQueried")
        do {
            guard effectiveUID != 0 else { throw InstallationError.nonRootApplicationRequired }
            report = bundleReport(try inspect())
        } catch { report.error = String(describing: error) }
        return report
    }

    internal static func status(effectiveUID: uid_t, inspect: () throws -> SignedBundleProof,
                               validateProcess: () throws -> Void, registration: () -> SMAppService.Status,
                               verify: (SignedBundleProof) throws -> Bool) -> HelperServiceReport {
        var report = HelperServiceReport(registration: "notQueried")
        do {
            guard effectiveUID != 0 else { throw InstallationError.nonRootApplicationRequired }
            let proof = try inspect()
            report = bundleReport(proof)
            // A status query can update BTM's app URL. Admit only the canonical installed process
            // before even constructing the framework service; staging uses inspectBundle instead.
            try SignedBundleInspector.requireInstalled(proof)
            try validateProcess()
            let state = registration()
            report.registration = name(state)
            guard state == .enabled else { throw InstallationError.serviceNotEnabled }
            report.pendingHardwareRestoration = try verify(proof)
            report.helperVerified = true
        } catch { report.error = String(describing: error) }
        return report
    }

    private static func bundleReport(_ proof: SignedBundleProof) -> HelperServiceReport {
        var report = HelperServiceReport(registration: "notQueried")
        report.trustedBundle = true; report.installedLocation = proof.installedLocation
        report.rootOwned = proof.rootOwned; report.fingerprint = proof.fingerprint
        return report
    }

    public static func register() throws -> HelperServiceReport {
        _ = try SignedBundleInspector.requireCurrentProcess(role: .application)
        let service = SMAppService.daemon(plistName: SignedBundleInspector.plistName)
        do {
            try registerIfNeeded(status: service.status, registration: service.register)
        } catch {
            guard registrationAwaitsApproval(error, status: service.status) else { throw error }
            var report = status()
            report.registrationDiagnostic = String(describing: error)
            return report
        }
        return status()
    }

    /// Explicit GUI action. Record before register; leave peer verification to background status.
    @MainActor public static func registerFromGUI(expected: InstallationFingerprint) throws -> HelperServiceReport {
        try registerFromGUI(expected: expected, inspectProcess: {
            try SignedBundleInspector.requireCurrentProcess(role: .application)
        }, state: {
            SMAppService.daemon(plistName: SignedBundleInspector.plistName).status
        }, claim: { try GUIRegistrationAttempt.record($0.fingerprint) }, register: {
            try SMAppService.daemon(plistName: SignedBundleInspector.plistName).register()
        })
    }

    internal static func registerFromGUI(expected: InstallationFingerprint,
        inspectProcess: () throws -> SignedBundleProof, state: () -> SMAppService.Status,
        claim: (SignedBundleProof) throws -> Void, register: () throws -> Void) throws -> HelperServiceReport {
        let proof = try inspectProcess()
        try SignedBundleInspector.requireInstalled(proof)
        guard proof.fingerprint == expected else { throw InstallationError.runtimeIdentityRejected }
        let before = state()
        var report = bundleReport(proof); report.registration = name(before)
        guard before == .notRegistered || before == .notFound else {
            guard before == .enabled || before == .requiresApproval else { throw InstallationError.serviceNotEnabled }
            return report
        }
        try claim(proof)
        do { try register() }
        catch {
            let after = state(); report.registration = name(after)
            if registrationAwaitsApproval(error, status: after) { report.registrationDiagnostic = String(describing: error) }
            else { report.error = String(describing: error) }
            return report
        }
        report.registration = name(state())
        return report
    }

    public static func guiStatus() -> HelperServiceReport {
        var report = status()
        if ["notRegistered", "notFound"].contains(report.registration), let fingerprint = report.fingerprint {
            do {
                if try GUIRegistrationAttempt.exists(fingerprint) { report.error = "registrationAlreadyAttempted" }
            } catch { report.error = String(describing: error) }
        }
        return report
    }

    internal static func registrationAwaitsApproval(_ error: Error, status: SMAppService.Status) -> Bool {
        guard #available(macOS 15.0, *) else { return false }
        let error = error as NSError
        // Error 1 alone is insufficient: require the framework's actual post-register state.
        return error.domain == SMAppServiceErrorDomain && error.code == 1 && status == .requiresApproval
    }

    internal static func registerIfNeeded(status: SMAppService.Status, registration: () throws -> Void) throws {
        switch status {
        // On this Mac a new daemon has no BTM record and reports notFound before register.
        // The caller already verified the signed layout; let the framework register or report its error.
        case .notRegistered, .notFound: try registration()
        case .enabled, .requiresApproval: break
        @unknown default: throw InstallationError.serviceNotEnabled
        }
    }

    public static func unregister() throws -> HelperServiceReport {
        let proof = try SignedBundleInspector.requireCurrentProcess(role: .application)
        let service = SMAppService.daemon(plistName: SignedBundleInspector.plistName)
        if service.status == .notRegistered { return status() }
        if service.status == .requiresApproval {
            try admitUnstartedRemoval(status: service.status,
                stateURL: URL(fileURLWithPath: "/Library/Application Support/Ventilator"))
            try service.unregister()
            return status()
        }
        guard service.status == .enabled else { throw InstallationError.serviceNotEnabled }
        let reply = try InstalledHelperClient.verify(proof)
        try admitRemoval(reply)
        try service.unregister()
        return status()
    }
    internal static func admitRemoval(_ reply: HelperInstallationReply) throws {
        guard !reply.pendingHardwareRestoration else { throw InstallationError.pendingRecovery }
        guard [.idle, .autoCodeObserved].contains(ControlPhase(rawValue: reply.simulationPhase)) else { throw InstallationError.simulationActive }
    }
    // An initialized daemon creates this root before accepting XPC. Any state, including a
    // broken symlink or an inaccessible path, forbids this narrow pre-experiment repair.
    internal static func admitUnstartedRemoval(status: SMAppService.Status, stateURL: URL) throws {
        guard status == .requiresApproval else { throw InstallationError.serviceNotEnabled }
        var metadata = stat()
        guard lstat(stateURL.path, &metadata) == -1, errno == ENOENT else { throw InstallationError.pendingRecovery }
    }
    private static func name(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }
}
