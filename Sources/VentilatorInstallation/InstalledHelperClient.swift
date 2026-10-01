import Darwin
import Foundation
import VentilatorControl

/// The audit-token UID/PID and a CDHash-pinned XPC requirement authenticate the peer, not its JSON claims.
public enum InstalledHelperClient {
    public static let timeoutSeconds = 2.0
    public static func verify(_ proof: SignedBundleProof) throws -> HelperInstallationReply {
        let session = try InstalledHelperSession(proof: proof)
        defer { session.close() }
        return session.installation
    }

    internal static func validate(_ reply: HelperInstallationReply, proof: SignedBundleProof, nonce: UUID,
                                  peerPID: Int32, peerUID: UInt32, started: Double, now: Double) throws {
        guard started.isFinite, now.isFinite, now >= started, now < started + timeoutSeconds else { throw InstallationError.deadline }
        guard peerPID > 0, peerUID == 0, reply.processIdentifier == peerPID, reply.effectiveUID == peerUID else { throw InstallationError.peerIdentity }
        guard reply.protocolVersion == 1, reply.nonce == nonce, reply.teamIdentifier == proof.teamIdentifier,
              reply.applicationCDHash == proof.applicationCDHash, reply.helperCDHash == proof.helperCDHash,
              reply.applicationSHA256 == proof.fingerprint.applicationSHA256, reply.helperSHA256 == proof.fingerprint.helperSHA256,
              reply.launchDaemonSHA256 == proof.fingerprint.launchDaemonSHA256, !reply.hardwareControlAvailable,
              ControlPhase(rawValue: reply.simulationPhase) != nil else { throw InstallationError.invalidReply }
    }

    public static func clock() -> Double {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return .nan }
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

/// Retains the authenticated connection whose server-generated owner is locally approved.
/// No approval issuer, arbitrary service, path, PID or write payload is exposed here.
public final class InstalledHelperSession {
    public let installation: HelperInstallationReply
    private let connection: NSXPCConnection
    private let failed: InstallationReplyBox
    public init(proof: SignedBundleProof) throws {
        guard geteuid() != 0 else { throw InstallationError.nonRootApplicationRequired }
        try SignedBundleInspector.requireInstalled(proof)
        let failure = InstallationReplyBox()
        failed = failure
        connection = NSXPCConnection(machServiceName: SignedBundleInspector.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: VentilatorHelperProtocol.self)
        connection.setCodeSigningRequirement(try SignedBundleInspector.requirement(role: .helper, proof: proof))
        connection.invalidationHandler = { failure.set(.failure(InstallationError.remoteFailure)) }
        connection.interruptionHandler = { failure.set(.failure(InstallationError.remoteFailure)) }
        connection.resume()
        do {
            let nonce = UUID(), started = InstalledHelperClient.clock()
            let data = try Self.call(connection, failed: failure, seconds: 2) { $0.installationStatus(nonce.uuidString, reply: $1) }
            installation = try JSONDecoder().decode(HelperInstallationReply.self, from: data)
            try InstalledHelperClient.validate(installation, proof: proof, nonce: nonce,
                peerPID: connection.processIdentifier, peerUID: connection.effectiveUserIdentifier,
                started: started, now: InstalledHelperClient.clock())
        } catch { connection.invalidate(); throw error }
    }
    deinit { close() }
    public func close() { connection.invalidate() }
    public func prepare() throws -> HelperReply { try request { $0.prepareHardwareExperiment(reply: $1) } }
    public func start(challenge: UUID, planSHA256: String) throws -> HelperReply {
        try request(seconds: 5) { $0.startApprovedHardwareExperiment(challenge.uuidString, planSHA256: planSHA256, reply: $1) }
    }
    public func heartbeat(session: UUID) throws -> HelperReply {
        try request { $0.heartbeatHardwareExperiment(session.uuidString, reply: $1) }
    }
    public func restore(session: UUID) throws -> HelperReply {
        try request { $0.restoreHardwareExperiment(session.uuidString, reply: $1) }
    }
    public func status() throws -> HelperReply { try request { $0.hardwareExperimentStatus(reply: $1) } }

    private func request(seconds: Double = 2, _ send: (VentilatorHelperProtocol, @escaping (Data) -> Void) -> Void) throws -> HelperReply {
        do {
            let data = try Self.call(connection, failed: failed, seconds: seconds, send)
            let reply = try JSONDecoder().decode(HelperReply.self, from: data)
            guard connection.processIdentifier == installation.processIdentifier, connection.effectiveUserIdentifier == 0 else {
                throw InstallationError.peerIdentity
            }
            try Self.validate(reply)
            return reply
        } catch { close(); throw error }
    }
    internal static func validate(_ reply: HelperReply) throws {
        guard reply.protocolVersion == 1, !reply.hardwareControlAvailable, reply.control.simulationOnly,
              reply.hardwareExperiment.map({ $0.domain == ExperimentDomain.hardware.rawValue && !$0.physicalAutoVerified &&
                  ["idle", "fixed", "restoring", "autoCodesObserved", "recoveryRequired"].contains($0.phase) }) ?? true else {
            throw InstallationError.invalidReply
        }
    }
    private static func call(_ connection: NSXPCConnection, failed: InstallationReplyBox, seconds: Double,
                             _ send: (VentilatorHelperProtocol, @escaping (Data) -> Void) -> Void) throws -> Data {
        let box = InstallationReplyBox(), started = InstalledHelperClient.clock()
        guard started.isFinite, failed.get() == nil,
              let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in box.set(.failure(InstallationError.remoteFailure)) }) as? VentilatorHelperProtocol else {
            throw InstallationError.remoteFailure
        }
        send(proxy) { box.set(.success($0)) }
        while box.get() == nil, failed.get() == nil, InstalledHelperClient.clock() < started + seconds {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let now = InstalledHelperClient.clock()
        guard now.isFinite, now >= started, now < started + seconds else { throw InstallationError.deadline }
        if failed.get() != nil { throw InstallationError.remoteFailure }
        guard let result = box.get() else { throw InstallationError.deadline }
        let data = try result.get()
        guard data.count <= 16_384 else { throw InstallationError.oversizedReply }
        return data
    }
}

private final class InstallationReplyBox {
    private let lock = NSLock()
    private var value: Result<Data, Error>?
    func set(_ next: Result<Data, Error>) { lock.lock(); defer { lock.unlock() }; if value == nil { value = next } }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return value }
}
