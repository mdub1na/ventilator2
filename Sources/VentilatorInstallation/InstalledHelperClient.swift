import Darwin
import Foundation
import VentilatorControl

/// The audit-token UID/PID and a CDHash-pinned XPC requirement authenticate the peer, not its JSON claims.
public enum InstalledHelperClient {
    public static let timeoutSeconds = 2.0
    public static func verify(_ proof: SignedBundleProof) throws -> HelperInstallationReply {
        guard geteuid() != 0 else { throw InstallationError.nonRootApplicationRequired }
        try SignedBundleInspector.requireInstalled(proof)
        let nonce = UUID(), started = clock()
        let connection = NSXPCConnection(machServiceName: SignedBundleInspector.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: VentilatorHelperProtocol.self)
        connection.setCodeSigningRequirement(try SignedBundleInspector.requirement(role: .helper, proof: proof))
        let box = InstallationReplyBox()
        connection.invalidationHandler = { box.set(.failure(InstallationError.remoteFailure)) }
        connection.interruptionHandler = { box.set(.failure(InstallationError.remoteFailure)) }
        connection.resume(); defer { connection.invalidate() }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in box.set(.failure(InstallationError.remoteFailure)) }) as? VentilatorHelperProtocol else {
            throw InstallationError.remoteFailure
        }
        proxy.installationStatus(nonce.uuidString) { box.set(.success($0)) }
        while box.get() == nil, clock() < started + timeoutSeconds {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard let result = box.get() else { throw InstallationError.deadline }
        let data = try result.get()
        guard data.count <= 16_384 else { throw InstallationError.oversizedReply }
        let reply = try JSONDecoder().decode(HelperInstallationReply.self, from: data)
        try validate(reply, proof: proof, nonce: nonce, peerPID: connection.processIdentifier,
            peerUID: connection.effectiveUserIdentifier, started: started, now: clock())
        return reply
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

    private static func clock() -> Double {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return .nan }
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

private final class InstallationReplyBox {
    private let lock = NSLock()
    private var value: Result<Data, Error>?
    func set(_ next: Result<Data, Error>) { lock.lock(); defer { lock.unlock() }; if value == nil { value = next } }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return value }
}
