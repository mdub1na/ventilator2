import Foundation
import MachO

/// Uses dyld's loaded image path; argv[0] is a caller-supplied name, including with BundleProgram.
public enum CurrentExecutable {
    public static func url() throws -> URL {
        var size: UInt32 = 0
        guard _NSGetExecutablePath(nil, &size) == -1, size > 1, size <= 65_536 else {
            throw InstallationError.runtimeIdentityRejected
        }
        var bytes = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&bytes, &size) == 0, let end = bytes.firstIndex(of: 0), end > 0,
              let path = String(bytes: bytes[..<end].map { UInt8(bitPattern: $0) }, encoding: .utf8),
              path.hasPrefix("/") else { throw InstallationError.runtimeIdentityRejected }
        // Do not resolve symlinks here. Installed layout validation must still reject aliases.
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
