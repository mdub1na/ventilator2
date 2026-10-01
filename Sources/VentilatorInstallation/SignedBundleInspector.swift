import CryptoKit
import Darwin
import Foundation
import Security

public enum InstallationError: Error, Equatable {
    case nonRootApplicationRequired, invalidLayout, appleSignatureRequired, signatureRejected(Int32)
    case installedLocationRequired, rootOwnershipRequired, runtimeIdentityRejected
    case serviceNotEnabled, invalidChallenge, invalidReply, peerIdentity, deadline, pendingRecovery
    case simulationActive, remoteFailure, oversizedReply
    case unsafeRuntimePolicy
}

public struct InstallationFingerprint: Codable, Equatable {
    public let applicationSHA256: String
    public let helperSHA256: String
    public let launchDaemonSHA256: String
    public init(applicationSHA256: String, helperSHA256: String, launchDaemonSHA256: String) {
        self.applicationSHA256 = applicationSHA256; self.helperSHA256 = helperSHA256; self.launchDaemonSHA256 = launchDaemonSHA256
    }
}

public struct SignedBundleProof {
    public let bundleURL: URL
    public let teamIdentifier: String
    public let applicationCDHash: String
    public let helperCDHash: String
    public let fingerprint: InstallationFingerprint
    public let rootOwned: Bool
    public var installedLocation: Bool { bundleURL.path == SignedBundleInspector.installedPath }
}

/// Static signatures plus exact launch layout; this proves neither registration nor a running daemon.
public enum SignedBundleInspector {
    public static let installedPath = "/Applications/Ventilator.app"
    public static let plistName = "dev.ventilator.helper.plist"
    public static let machService = "dev.ventilator.helper"
    // checkTrustedAnchors is rejected by validation on this macOS (errSecCSInvalidFlags).
    // Apple anchoring is required by the explicit requirement; expiry/network policy stays enforced.
    internal static let offlineFlags: SecCSFlags = [.considerExpiration, .noNetworkAccess]
    public enum Role: Equatable { case application, helper }

    public static func currentBundleURL() -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    public static func inspect(_ bundle: URL) throws -> SignedBundleProof {
        let bundle = bundle.standardizedFileURL
        guard bundle.pathExtension == "app", bundle.resolvingSymlinksInPath().path == bundle.path else { throw InstallationError.invalidLayout }
        let app = bundle.appendingPathComponent("Contents/MacOS/Ventilator")
        let helper = bundle.appendingPathComponent("Contents/MacOS/VentilatorHelper")
        let plist = bundle.appendingPathComponent("Contents/Library/LaunchDaemons/\(plistName)")
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        for file in [app, helper, plist, info] {
            guard file.resolvingSymlinksInPath().path == file.path,
                  (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw InstallationError.invalidLayout }
        }
        let launchData = try boundedData(plist, maximum: 16_384), infoData = try boundedData(info, maximum: 16_384)
        try validateLayout(launchData: launchData, infoData: infoData)
        let applicationInfo = try signature(bundle, identifier: "dev.ventilator.macos")
        let helperInfo = try signature(helper, identifier: machService, team: applicationInfo.team)
        return .init(bundleURL: bundle, teamIdentifier: applicationInfo.team,
            applicationCDHash: applicationInfo.cdhash, helperCDHash: helperInfo.cdhash,
            fingerprint: .init(applicationSHA256: digest(try boundedData(app, maximum: 128 * 1024 * 1024)),
                helperSHA256: digest(try boundedData(helper, maximum: 128 * 1024 * 1024)), launchDaemonSHA256: digest(launchData)),
            rootOwned: try allRootOwned(bundle))
    }

    internal static func validateLayout(launchData: Data, infoData: Data) throws {
        guard let launch = try PropertyListSerialization.propertyList(from: launchData, format: nil) as? [String: Any],
              Set(launch.keys) == ["Label", "BundleProgram", "MachServices"],
              launch["Label"] as? String == machService,
              launch["BundleProgram"] as? String == "Contents/MacOS/VentilatorHelper",
              let services = launch["MachServices"] as? [String: Any], Set(services.keys) == [machService],
              let enabled = services[machService] as? NSNumber, CFGetTypeID(enabled) == CFBooleanGetTypeID(), enabled.boolValue,
              let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "dev.ventilator.macos",
              info["CFBundleExecutable"] as? String == "Ventilator", info["CFBundlePackageType"] as? String == "APPL" else {
            throw InstallationError.invalidLayout
        }
    }

    public static func requireCurrentProcess(role: Role) throws -> SignedBundleProof {
        if role == .application && geteuid() == 0 { throw InstallationError.nonRootApplicationRequired }
        if role == .helper && geteuid() != 0 { throw InstallationError.peerIdentity }
        let proof = try inspect(currentBundleURL())
        try requireInstalled(proof)
        let executable = proof.bundleURL.appendingPathComponent("Contents/MacOS/\(role == .application ? "Ventilator" : "VentilatorHelper")")
        guard URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path == executable.path else { throw InstallationError.runtimeIdentityRejected }
        var code: SecCode?, requirement: SecRequirement?
        let text = try Self.requirement(role: role, proof: proof)
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, offlineFlags, requirement) == errSecSuccess else { throw InstallationError.runtimeIdentityRejected }
        return proof
    }

    public static func requireInstalled(_ proof: SignedBundleProof) throws {
        guard proof.installedLocation else { throw InstallationError.installedLocationRequired }
        guard proof.rootOwned else { throw InstallationError.rootOwnershipRequired }
    }

    public static func requirement(role: Role, proof: SignedBundleProof) throws -> String {
        let hash = role == .application ? proof.applicationCDHash : proof.helperCDHash
        guard validTeam(proof.teamIdentifier), [40, 64].contains(hash.utf8.count),
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw InstallationError.runtimeIdentityRejected }
        let identifier = role == .application ? "dev.ventilator.macos" : machService
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(proof.teamIdentifier)\" and cdhash H\"\(hash)\""
    }

    private static func signature(_ path: URL, identifier: String, team expectedTeam: String? = nil) throws -> (team: String, cdhash: String) {
        var code: SecStaticCode?, information: CFDictionary?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(path as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any], let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              validTeam(team), expectedTeam.map({ $0 == team }) ?? true,
              let cdhash = info[kSecCodeInfoUnique as String] as? Data else { throw InstallationError.appleSignatureRequired }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { throw InstallationError.appleSignatureRequired }
        try validateRuntimePolicy(flags: (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0,
            entitlements: info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:])
        // Keep the bounded diagnostic/device paths free of network lookups. Online certificate
        // revocation/notarization qualification is a separate installed-owner gate, not claimed here.
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode |
            offlineFlags.rawValue)
        let result = SecStaticCodeCheckValidity(code, flags, requirement)
        guard result == errSecSuccess else { throw InstallationError.signatureRejected(result) }
        // Check X.509 validity/system anchors without requiring a freshly cached OCSP response on
        // the bounded device path. Code signing/Apple identity is validated above; the owner
        // qualification separately requires positive online CodeSigning + revocation evaluation.
        guard let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty else {
            throw InstallationError.appleSignatureRequired
        }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust, SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else {
            throw InstallationError.appleSignatureRequired
        }
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            throw error.map { $0 as Error } ?? InstallationError.appleSignatureRequired
        }
        return (team, cdhash.map { String(format: "%02x", $0) }.joined())
    }
    internal static func validateRuntimePolicy(flags: UInt32, entitlements: [String: Any]) throws {
        guard flags & SecCodeSignatureFlags.runtime.rawValue != 0 else { throw InstallationError.unsafeRuntimePolicy }
        for key in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                    "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory",
                    "com.apple.security.cs.allow-jit"] {
            guard entitlements[key].map({ ($0 as? NSNumber)?.boolValue == false }) ?? true else { throw InstallationError.unsafeRuntimePolicy }
        }
    }
    private static func validTeam(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func boundedData(_ path: URL, maximum: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: path); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw InstallationError.invalidLayout }
        return data
    }
    private static func allRootOwned(_ bundle: URL) throws -> Bool {
        var enumerationFailed = false
        guard let items = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isSymbolicLinkKey],
            errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw InstallationError.invalidLayout }
        var paths = [bundle], count = 0
        for case let item as URL in items {
            count += 1; guard count <= 4096 else { throw InstallationError.invalidLayout }
            guard (try item.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw InstallationError.invalidLayout }
            paths.append(item)
        }
        guard !enumerationFailed else { throw InstallationError.invalidLayout }
        return try paths.allSatisfy {
            let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
            return (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0 &&
                ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o022 == 0
        }
    }
}
