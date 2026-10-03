import Darwin
import Foundation
import ServiceManagement
import VentilatorControl

public struct HelperServiceReport: Encodable {
    public var registration: String
    public var trustedBundle = false
    public var installedLocation = false
    public var rootOwned = false
    public var helperVerified = false
    public let hardwareControlAvailable = false
    public var fingerprint: InstallationFingerprint?
    public var error: String?
    public var registrationDiagnostic: String?
}

/// Explicit app CLI actions only. No registration during status, GUI launch, signing or build.
public enum HelperServiceController {
    public static func status() -> HelperServiceReport {
        let service = SMAppService.daemon(plistName: SignedBundleInspector.plistName)
        var report = HelperServiceReport(registration: name(service.status))
        do {
            guard geteuid() != 0 else { throw InstallationError.nonRootApplicationRequired }
            let proof = try SignedBundleInspector.inspect(SignedBundleInspector.currentBundleURL())
            report.trustedBundle = true; report.installedLocation = proof.installedLocation
            report.rootOwned = proof.rootOwned; report.fingerprint = proof.fingerprint
            _ = try SignedBundleInspector.requireCurrentProcess(role: .application)
            guard service.status == .enabled else { throw InstallationError.serviceNotEnabled }
            _ = try InstalledHelperClient.verify(proof)
            report.helperVerified = true
        } catch { report.error = String(describing: error) }
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
