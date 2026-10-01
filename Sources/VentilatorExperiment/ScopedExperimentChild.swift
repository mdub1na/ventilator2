import Darwin
import Foundation
import VentilatorControl
import VentilatorCore

public enum ExperimentChildRole: String, Codable { case fixed, restore, reader }

/// The reader's IPC carries only the experiment's required values, never a write permission.
public struct BrokerObservation: Codable {
    public struct Fan: Codable {
        public let index: Int
        public let actual: Double?
        public let target: Double?
        public let minimum: Double?
        public let maximum: Double?
        public let mode: UInt8?
    }
    public let machine: ExperimentMachine
    public let sampledAt: Date
    public let readSeconds: Double
    public let fans: [Fan]
    public let testMode: UInt8?
    public let pressure: String

    public init(_ sample: TimedExperimentObservation) {
        let value = sample.observation, snapshot = value.snapshot
        machine = .init(model: snapshot.modelIdentifier, version: snapshot.macOSVersion, build: snapshot.macOSBuild)
        sampledAt = snapshot.sampledAt; readSeconds = sample.readSeconds; testMode = value.testModeCode
        fans = snapshot.fans.map { .init(index: $0.index, actual: $0.actualRPM, target: $0.targetRPM,
                                        minimum: $0.minimumRPM, maximum: $0.maximumRPM, mode: $0.modeCode) }
        switch value.thermalPressure {
        case .nominal: pressure = "nominal"
        case .elevated: pressure = "elevated"
        case .unavailable: pressure = "unavailable"
        }
    }

    /// Bound to the outstanding reader request, with exact ranges and a fresh timestamp.
    /// Elevated pressure is retained so the broker can close Fixed while still attempting Auto.
    public func admitted(requestedAt: Date, deadline: Double, now: Double, date: Date) throws -> ControlObservation {
        guard now.isFinite, now >= 0, deadline.isFinite, now < deadline, readSeconds.isFinite,
              requestedAt.timeIntervalSince1970.isFinite, sampledAt.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970.isFinite,
              readSeconds >= 0, readSeconds <= CandidateExperimentPlan.operationSeconds,
              sampledAt >= requestedAt, date >= sampledAt,
              date.timeIntervalSince(sampledAt) <= CandidateExperimentPlan.operationSeconds,
              machine == .candidate, fans.map(\.index) == [0, 1], testMode == 0 || testMode == 1 else {
            throw ExperimentObservationError.readDeadline
        }
        let expected = [(1350.0, 5349.0), (1458.0, 5777.0)]
        for (fan, range) in zip(fans, expected) {
            guard let actual = fan.actual, let target = fan.target, actual.isFinite, target.isFinite,
                  actual >= 0, target >= 0, fan.minimum == range.0, fan.maximum == range.1,
                  [UInt8(0), 1, 3].contains(where: { fan.mode == $0 }) else {
                throw ExperimentObservationError.unexpectedFans
            }
        }
        let thermal: ExperimentVerification.ThermalPressure
        switch pressure {
        case "nominal": thermal = .nominal
        case "elevated": thermal = .elevated
        case "unavailable": thermal = .unavailable
        default: throw ExperimentObservationError.unexpectedFans
        }
        return .init(snapshot: .init(modelIdentifier: machine.model, macOSVersion: machine.version, macOSBuild: machine.build,
            sampledAt: sampledAt, fans: fans.map { .init(index: $0.index, actualRPM: $0.actual, targetRPM: $0.target,
                minimumRPM: $0.minimum, maximumRPM: $0.maximum, modeCode: $0.mode) }, temperatures: [], smcAvailable: true),
            thermalPressure: thermal, testModeCode: testMode)
    }
}

/// Prepared native/model child boundary. Only inherited private pipes carry probes; public XPC does
/// not construct these children. A hardware ledger requires root and native open also checks signing,
/// boot, exact binaries and a fresh broker response before opening the fixed-step SMC transport.
public final class ScopedExperimentChild {
    public let role: ExperimentChildRole
    private let authority: ExperimentAuthority
    private let scope: RecoveryScope
    private let device: ExperimentStepDevice?
    private let observer: ReadOnlyExperimentObserver?
    private let model: FileSimulatedStepDevice?
    private let executor: ApprovedStepExecutor?

    public init(authority: ExperimentAuthority, scope: RecoveryScope, role: ExperimentChildRole,
                phase: RecoveryPhase, input: Int32, output: Int32) throws {
        guard let ledger = try authority.state().ledger, scope.domain == authority.domain, scope.matches(ledger),
              ledger.pendingRestoration, !ledger.autoCodesObserved,
              role != .fixed || ledger.attempts.isEmpty,
              [.fixed, .restoring].contains(phase),
              (phase == .fixed ? !ledger.fixedClosed : ledger.fixedClosed),
              role == .reader || (role == .fixed ? phase == .fixed : phase == .restoring) else {
            throw NativeExperimentError.invalidScope
        }
        let deadline: Double
        if phase == .fixed { deadline = ledger.expiresAt }
        else {
            guard let started = ledger.restoreStartedAt else { throw NativeExperimentError.invalidScope }
            deadline = started + 8
        }
        let probe = try RecoveryProbeClient(scope: scope, phase: phase, deadline: deadline, input: input, output: output)
        self.authority = authority; self.scope = scope; self.role = role
        if authority.domain == .simulation {
            guard geteuid() != 0 else { throw NativeExperimentError.simulationCannotOpenHardware }
            let model = try FileSimulatedStepDevice(directory: authority.directory, sessionID: ledger.sessionID)
            self.model = model; observer = nil
            if role == .reader { try probe.confirm(); device = nil; executor = nil }
            else {
                let device = try ProbedModelDevice(authority: authority, scope: scope, role: role, model: model, probe: probe)
                try probe.confirm()
                self.device = device
                executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
            }
        } else {
            model = nil
            if role == .reader {
                // Reader is isolated too: it can block in IOKit without blocking the broker's lease timer.
                guard currentBootSession() == ledger.approval.challenge.bootSession,
                      trustedHelperAndApplication() else { throw NativeExperimentError.untrustedSignature }
                try probe.confirm()
                observer = try .native(); device = nil; executor = nil
            } else {
                observer = try .native()
                let recovery = try ArmedHardwareRecovery(session: ledger, role: role == .fixed ? .fixed : .restoration, probe: probe)
                let device = try NativeExperimentDevice(authority: authority, sessionID: ledger.sessionID,
                    restorationOnly: role == .restore, recovery: recovery)
                self.device = device
                executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
            }
        }
    }

    public func sample() throws -> TimedExperimentObservation {
        if let observer { return try observer.sample() }
        let start = ExperimentMonotonicClock.now(), date = Date()
        return try .init(observation: model!.observation(at: date), readSeconds: ExperimentMonotonicClock.now() - start)
    }

    public func perform(_ step: ExperimentStep) throws {
        guard let executor, role != .reader, step.isFixed == (role == .fixed),
              let ledger = try authority.state().ledger, scope.matches(ledger) else { throw NativeExperimentError.invalidScope }
        let sample = try sample()
        try executor.perform(step, now: ExperimentMonotonicClock.now(), date: Date(), observation: sample.observation)
    }

    /// A fault injection stays on the simulation transport. It cannot select or alter native packets.
    public func simulateFailure(before step: ExperimentStep) throws {
        guard authority.domain == .simulation, let model else { throw NativeExperimentError.invalidScope }
        model.failBeforeStep = step
    }
    public func simulateBlock(afterEffect step: ExperimentStep) throws {
        guard authority.domain == .simulation, let device = device as? ProbedModelDevice else {
            throw NativeExperimentError.invalidScope
        }
        device.blockAfterEffect = step
    }
}

private final class ProbedModelDevice: ExperimentStepDevice {
    let domain: ExperimentDomain = .simulation
    let authority: ExperimentAuthority
    let scope: RecoveryScope
    let role: ExperimentChildRole
    let model: FileSimulatedStepDevice
    let probe: RecoveryProbeClient
    let executionLock: SessionJournalLock
    var blockAfterEffect: ExperimentStep?
    init(authority: ExperimentAuthority, scope: RecoveryScope, role: ExperimentChildRole,
         model: FileSimulatedStepDevice, probe: RecoveryProbeClient) throws {
        executionLock = try FileSessionJournal(directory: authority.directory).acquireDeviceExecutionLock(domain: .simulation)
        guard let current = try authority.state().ledger, scope.matches(current),
              role == .fixed ? !current.fixedClosed : current.fixedClosed else { throw NativeExperimentError.invalidScope }
        self.authority = authority; self.scope = scope; self.role = role; self.model = model; self.probe = probe
    }
    func write(_ reservation: ExperimentWriteReservation) throws {
        try probe.confirm()
        guard let ledger = try authority.state().ledger, scope.matches(ledger) else { throw NativeExperimentError.invalidScope }
        try ExperimentWriteAdmission.validate(reserved: reservation.ledger, current: ledger, step: reservation.step,
            domain: .simulation, sessionID: scope.sessionID, boot: scope.bootSession,
            now: ExperimentMonotonicClock.now(), role: role == .fixed ? .fixed : .restoration)
        if reservation.step.isFixed, try authority.fixedRevoked(sessionID: scope.sessionID) { throw ExperimentAuthorityError.fixedClosed }
        try model.write(reservation)
        if reservation.step == blockAfterEffect { while true { Thread.sleep(forTimeInterval: 1) } }
    }
}
