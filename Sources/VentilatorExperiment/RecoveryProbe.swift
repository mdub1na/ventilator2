import Darwin
import Foundation
import VentilatorControl

public struct RecoveryProbeRequest: Codable {
    public let id: UUID
    public let scope: RecoveryScope
    public let deadline: Double
    public init(id: UUID, scope: RecoveryScope, deadline: Double) { self.id = id; self.scope = scope; self.deadline = deadline }
}

public struct RecoveryProbeReply: Codable {
    public let id: UUID
    public let scope: RecoveryScope
    public let phase: RecoveryPhase
    public let deadline: Double
    public init(id: UUID, scope: RecoveryScope, phase: RecoveryPhase, deadline: Double) {
        self.id = id; self.scope = scope; self.phase = phase; self.deadline = deadline
    }
}

public enum RecoveryProbeError: Error, Equatable { case invalidPipe, invalidClock, expired, timeout, closed, frame, binding, wrongPhase }

/// Inherited private pipes with a fresh request ID on every probe. A model reply never becomes a hardware witness.
/// The client owns duplicates; it never uses a PID or socket path supplied by public XPC.
public final class RecoveryProbeClient {
    public let scope: RecoveryScope
    public let phase: RecoveryPhase
    public let deadline: Double
    private let input: Int32
    private let output: Int32
    private let clock: () -> Double
    private var lastClock: Double
    private var failed = false

    public init(scope: RecoveryScope, phase: RecoveryPhase, deadline: Double, input: Int32, output: Int32,
                clock: @escaping () -> Double = ExperimentMonotonicClock.now) throws {
        let now = clock()
        guard [.fixed, .restoring].contains(phase), deadline.isFinite, now.isFinite, now >= 0, deadline > now else {
            throw RecoveryProbeError.expired
        }
        var inputInfo = stat(), outputInfo = stat()
        guard input != output, fstat(input, &inputInfo) == 0, fstat(output, &outputInfo) == 0,
              inputInfo.st_mode & S_IFMT == S_IFIFO, outputInfo.st_mode & S_IFMT == S_IFIFO,
              inputInfo.st_uid == geteuid(), outputInfo.st_uid == geteuid() else { throw RecoveryProbeError.invalidPipe }
        let ownedInput = dup(input), ownedOutput = dup(output)
        guard ownedInput >= 0, ownedOutput >= 0 else {
            if ownedInput >= 0 { close(ownedInput) }; if ownedOutput >= 0 { close(ownedOutput) }
            throw RecoveryProbeError.invalidPipe
        }
        do {
            for descriptor in [ownedInput, ownedOutput] {
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
                      fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw RecoveryProbeError.invalidPipe }
                let noSignal: Int32 = 1
                guard fcntl(descriptor, F_SETNOSIGPIPE, noSignal) == 0 else { throw RecoveryProbeError.invalidPipe }
            }
        } catch { close(ownedInput); close(ownedOutput); throw error }
        self.scope = scope; self.phase = phase; self.deadline = deadline
        self.input = ownedInput; self.output = ownedOutput; self.clock = clock; lastClock = now
    }

    deinit { close(input); close(output) }

    /// Any failure permanently closes this witness; there is no retry or reuse of a stale acknowledgement.
    public func confirm() throws {
        guard !failed else { throw RecoveryProbeError.closed }
        do {
            let now = try time()
            guard now < deadline else { throw RecoveryProbeError.expired }
            let request = RecoveryProbeRequest(id: UUID(), scope: scope, deadline: min(deadline, now + CandidateExperimentPlan.operationSeconds))
            var data = try JSONEncoder().encode(request)
            guard data.count <= 1024 else { throw RecoveryProbeError.frame }
            data.append(10)
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    try poll(output, events: Int16(POLLOUT), until: request.deadline)
                    let count = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EAGAIN || errno == EINTR { continue }
                    guard count > 0 else { throw RecoveryProbeError.closed }
                    offset += count
                }
            }
            var buffer = Data()
            while true {
                try poll(input, events: Int16(POLLIN), until: request.deadline)
                var bytes = [UInt8](repeating: 0, count: 256)
                let count = Darwin.read(input, &bytes, bytes.count)
                if count < 0, errno == EAGAIN || errno == EINTR { continue }
                guard count > 0 else { throw RecoveryProbeError.closed }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 1024 else { throw RecoveryProbeError.frame }
                if let newline = buffer.firstIndex(of: 10) {
                    guard newline == buffer.count - 1 else { throw RecoveryProbeError.frame }
                    let reply = try JSONDecoder().decode(RecoveryProbeReply.self, from: buffer.prefix(upTo: newline))
                    guard reply.id == request.id, reply.scope == scope, reply.deadline == request.deadline else {
                        throw RecoveryProbeError.binding
                    }
                    guard reply.phase == phase else { throw RecoveryProbeError.wrongPhase }
                    guard try time() < request.deadline else { throw RecoveryProbeError.timeout }
                    return
                }
            }
        } catch { failed = true; throw error }
    }

    private func time() throws -> Double {
        let now = clock()
        guard now.isFinite, now >= lastClock else { throw RecoveryProbeError.invalidClock }
        lastClock = now; return now
    }

    private func poll(_ descriptor: Int32, events: Int16, until deadline: Double) throws {
        while true {
            let remaining = deadline - (try time())
            guard remaining > 0 else { throw RecoveryProbeError.timeout }
            var item = pollfd(fd: descriptor, events: events, revents: 0)
            let status = Darwin.poll(&item, 1, Int32(ceil(min(remaining * 1000, 500))))
            if status < 0, errno == EINTR { continue }
            guard status > 0 else { throw RecoveryProbeError.timeout }
            guard item.revents & Int16(POLLNVAL | POLLERR) == 0 else { throw RecoveryProbeError.closed }
            return
        }
    }
}
