import Darwin
import Foundation

/// A private directory, no-follow file access, atomic replacement and fsync before simulated changes.
/// Persistence across process restart is tested; survival of power loss is not a hardware guarantee.
public final class FileSessionJournal: SessionJournal {
    private let directory: URL
    private let filename = "session.json"

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = try openDirectory()
        close(descriptor)
    }

    public func load() throws -> SessionRecord? {
        guard let data = try read(filename) else { return nil }
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)
        guard record.expiresAt.isFinite, record.expiresAt >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    public func save(_ record: SessionRecord) throws {
        try write(JSONEncoder().encode(record), to: filename)
    }

    public func clear() throws { try remove(filename) }

    /// The worker retains this lock across its entire lifetime; a second worker cannot resume fixed.
    public func acquireWorkerLock() throws -> SessionJournalLock {
        try acquireLock("worker.lock")
    }

    public func acquireAuthorityLock(domain: ExperimentDomain) throws -> SessionJournalLock {
        try checkAuthorityDomain(domain)
        return try acquireLock("authority-\(domain.rawValue).lock")
    }

    public func acquireRecoveryBrokerLock() throws -> SessionJournalLock { try acquireLock("recovery-broker.lock") }
    /// Held by each writer/restorer until its device connection closes. A broker never kills a persisted PID.
    public func acquireDeviceExecutionLock(domain: ExperimentDomain) throws -> SessionJournalLock {
        try checkAuthorityDomain(domain)
        return try acquireLock("device-execution-\(domain.rawValue).lock")
    }
    public func loadLocalReview(domain: ExperimentDomain) throws -> Data? {
        try checkAuthorityDomain(domain)
        return try read("local-review-\(domain.rawValue).json", maximumBytes: 16_384)
    }
    public func saveLocalReview(_ data: Data, domain: ExperimentDomain) throws {
        try checkAuthorityDomain(domain)
        try write(data, to: "local-review-\(domain.rawValue).json", maximumBytes: 16_384)
    }
    public func acquireSimulationDeviceLock() throws -> SessionJournalLock { try acquireLock("simulation-device.lock") }
    public func loadSimulationDevice() throws -> SimulationDeviceState? {
        guard let data = try read("simulation-device.json") else { return nil }
        let state = try JSONDecoder().decode(SimulationDeviceState.self, from: data)
        guard state.modes.count == 2, state.targets.count == 2,
              state.targets.allSatisfy({ $0.isFinite && $0 >= 0 }),
              Set(state.effects).count == state.effects.count else { throw CocoaError(.fileReadCorruptFile) }
        return state
    }
    public func saveSimulationDevice(_ state: SimulationDeviceState) throws {
        try write(JSONEncoder().encode(state), to: "simulation-device.json")
    }
    public func saveRecoveryOutcome(_ outcome: SimulationRecoveryOutcome) throws {
        try write(JSONEncoder().encode(outcome), to: "recovery-result.json")
    }
    public func loadRecoveryOutcome() throws -> SimulationRecoveryOutcome? {
        guard let data = try read("recovery-result.json") else { return nil }
        return try JSONDecoder().decode(SimulationRecoveryOutcome.self, from: data)
    }
    public func saveHardwareRecoveryOutcome(_ outcome: HardwareRecoveryOutcome) throws {
        try checkAuthorityDomain(.hardware)
        try write(JSONEncoder().encode(outcome), to: "hardware-recovery-result.json")
    }

    public func loadHardwareRecoveryOutcome() throws -> HardwareRecoveryOutcome? {
        try checkAuthorityDomain(.hardware)
        guard let data = try read("hardware-recovery-result.json") else { return nil }
        let outcome = try JSONDecoder().decode(HardwareRecoveryOutcome.self, from: data)
        guard !outcome.physicalAutoVerified, !outcome.simulationOnly,
              outcome.elapsedSeconds.isFinite, outcome.elapsedSeconds >= 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return outcome
    }

    public func loadAuthorityState(domain: ExperimentDomain) throws -> ExperimentAuthorityState? {
        try checkAuthorityDomain(domain)
        guard let data = try read("authority-\(domain.rawValue).json") else { return nil }
        let state = try JSONDecoder().decode(ExperimentAuthorityState.self, from: data)
        guard state.approval.map({ $0.domain == domain }) ?? true,
              state.ledger.map({ $0.domain == domain && $0.approval.domain == domain }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        func validChallenge(_ challenge: OwnerApprovalChallenge) -> Bool {
            challenge.issuedAt.isFinite && challenge.issuedAt >= 0 &&
                challenge.expiresAt == challenge.issuedAt + ExperimentAuthority.approvalSeconds &&
                challenge.planSHA256.utf8.count == 64 &&
                (challenge.ownerReviewSHA256.map({ value in
                    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                }) ?? (domain == .simulation))
        }
        if let challenge = state.challenge, !validChallenge(challenge) { throw CocoaError(.fileReadCorruptFile) }
        if let approval = state.approval {
            guard validChallenge(approval.challenge), state.challenge == approval.challenge,
                  approval.approvedAt.isFinite, approval.approvedAt >= approval.challenge.issuedAt,
                  approval.approvedAt < approval.challenge.expiresAt else { throw CocoaError(.fileReadCorruptFile) }
        }
        if let ledger = state.ledger {
            guard state.approval == ledger.approval, ledger.startedAt.isFinite,
                  ledger.startedAt >= ledger.approval.approvedAt, ledger.startedAt < ledger.approval.challenge.expiresAt,
                  ledger.expiresAt == ledger.startedAt + ControlSession.leaseSeconds,
                  ledger.lastClock.isFinite, ledger.lastClock >= ledger.startedAt,
                  Set(ledger.attempts).count == ledger.attempts.count,
                  Set(ledger.successfulReturns ?? []).count == (ledger.successfulReturns ?? []).count,
                  Set(ledger.successfulReturns ?? []).isSubset(of: Set(ledger.attempts)),
                  (ledger.restoreStartedAt == nil) == (ledger.restoreRequestedDate == nil),
                  ledger.restoreStartedAt.map({ $0.isFinite && $0 >= ledger.startedAt && ledger.fixedClosed }) ?? true else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return state
    }

    public func saveAuthorityState(_ state: ExperimentAuthorityState, domain: ExperimentDomain) throws {
        try checkAuthorityDomain(domain)
        guard state.approval.map({ $0.domain == domain }) ?? true,
              state.ledger.map({ $0.domain == domain && $0.approval.domain == domain }) ?? true else {
            throw CocoaError(.fileWriteUnknown)
        }
        try write(JSONEncoder().encode(state), to: "authority-\(domain.rawValue).json")
    }

    public func saveFixedRevocation(_ record: FixedRevocationRecord) throws {
        try checkAuthorityDomain(record.domain)
        try write(JSONEncoder().encode(record), to: "fixed-revoked-\(record.domain.rawValue).json")
    }
    public func loadFixedRevocation(domain: ExperimentDomain) throws -> FixedRevocationRecord? {
        try checkAuthorityDomain(domain)
        guard let data = try read("fixed-revoked-\(domain.rawValue).json") else { return nil }
        let record = try JSONDecoder().decode(FixedRevocationRecord.self, from: data)
        guard record.domain == domain, record.revokedAt.isFinite, record.revokedAt >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    private func checkAuthorityDomain(_ domain: ExperimentDomain) throws {
        if domain == .hardware && geteuid() != 0 { throw ExperimentAuthorityError.hardwareRequiresRoot }
    }

    private func acquireLock(_ name: String) throws -> SessionJournalLock {
        let directoryFD = try openDirectory()
        defer { close(directoryFD) }
        let descriptor = openat(directoryFD, name, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        do {
            try checkFile(descriptor)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw posixError() }
            return SessionJournalLock(descriptor: descriptor)
        } catch { close(descriptor); throw error }
    }

    public func saveWorkerOutcome(_ outcome: SimulationWorkerOutcome) throws {
        try write(JSONEncoder().encode(outcome), to: "worker-result.json")
    }

    public func loadWorkerOutcome() throws -> SimulationWorkerOutcome? {
        guard let data = try read("worker-result.json") else { return nil }
        let result = try JSONDecoder().decode(SimulationWorkerOutcome.self, from: data)
        guard result.reply.protocolVersion == 1, result.reply.control.simulationOnly,
              !result.reply.hardwareControlAvailable, result.elapsedSeconds.isFinite,
              result.elapsedSeconds >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    public func clearWorkerOutcome() throws { try remove("worker-result.json") }

    private func read(_ name: String, maximumBytes: Int = 4096) throws -> Data? {
        let directoryFD = try openDirectory()
        defer { close(directoryFD) }
        let descriptor = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try checkFile(descriptor)
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    private func checkFile(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1 else {
            throw CocoaError(.fileReadNoPermission)
        }
    }

    private func write(_ data: Data, to name: String, maximumBytes: Int = 4096) throws {
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteInvalidFileName) }
        let directoryFD = try openDirectory()
        defer { close(directoryFD) }
        let temporary = ".session-\(UUID().uuidString).tmp"
        let descriptor = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor); unlinkat(directoryFD, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
        guard renameat(directoryFD, temporary, directoryFD, name) == 0 else { throw posixError() }
        guard fsync(directoryFD) == 0 else { throw posixError() }
    }

    private func remove(_ name: String) throws {
        let directoryFD = try openDirectory()
        defer { close(directoryFD) }
        if unlinkat(directoryFD, name, 0) != 0 && errno != ENOENT { throw posixError() }
        guard fsync(directoryFD) == 0 else { throw posixError() }
    }

    private func openDirectory() throws -> Int32 {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
            close(descriptor)
            throw CocoaError(.fileReadNoPermission)
        }
        return descriptor
    }

    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

public final class SessionJournalLock {
    private let descriptor: Int32
    fileprivate init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }
}

public struct SimulationWorkerOutcome: Codable {
    public let reply: HelperReply
    public let effects: [SimulatedEffect]
    public let elapsedSeconds: Double
    public let powerNotificationsRegistered: Bool

    public init(reply: HelperReply, effects: [SimulatedEffect], elapsedSeconds: Double, powerNotificationsRegistered: Bool) {
        self.reply = reply
        self.effects = effects
        self.elapsedSeconds = elapsedSeconds
        self.powerNotificationsRegistered = powerNotificationsRegistered
    }
}

/// Shared only by the non-root, file-backed experiment model. It never represents SMC hardware.
public struct SimulationDeviceState: Codable {
    public var modes: [UInt8] = [3, 3]
    public var targets: [Double] = [0, 0]
    public var testMode: UInt8 = 0
    public var effects: [ExperimentStep] = []
    public init() {}
}

public struct SimulationRecoveryOutcome: Codable {
    public let sessionID: UUID
    public let phase: String
    public let reason: String?
    public let events: [String]
    public let failedSteps: [ExperimentStep]
    public let elapsedSeconds: Double
    public let powerNotificationsRegistered: Bool
    public let simulationOnly: Bool

    public init(sessionID: UUID, phase: String, reason: String?, events: [String], failedSteps: [ExperimentStep],
                elapsedSeconds: Double, powerNotificationsRegistered: Bool) {
        self.sessionID = sessionID; self.phase = phase; self.reason = reason
        self.events = events; self.failedSteps = failedSteps; self.elapsedSeconds = elapsedSeconds
        self.powerNotificationsRegistered = powerNotificationsRegistered
        simulationOnly = true
    }
}

/// The prepared broker can record code evidence, but cannot declare physical Auto or clear the marker.
public struct HardwareRecoveryOutcome: Codable {
    public let sessionID: UUID
    public let phase: String
    public let reason: String?
    public let events: [String]
    public let failedSteps: [ExperimentStep]
    public let elapsedSeconds: Double
    public let powerNotificationsRegistered: Bool
    public let simulationOnly: Bool
    public let physicalAutoVerified: Bool
    public init(sessionID: UUID, phase: String, reason: String?, events: [String], failedSteps: [ExperimentStep],
                elapsedSeconds: Double, powerNotificationsRegistered: Bool) {
        self.sessionID = sessionID; self.phase = phase; self.reason = reason; self.events = events
        self.failedSteps = failedSteps; self.elapsedSeconds = elapsedSeconds
        self.powerNotificationsRegistered = powerNotificationsRegistered
        simulationOnly = false; physicalAutoVerified = false
    }
}
