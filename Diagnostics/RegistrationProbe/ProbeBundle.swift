import CryptoKit
import Darwin
import Foundation
import MachO
import Security

enum ProbeFailure: Error { case layout, identity, ownership, certificate, session, replay }

/// Fixed, separate diagnostic identity. This code has no Ventilator or device dependencies.
enum ProbeBundle {
    static let appID = "dev.ventilator.registration-probe"
    static let daemonID = "dev.ventilator.registration-probe.daemon"
    static let plistName = daemonID + ".plist"
    static let installed = "/Applications/Ventilator Registration Probe.app"
    static let team = "4659S5GD6X"
    static let certificate = "4895C06FF7407EAF5F350E78CF23D0B41AD466C9"
    static let files = ["Contents/Info.plist", "Contents/MacOS/RegistrationProbe",
                        "Contents/MacOS/RegistrationProbeDaemon", "Contents/_CodeSignature/CodeResources",
                        "Contents/Library/LaunchDaemons/" + plistName]

    struct Proof {
        let url: URL
        let fingerprint: [String: String]
        let appCDHash: String
        let daemonCDHash: String
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func read(_ url: URL, limit: Int = 64 * 1024) throws -> Data {
        guard url.resolvingSymlinksInPath() == url.standardizedFileURL,
              (try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])).isRegularFile == true,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else { throw ProbeFailure.layout }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw ProbeFailure.layout }
        return data
    }

    static func inspect(_ url: URL, online: Bool = false) throws -> Proof {
        guard url.pathExtension == "app", url.resolvingSymlinksInPath() == url.standardizedFileURL else { throw ProbeFailure.layout }
        let info = try PropertyListSerialization.propertyList(from: read(url.appendingPathComponent(files[0])), format: nil) as? [String: Any]
        let launch = try PropertyListSerialization.propertyList(from: read(url.appendingPathComponent(files[4])), format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == appID, info?["CFBundleExecutable"] as? String == "RegistrationProbe",
              let launch, Set(launch.keys) == ["Label", "BundleProgram", "RunAtLoad"],
              launch["Label"] as? String == daemonID, launch["BundleProgram"] as? String == files[2],
              launch["RunAtLoad"] as? Bool == true else { throw ProbeFailure.layout }
        var fingerprints: [String: String] = [:]
        for file in files { fingerprints[file] = digest(try read(url.appendingPathComponent(file), limit: 128 * 1024 * 1024)) }
        let appHash = try signature(url, identifier: appID, online: online)
        let daemonHash = try signature(url.appendingPathComponent(files[2]), identifier: daemonID, online: online)
        for file in files {
            guard digest(try read(url.appendingPathComponent(file), limit: 128 * 1024 * 1024)) == fingerprints[file] else { throw ProbeFailure.identity }
        }
        return Proof(url: url, fingerprint: fingerprints, appCDHash: appHash, daemonCDHash: daemonHash)
    }

    private static func signature(_ path: URL, identifier: String, online: Bool) throws -> String {
        var code: SecStaticCode?, raw: CFDictionary?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(path as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any], info[kSecCodeInfoTeamIdentifier as String] as? String == team,
              let hash = info[kSecCodeInfoUnique as String] as? Data,
              let chain = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = chain.first,
              Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map({ String(format: "%02X", $0) }).joined() == certificate else { throw ProbeFailure.identity }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, [.considerExpiration, .noNetworkAccess], requirement) == errSecSuccess else { throw ProbeFailure.identity }
        if online {
            guard let signing = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil),
                  let revocation = SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationUseAnyAvailableMethod | kSecRevocationRequirePositiveResponse)) else { throw ProbeFailure.certificate }
            var trust: SecTrust?
            guard SecTrustCreateWithCertificates(chain as CFArray, [signing, revocation] as CFArray, &trust) == errSecSuccess,
                  let trust, SecTrustSetNetworkFetchAllowed(trust, true) == errSecSuccess else { throw ProbeFailure.certificate }
            var error: CFError?
            guard SecTrustEvaluateWithError(trust, &error) else { throw error.map { $0 as Error } ?? ProbeFailure.certificate }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func installedProcess(daemon: Bool = false) throws -> Proof {
        guard (geteuid() == 0) == daemon else { throw ProbeFailure.ownership }
        var size: UInt32 = 0
        guard _NSGetExecutablePath(nil, &size) == -1, size > 1, size <= 65_536 else { throw ProbeFailure.layout }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { throw ProbeFailure.layout }
        let executable = String(cString: buffer)
        guard executable == installed + "/" + files[daemon ? 2 : 1] else { throw ProbeFailure.layout }
        let url = URL(fileURLWithPath: installed), proof = try inspect(url)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { throw ProbeFailure.ownership }
        for path in [url] + enumerator.compactMap({ $0 as? URL }) {
            var meta = stat()
            guard lstat(path.path, &meta) == 0, meta.st_uid == 0, meta.st_mode & 0o022 == 0,
                  meta.st_mode & S_IFMT != S_IFLNK else { throw ProbeFailure.ownership }
        }
        var code: SecCode?, requirement: SecRequirement?
        let id = daemon ? daemonID : appID, hash = daemon ? proof.daemonCDHash : proof.appCDHash
        let text = "anchor apple generic and identifier \"\(id)\" and certificate leaf[subject.OU] = \"\(team)\" and cdhash H\"\(hash)\""
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { throw ProbeFailure.identity }
        return proof
    }

    static func session(_ path: String, proof: Proof) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var meta = stat()
        guard path == url.path, url.resolvingSymlinksInPath() == url, lstat(path, &meta) == 0,
              meta.st_uid == getuid(), meta.st_mode & 0o077 == 0, meta.st_mode & S_IFMT == S_IFDIR else { throw ProbeFailure.session }
        let manifest = try JSONSerialization.jsonObject(with: read(url.appendingPathComponent("manifest.json"))) as? [String: Any]
        let seal = try JSONSerialization.jsonObject(with: read(url.appendingPathComponent("sealed.json"))) as? [String: Any]
        guard manifest?["sessionPath"] as? String == path, manifest?["ownerUID"] as? UInt32 == getuid(),
              manifest?["purpose"] as? String == "isolatedRegistrationProbe", seal?["positiveRevocation"] as? Bool == true,
              seal?["fingerprint"] as? [String: String] == proof.fingerprint else { throw ProbeFailure.session }
        return url
    }

    static func save(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .withoutOverwriting)
    }
}
