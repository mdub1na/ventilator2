import Foundation
import VentilatorCore

public struct ControlObservation {
    public let snapshot: MonitorSnapshot
    public let thermalPressure: ExperimentVerification.ThermalPressure
    public let testModeCode: UInt8?

    public init(snapshot: MonitorSnapshot, thermalPressure: ExperimentVerification.ThermalPressure, testModeCode: UInt8?) {
        self.snapshot = snapshot
        self.thermalPressure = thermalPressure
        self.testModeCode = testModeCode
    }
}

/// Only a simulated implementation exists. This port is not an authorization for hardware writes.
public protocol ExperimentTransport: AnyObject {
    func read(at date: Date) throws -> ControlObservation
    func simulateFixed2500RPM() throws
    func simulateAuto() throws
}

public struct SessionRecord: Codable, Equatable {
    public let id: UUID
    public let owner: UUID
    public let expiresAt: Double
}

public protocol SessionJournal: AnyObject {
    func load() throws -> SessionRecord?
    func save(_ record: SessionRecord) throws
    func clear() throws
}

public enum ControlPhase: String, Codable {
    case idle, waitingForFixed, fixedObserved, restoring, autoCodeObserved, recoveryRequired
}

public enum StopReason: String, Codable {
    case leaseExpired, heartbeatLost, clientDisconnected, explicitAuto, systemSleep, processRestart
    case thermalPressure, sensorUnavailable, profileChanged, fixedNotObserved, clockFailure
    case transportFailure, journalFailure, restoreNotObserved, rangeChanged, helperExited, systemShutdown
}

public struct ControlReport: Codable {
    public let phase: ControlPhase
    public let sessionID: UUID?
    public let reason: StopReason?
    public let simulationOnly: Bool

    public init(phase: ControlPhase, sessionID: UUID? = nil, reason: StopReason? = nil) {
        self.phase = phase
        self.sessionID = sessionID
        self.reason = reason
        self.simulationOnly = true
    }
}

public enum ControlError: Error, Equatable {
    case sessionAlreadyUsed, wrongOwnerOrSession, invalidClock, journalUnavailable
    case preflight(ExperimentVerification.PreflightFailure), testModeNotZero
}

/// Serialized by the helper. The clock must be monotonic; the lease is never renewed beyond 10 s.
public final class ControlSession {
    public static let leaseSeconds = 10.0
    public static let heartbeatSeconds = 2.0
    private let transport: ExperimentTransport
    private let journal: SessionJournal
    private var record: SessionRecord?
    private var baseline: MonitorSnapshot?
    private var used = false
    private var phase: ControlPhase = .idle
    private var reason: StopReason?
    private var lastClock: Double?
    private var heartbeatDeadline = 0.0
    private var fixedDeadline = 0.0
    private var restoreDeadline = 0.0
    private var restoreDate = Date.distantPast
    private var autoSamples: [MonitorSnapshot] = []

    public init(transport: ExperimentTransport, journal: SessionJournal) {
        self.transport = transport
        self.journal = journal
    }

    public var report: ControlReport {
        ControlReport(phase: phase, sessionID: record?.id, reason: reason)
    }

    /// An unfinished record always triggers restoration; fixed mode is never resumed after restart.
    public func recover(now: Double, date: Date) {
        guard phase == .idle, !used else { return }
        do {
            guard let pending = try journal.load() else { return }
            record = pending
            used = true
            requestRestore(.processRestart, now: now, date: date)
        } catch {
            used = true
            phase = .recoveryRequired
            reason = .journalFailure
        }
    }

    public func begin(owner: UUID, now: Double, date: Date) throws -> ControlReport {
        guard phase == .idle, !used else { throw ControlError.sessionAlreadyUsed }
        guard now.isFinite, now >= 0 else { throw ControlError.invalidClock }
        do {
            guard try journal.load() == nil else { throw ControlError.journalUnavailable }
        } catch { throw ControlError.journalUnavailable }
        let observation = try transport.read(at: date)
        if let failure = ExperimentVerification.preflight(observation.snapshot, now: date, thermalPressure: observation.thermalPressure) {
            throw ControlError.preflight(failure)
        }
        guard observation.testModeCode == 0 else { throw ControlError.testModeNotZero }
        let pending = SessionRecord(id: UUID(), owner: owner, expiresAt: now + Self.leaseSeconds)
        do { try journal.save(pending) } catch { throw ControlError.journalUnavailable }
        record = pending
        baseline = observation.snapshot
        used = true
        lastClock = now
        heartbeatDeadline = now + Self.heartbeatSeconds
        fixedDeadline = now + 5
        phase = .waitingForFixed
        do { try transport.simulateFixed2500RPM() }
        catch { requestRestore(.transportFailure, now: now, date: date) }
        return report
    }

    public func heartbeat(owner: UUID, sessionID: UUID, now: Double, date: Date) throws -> ControlReport {
        try checkOwner(owner, sessionID)
        tick(now: now, date: date) // A late heartbeat cannot revive an expired lease.
        guard phase == .waitingForFixed || phase == .fixedObserved else { throw ControlError.sessionAlreadyUsed }
        heartbeatDeadline = min(now + Self.heartbeatSeconds, record!.expiresAt)
        return report
    }

    public func restore(owner: UUID, sessionID: UUID, now: Double, date: Date) throws -> ControlReport {
        try checkOwner(owner, sessionID)
        requestRestore(.explicitAuto, now: now, date: date)
        return report
    }

    public func disconnected(owner: UUID, now: Double, date: Date) {
        guard record?.owner == owner else { return }
        requestRestore(.clientDisconnected, now: now, date: date)
    }

    public func willSleep(now: Double, date: Date) {
        requestRestore(.systemSleep, now: now, date: date)
    }

    public func helperExited(now: Double, date: Date) {
        requestRestore(.helperExited, now: now, date: date)
    }

    public func willTerminate(now: Double, date: Date) {
        requestRestore(.systemShutdown, now: now, date: date)
    }

    public func tick(now: Double, date: Date) {
        guard [.waitingForFixed, .fixedObserved, .restoring].contains(phase) else { return }
        guard now.isFinite, now >= 0, lastClock.map({ now >= $0 }) ?? true else {
            if phase == .restoring { phase = .recoveryRequired; reason = .clockFailure }
            else { requestRestore(.clockFailure, now: lastClock ?? 0, date: date) }
            return
        }
        lastClock = now
        if phase == .restoring { observeRestoration(now: now, date: date); return }
        if now >= record!.expiresAt { requestRestore(.leaseExpired, now: now, date: date); return }
        if now >= heartbeatDeadline { requestRestore(.heartbeatLost, now: now, date: date); return }
        let observation: ControlObservation
        do { observation = try transport.read(at: date) }
        catch { requestRestore(.sensorUnavailable, now: now, date: date); return }
        if let failure = monitoringFailure(observation, date: date) {
            requestRestore(failure, now: now, date: date); return
        }
        if let baseline, zip(baseline.fans, observation.snapshot.fans).contains(where: {
            $0.minimumRPM != $1.minimumRPM || $0.maximumRPM != $1.maximumRPM
        }) {
            requestRestore(.rangeChanged, now: now, date: date); return
        }
        if let baseline, ExperimentVerification.fixedRPMConfirmed(baseline: baseline, observed: observation.snapshot) {
            phase = .fixedObserved
        } else if phase == .fixedObserved || now >= fixedDeadline {
            requestRestore(.fixedNotObserved, now: now, date: date)
        }
    }

    private func checkOwner(_ owner: UUID, _ sessionID: UUID) throws {
        guard record?.owner == owner, record?.id == sessionID else { throw ControlError.wrongOwnerOrSession }
    }

    private func monitoringFailure(_ observation: ControlObservation, date: Date) -> StopReason? {
        let snapshot = observation.snapshot
        guard snapshot.modelIdentifier == "Mac15,7", snapshot.macOSVersion == "27.0.1", snapshot.macOSBuild == "26A434" else { return .profileChanged }
        guard observation.thermalPressure == .nominal else { return .thermalPressure }
        guard snapshot.smcAvailable, snapshot.fans.map(\.index) == [0, 1],
              date.timeIntervalSince(snapshot.sampledAt) >= 0, date.timeIntervalSince(snapshot.sampledAt) <= 3,
              snapshot.fans.allSatisfy({ fan in
                  guard let actual = fan.actualRPM, let target = fan.targetRPM,
                        let low = fan.minimumRPM, let high = fan.maximumRPM, fan.modeCode != nil else { return false }
                  return actual.isFinite && target.isFinite && low.isFinite && high.isFinite &&
                      actual >= 0 && target >= 0 && low > 0 && high > low
              }), observation.testModeCode != nil else { return .sensorUnavailable }
        return nil
    }

    private func requestRestore(_ cause: StopReason, now: Double, date: Date) {
        guard phase == .waitingForFixed || phase == .fixedObserved || (used && phase == .idle) else { return }
        reason = cause
        phase = .restoring
        lastClock = now
        restoreDate = date
        restoreDeadline = now + 8
        autoSamples = []
        do { try transport.simulateAuto() }
        catch { phase = .recoveryRequired; reason = .transportFailure }
    }

    private func observeRestoration(now: Double, date: Date) {
        if now >= restoreDeadline { phase = .recoveryRequired; reason = .restoreNotObserved; return }
        guard let observation = try? transport.read(at: date),
              monitoringFailure(observation, date: date) == nil, observation.testModeCode == 0 else { return }
        if autoSamples.last.map({ observation.snapshot.sampledAt.timeIntervalSince($0.sampledAt) >= 1 }) ?? true {
            autoSamples.append(observation.snapshot)
        }
        if ExperimentVerification.autoModeSustained(autoSamples, after: restoreDate) {
            do { try journal.clear(); phase = .autoCodeObserved }
            catch { phase = .recoveryRequired; reason = .journalFailure }
        }
    }
}
