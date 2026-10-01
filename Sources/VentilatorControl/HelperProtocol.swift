import Foundation

/// User control remains disabled. The experimental hardware RPC consumes root TTY approval only.
@objc public protocol VentilatorHelperProtocol {
    func status(reply: @escaping (Data) -> Void)
    func installationStatus(_ nonce: String, reply: @escaping (Data) -> Void)
    func startSimulation(reply: @escaping (Data) -> Void)
    func heartbeat(_ sessionID: String, reply: @escaping (Data) -> Void)
    func restoreSimulation(_ sessionID: String, reply: @escaping (Data) -> Void)
    func prepareHardwareExperiment(reply: @escaping (Data) -> Void)
    func startApprovedHardwareExperiment(_ challengeID: String, planSHA256: String, reply: @escaping (Data) -> Void)
    func heartbeatHardwareExperiment(_ sessionID: String, reply: @escaping (Data) -> Void)
    func restoreHardwareExperiment(_ sessionID: String, reply: @escaping (Data) -> Void)
    func hardwareExperimentStatus(reply: @escaping (Data) -> Void)
}

/// Read-only diagnostic reply. It never grants hardware authority or reports physical recovery.
public struct HelperInstallationReply: Codable {
    public let protocolVersion: Int
    public let nonce: UUID
    public let processIdentifier: Int32
    public let effectiveUID: UInt32
    public let teamIdentifier: String
    public let applicationCDHash: String
    public let helperCDHash: String
    public let applicationSHA256: String
    public let helperSHA256: String
    public let launchDaemonSHA256: String
    public let pendingHardwareRestoration: Bool
    public let simulationPhase: String
    public let hardwareControlAvailable: Bool
    public init(nonce: UUID, processIdentifier: Int32, effectiveUID: UInt32, teamIdentifier: String,
                applicationCDHash: String, helperCDHash: String, applicationSHA256: String,
                helperSHA256: String, launchDaemonSHA256: String, pendingHardwareRestoration: Bool, simulationPhase: String) {
        protocolVersion = 1; self.nonce = nonce; self.processIdentifier = processIdentifier; self.effectiveUID = effectiveUID
        self.teamIdentifier = teamIdentifier; self.applicationCDHash = applicationCDHash; self.helperCDHash = helperCDHash
        self.applicationSHA256 = applicationSHA256; self.helperSHA256 = helperSHA256; self.launchDaemonSHA256 = launchDaemonSHA256
        self.pendingHardwareRestoration = pendingHardwareRestoration; self.simulationPhase = simulationPhase
        hardwareControlAvailable = false
    }
}

public struct HelperReply: Codable {
    public let protocolVersion: Int
    public let hardwareControlAvailable: Bool
    public let control: ControlReport
    public let errorCode: String?
    public let preparation: HardwarePreparation?
    public let hardwareExperiment: HardwareExperimentReport?

    public init(control: ControlReport, errorCode: String? = nil, preparation: HardwarePreparation? = nil,
                hardwareExperiment: HardwareExperimentReport? = nil) {
        self.protocolVersion = 1
        self.hardwareControlAvailable = false
        self.control = control
        self.errorCode = errorCode
        self.preparation = preparation
        self.hardwareExperiment = hardwareExperiment
    }
}

public struct HardwarePreparation: Codable {
    public let planSHA256: String
    public let readyForOwnerApproval: Bool
    public let blockers: [String]
    public let connectionOwner: UUID?
    public let runtimePrepared: Bool
    public init(planSHA256: String, connectionOwner: UUID? = nil, runtimePrepared: Bool = true) {
        self.planSHA256 = planSHA256
        self.readyForOwnerApproval = false
        self.connectionOwner = connectionOwner; self.runtimePrepared = runtimePrepared
        self.blockers = (runtimePrepared ? [] : ["hardwareRecoveryBrokerNotConnected"]) + ["localApprovalIssuerHardwarePathUnverified",
                         "installedSignedHelperUnverified", "ownerSessionInstructionsPending"]
    }
}

/// Experimental audit status, separate from the simulation ControlReport and from product readiness.
public struct HardwareExperimentReport: Codable {
    public let domain: String
    public let sessionID: UUID?
    public let phase: String
    public let pending: Bool
    public let fixedRPMObserved: Bool
    public let physicalAutoVerified: Bool
    public init(domain: String, sessionID: UUID?, phase: String, pending: Bool, fixedRPMObserved: Bool) {
        self.domain = domain; self.sessionID = sessionID; self.phase = phase; self.pending = pending
        self.fixedRPMObserved = fixedRPMObserved; self.physicalAutoVerified = false
    }
}
