import CryptoKit
import Foundation
import Security

/// Read-only, online public-certificate qualification. Run in a disposable process with an external deadline.
/// No private key access, keychain edits, notarization claim, helper registration or device access.
public enum CertificateQualification {
    public static func qualify(bundle: URL, certificateSHA1: String) throws -> SignedBundleProof {
        guard certificateSHA1.count == 40, certificateSHA1.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else {
            throw InstallationError.invalidChallenge
        }
        let proof = try SignedBundleInspector.inspect(bundle)
        for path in [proof.bundleURL, proof.bundleURL.appendingPathComponent("Contents/MacOS/VentilatorHelper")] {
            var code: SecStaticCode?, info: CFDictionary?
            guard SecStaticCodeCreateWithPath(path as CFURL, [], &code) == errSecSuccess, let code,
                  SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let chain = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
                  let leaf = chain.first else { throw InstallationError.appleSignatureRequired }
            let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02X", $0) }.joined()
            guard digest == certificateSHA1 else { throw InstallationError.runtimeIdentityRejected }
            guard let codeSigning = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil),
                  let revocation = SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationUseAnyAvailableMethod | kSecRevocationRequirePositiveResponse)) else {
                throw InstallationError.appleSignatureRequired
            }
            var trust: SecTrust?
            guard SecTrustCreateWithCertificates(chain as CFArray, [codeSigning, revocation] as CFArray, &trust) == errSecSuccess,
                  let trust, SecTrustSetNetworkFetchAllowed(trust, true) == errSecSuccess else { throw InstallationError.appleSignatureRequired }
            var error: CFError?
            guard SecTrustEvaluateWithError(trust, &error) else {
                throw error.map { $0 as Error } ?? InstallationError.appleSignatureRequired
            }
        }
        // Re-inspect to exclude a replaced bundle between certificate evaluation and reporting.
        let after = try SignedBundleInspector.inspect(bundle)
        guard after.fingerprint == proof.fingerprint, after.applicationCDHash == proof.applicationCDHash,
              after.helperCDHash == proof.helperCDHash else { throw InstallationError.runtimeIdentityRejected }
        return after
    }
}
