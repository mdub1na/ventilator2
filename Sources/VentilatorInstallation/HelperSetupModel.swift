import Combine
import Foundation

public enum HelperSetupPhase: String, CaseIterable, Sendable {
    case unchecked, checking, registering, unavailable, notRegistered, requiresApproval, registered, verified, connectionFailed, stopped

    public init(report: HelperServiceReport) {
        guard report.trustedBundle, report.rootOwned, report.installedLocation, report.fingerprint != nil else {
            self = .unavailable; return
        }
        switch report.registration {
        case "requiresApproval": self = .requiresApproval
        case "enabled": self = report.helperVerified && report.error == nil ? .verified : report.error == nil ? .registered : .connectionFailed
        case "notRegistered", "notFound": self = report.error == "registrationAlreadyAttempted" ? .stopped : (report.error == nil || report.error == "serviceNotEnabled") ? .notRegistered : .stopped
        default: self = .unavailable
        }
    }
}

@MainActor public final class HelperSetupModel: ObservableObject {
    @Published public private(set) var phase: HelperSetupPhase = .unchecked
    @Published public private(set) var report: HelperServiceReport?
    private var registrationRequested = false
    private let read: @Sendable () -> HelperServiceReport
    private let register: (InstallationFingerprint) throws -> HelperServiceReport

    public init() {
        read = { HelperServiceController.guiStatus() }
        register = HelperServiceController.registerFromGUI
    }
    internal init(read: @escaping @Sendable () -> HelperServiceReport,
                  register: @escaping (InstallationFingerprint) throws -> HelperServiceReport) {
        self.read = read; self.register = register
    }
    public var busy: Bool { phase == .checking || phase == .registering }
    public var canRegister: Bool { phase == .notRegistered && !registrationRequested }
    public var canOpenSettings: Bool { [.notRegistered, .requiresApproval, .registered, .verified, .connectionFailed, .stopped].contains(phase) }

    public func refreshIfNeeded() { if phase == .unchecked { refresh() } }
    public func refresh() {
        guard !busy else { return }
        phase = .checking
        let read = read
        Task { [weak self] in
            let next = await Task.detached(priority: .utility) { read() }.value
            self?.report = next; self?.phase = HelperSetupPhase(report: next)
        }
    }
    public func connect() {
        guard canRegister, let expected = report?.fingerprint else { return }
        registrationRequested = true; phase = .registering
        do {
            let next = try register(expected)
            report = next; phase = HelperSetupPhase(report: next)
            if phase == .notRegistered { report?.error = "registrationNotConfirmed"; phase = .stopped }
            if next.registration == "enabled" { refresh() }
        } catch {
            report?.error = String(describing: error); phase = .stopped
        }
    }
}
