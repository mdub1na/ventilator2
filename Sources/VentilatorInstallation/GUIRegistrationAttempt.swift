import Darwin
import Foundation

/// Per-owner, per-signed-fingerprint latch. Failed registration is preserved across GUI restarts.
enum GUIRegistrationAttempt {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ventilator/Helper Setup", isDirectory: true)
    }
    static func fileName(_ fingerprint: InstallationFingerprint) throws -> String {
        let hashes = [fingerprint.applicationSHA256, fingerprint.helperSHA256, fingerprint.launchDaemonSHA256]
        guard hashes.allSatisfy({ $0.utf8.count == 64 && $0.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) else {
            throw InstallationError.runtimeIdentityRejected
        }
        return hashes.joined(separator: "-") + ".json"
    }
    static func directory(_ url: URL, create: Bool) throws -> Bool {
        guard url.resolvingSymlinksInPath().path == url.path else { throw InstallationError.unsafeRuntimePolicy }
        if create {
            let result = mkdir(url.path, 0o700)
            if result != 0 && errno != EEXIST { throw posixError() }
            if result == 0 {
                let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard parent >= 0 else { throw posixError() }
                defer { close(parent) }
                guard fsync(parent) == 0 else { throw posixError() }
            }
        }
        var metadata = stat()
        if lstat(url.path, &metadata) != 0 {
            if !create && errno == ENOENT { return false }
            throw posixError()
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR, metadata.st_uid == geteuid(), metadata.st_mode & 0o777 == 0o700 else {
            throw InstallationError.unsafeRuntimePolicy
        }
        return true
    }
    static func exists(_ fingerprint: InstallationFingerprint, at url: URL = root) throws -> Bool {
        let name = try fileName(fingerprint)
        guard try directory(url.deletingLastPathComponent(), create: false), try directory(url, create: false) else { return false }
        var metadata = stat()
        if lstat(url.appendingPathComponent(name).path, &metadata) == 0 { return true }
        if errno == ENOENT { return false }
        throw posixError()
    }
    static func record(_ fingerprint: InstallationFingerprint, at url: URL = root) throws {
        guard geteuid() != 0 else { throw InstallationError.nonRootApplicationRequired }
        let name = try fileName(fingerprint)
        _ = try directory(url.deletingLastPathComponent(), create: true)
        _ = try directory(url, create: true)
        let directoryFD = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw posixError() }
        defer { close(directoryFD) }
        let descriptor = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw InstallationError.registrationAlreadyAttempted }
            throw posixError()
        }
        defer { close(descriptor) }
        struct Attempt: Encodable { let ownerUID: uid_t; let pid: pid_t; let fingerprint: InstallationFingerprint; let date: Date }
        let bytes = try JSONEncoder().encode(Attempt(ownerUID: geteuid(), pid: getpid(), fingerprint: fingerprint, date: Date()))
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, fsync(directoryFD) == 0 else { throw posixError() }
    }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
