import Foundation

/// The current wire contract explicitly operates on simulation. Hardware control has no RPC.
@objc public protocol VentilatorHelperProtocol {
    func status(reply: @escaping (Data) -> Void)
    func startSimulation(reply: @escaping (Data) -> Void)
    func heartbeat(_ sessionID: String, reply: @escaping (Data) -> Void)
    func restoreSimulation(_ sessionID: String, reply: @escaping (Data) -> Void)
    func prepareHardwareExperiment(reply: @escaping (Data) -> Void)
    func startApprovedHardwareExperiment(_ challengeID: String, planSHA256: String, reply: @escaping (Data) -> Void)
}

public struct HelperReply: Codable {
    public let protocolVersion: Int
    public let hardwareControlAvailable: Bool
    public let control: ControlReport
    public let errorCode: String?
    public let preparation: HardwarePreparation?

    public init(control: ControlReport, errorCode: String? = nil, preparation: HardwarePreparation? = nil) {
        self.protocolVersion = 1
        self.hardwareControlAvailable = false
        self.control = control
        self.errorCode = errorCode
        self.preparation = preparation
    }
}

public struct HardwarePreparation: Codable {
    public let planSHA256: String
    public let readyForOwnerApproval: Bool
    public let blockers: [String]
    public init(planSHA256: String) {
        self.planSHA256 = planSHA256
        self.readyForOwnerApproval = false
        self.blockers = ["hardwareRecoveryBrokerNotConnected", "localApprovalIssuerNotConnected",
                         "installedSignedHelperUnverified", "ownerSessionInstructionsPending"]
    }
}
