import Darwin
import Foundation
import VentilatorControl

enum WorkerCommand: String, Codable { case status, start, heartbeat, restore, disconnected }

struct WorkerRequest: Codable {
    let id: UUID
    let command: WorkerCommand
    let owner: UUID
    let sessionID: UUID?
}

struct WorkerResponse: Codable {
    let id: UUID?
    let reply: HelperReply
}

/// Private inherited pipes only. Neither these commands nor the journal path are public XPC input.
final class WorkerChannel {
    private let input: Int32
    private let output: Int32
    private var buffer = Data()

    init(input: Int32, output: Int32) throws {
        self.input = input
        self.output = output
        for descriptor in [input, output] {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw CheckError.failed("Pipe flags")
            }
        }
        signal(SIGPIPE, SIG_IGN) // A dead parent must not kill its restorer through a broken pipe.
    }

    func readLine(waitSeconds: Double) throws -> Data? {
        let deadline = HelperClock.now() + waitSeconds
        guard deadline.isFinite else { throw CheckError.failed("Worker clock unavailable") }
        repeat {
            if let newline = buffer.firstIndex(of: 10) {
                guard newline <= 4096 else { throw CheckError.failed("Oversized worker frame") }
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                return Data(line)
            }
            guard buffer.count <= 4096 else { throw CheckError.failed("Oversized worker frame") }
            var item = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
            let remaining = max(0, deadline - HelperClock.now())
            let ready = poll(&item, 1, Int32(min(remaining * 1000, 2000)))
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw CheckError.failed("Pipe poll") }
            if ready == 0 { return nil }
            var bytes = [UInt8](repeating: 0, count: 512)
            let count = Darwin.read(input, &bytes, bytes.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw CheckError.failed("Worker pipe closed") }
            buffer.append(contentsOf: bytes.prefix(count))
        } while HelperClock.now() < deadline
        // Parse a frame read at the end of a zero-wait call on the next iteration.
        return nil
    }

    func send<T: Encodable>(_ value: T) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count <= 4096 else { throw CheckError.failed("Oversized worker frame") }
        data.append(10)
        let deadline = HelperClock.now() + 1
        guard deadline.isFinite else { throw CheckError.failed("Worker clock unavailable") }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let remaining = deadline - HelperClock.now()
                guard remaining > 0 else { throw CheckError.failed("Worker pipe write timeout") }
                var item = pollfd(fd: output, events: Int16(POLLOUT), revents: 0)
                guard poll(&item, 1, Int32(remaining * 1000)) > 0 else {
                    if errno == EINTR { continue }
                    throw CheckError.failed("Worker pipe unavailable")
                }
                let count = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                guard count > 0 else { throw CheckError.failed("Worker pipe closed") }
                offset += count
            }
        }
    }
}

/// The helper is a proxy; the independently timed worker exclusively owns every simulated effect.
/// This proves helper-crash isolation only. A worker crash or blocked hardware I/O is not covered.
final class SimulationWorkerClient {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let channel: WorkerChannel
    private let journal: FileSessionJournal
    private(set) var lastReply = HelperReply(control: ControlReport(phase: .idle))

    init(directory: URL, restoreFailure: Bool = false) throws {
        journal = try FileSessionJournal(directory: directory)
        channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor,
                                    output: input.fileHandleForWriting.fileDescriptor)
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = [restoreFailure ? "--simulation-worker-restore-failure" : "--simulation-worker", directory.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        do {
            guard let data = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Worker readiness timeout") }
            let response = try JSONDecoder().decode(WorkerResponse.self, from: data)
            guard response.id == nil else { throw CheckError.failed("Worker readiness frame") }
            lastReply = response.reply
        } catch {
            try? input.fileHandleForWriting.close() // EOF requests restoration, never terminates the worker.
            throw error
        }
    }

    deinit {
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }

    func waitForExit() throws {
        let deadline = HelperClock.now() + 2
        while process.isRunning, HelperClock.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !process.isRunning else { throw CheckError.failed("Worker did not exit after terminal result") }
    }

    func request(command: WorkerCommand, owner: UUID, sessionID: UUID? = nil) throws -> HelperReply {
        if [.autoCodeObserved, .recoveryRequired].contains(lastReply.control.phase) {
            if command == .status { return lastReply }
            return HelperReply(control: lastReply.control, errorCode: "sessionAlreadyUsed")
        }
        let request = WorkerRequest(id: UUID(), command: command, owner: owner, sessionID: sessionID)
        do {
            try channel.send(request)
            guard let data = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Worker reply timeout") }
            let response = try JSONDecoder().decode(WorkerResponse.self, from: data)
            guard response.id == request.id else { throw CheckError.failed("Worker reply binding") }
            lastReply = response.reply
            return response.reply
        } catch {
            // A terminal result is persisted before the worker exits. Never respawn fixed on EOF.
            if let result = try? journal.loadWorkerOutcome(),
               result.reply.control.sessionID == lastReply.control.sessionID {
                lastReply = result.reply
                return command == .status ? lastReply : HelperReply(control: lastReply.control, errorCode: "sessionAlreadyUsed")
            }
            try? input.fileHandleForWriting.close()
            throw error
        }
    }
}

func runSimulationWorker(directory: URL, restoreFailure: Bool) throws {
    var inputInfo = stat(), outputInfo = stat()
    guard fstat(STDIN_FILENO, &inputInfo) == 0, fstat(STDOUT_FILENO, &outputInfo) == 0,
          inputInfo.st_mode & S_IFMT == S_IFIFO, outputInfo.st_mode & S_IFMT == S_IFIFO else {
        throw CheckError.failed("Worker requires inherited private pipes")
    }
    let journal = try FileSessionJournal(directory: directory)
    let ownership = try journal.acquireWorkerLock()
    try journal.clearWorkerOutcome()
    let transport = SimulatedFanTransport()
    if restoreFailure { transport.fault = .restoreFailure }
    let session = ControlSession(transport: transport, journal: journal)
    let start = HelperClock.now()
    session.recover(now: start, date: Date())
    let power = SystemPowerObserver { session.willSleep(now: HelperClock.now(), date: Date()) }
    var terminating = false
    signal(SIGTERM, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler { terminating = true }
    termination.resume()
    defer { termination.cancel() }
    let channel = try WorkerChannel(input: STDIN_FILENO, output: STDOUT_FILENO)
    try channel.send(WorkerResponse(id: nil, reply: HelperReply(control: session.report)))
    var parentConnected = true
    while true {
        let now = HelperClock.now(), date = Date()
        if terminating { session.willTerminate(now: now, date: date) }
        session.tick(now: now, date: date)
        if [.autoCodeObserved, .recoveryRequired].contains(session.report.phase) {
            try journal.saveWorkerOutcome(SimulationWorkerOutcome(
                reply: HelperReply(control: session.report), effects: transport.effects,
                elapsedSeconds: now - start, powerNotificationsRegistered: power.registered))
            break
        }
        if session.report.phase == .idle && (!parentConnected || now - start >= 5 || terminating) { break }
        // The control lease and eight-second restoration deadline bound an armed worker.
        if parentConnected {
            do {
                if let data = try channel.readLine(waitSeconds: 0) {
                    let request = try JSONDecoder().decode(WorkerRequest.self, from: data)
                    var errorCode: String?
                    do {
                        switch request.command {
                        case .status: break
                        case .start: _ = try session.begin(owner: request.owner, now: HelperClock.now(), date: Date())
                        case .heartbeat, .restore:
                            guard let id = request.sessionID else { throw ControlError.wrongOwnerOrSession }
                            if request.command == .heartbeat {
                                _ = try session.heartbeat(owner: request.owner, sessionID: id, now: HelperClock.now(), date: Date())
                            } else {
                                _ = try session.restore(owner: request.owner, sessionID: id, now: HelperClock.now(), date: Date())
                            }
                        case .disconnected: session.disconnected(owner: request.owner, now: HelperClock.now(), date: Date())
                        }
                    } catch { errorCode = String(describing: error) }
                    try channel.send(WorkerResponse(id: request.id, reply: HelperReply(control: session.report, errorCode: errorCode)))
                }
            } catch {
                parentConnected = false
                session.helperExited(now: HelperClock.now(), date: Date())
            }
        }
        // Services the IOKit power source and SIGTERM callback without relying on the helper's queue.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    withExtendedLifetime(ownership) {}
    withExtendedLifetime(power) {}
}
