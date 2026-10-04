import CryptoKit
import Foundation
import VentilatorCore

/// Offline review material only. A matching digest never authorizes a write.
public struct CandidateExperimentPlan: Codable, Equatable {
    public static let operationSeconds = 0.5
    public static let writerQuiescenceSeconds = 1.0
    public struct Binaries: Codable, Equatable {
        public let applicationSHA256: String
        public let helperSHA256: String // The recovery worker is this same executable in a separate process.
        public init(applicationSHA256: String, helperSHA256: String) {
            self.applicationSHA256 = applicationSHA256
            self.helperSHA256 = helperSHA256
        }
    }

    public struct FanRange: Codable, Equatable {
        public let index: Int
        public let minimumRPM: Double
        public let maximumRPM: Double
    }

    public struct ProposedWrite: Codable, Equatable {
        public let key: String
        public let dataType: String
        public let payloadHex: String
        public let maximumAttempts: Int
        public let prerequisite: String
    }

    public let schemaVersion: Int
    public let stage: String
    public let modelIdentifier: String
    public let macOSVersion: String
    public let macOSBuild: String
    public let binaries: Binaries
    public let fans: [FanRange]
    public let targetRPM: Double
    public let leaseSeconds: Double
    public let heartbeatSeconds: Double
    public let unlockWaitSeconds: Double
    public let fixedObservationDeadlineSeconds: Double
    public let restorationDeadlineSeconds: Double
    public let operationDeadlineSeconds: Double
    public let writerQuiescenceDeadlineSeconds: Double
    public let fixedWrites: [ProposedWrite]
    public let restoreWrites: [ProposedWrite]
    public let maximumFixedRuns: Int
    public let maximumRestoreRuns: Int
    public let maximumOwnerRecoveryRuns: Int
    public let readyForOwnerApproval: Bool
    public let restartPolicy: String

    public init(binaries: Binaries) {
        schemaVersion = 4
        stage = "candidate-unapproved"
        modelIdentifier = "Mac15,7"
        macOSVersion = "27.0.1"
        macOSBuild = "26A434"
        self.binaries = binaries
        fans = [FanRange(index: 0, minimumRPM: 1350, maximumRPM: 5349),
                FanRange(index: 1, minimumRPM: 1458, maximumRPM: 5777)]
        targetRPM = ExperimentVerification.proposedRPM
        leaseSeconds = ControlSession.leaseSeconds
        heartbeatSeconds = ControlSession.heartbeatSeconds
        unlockWaitSeconds = 3
        fixedObservationDeadlineSeconds = 5
        restorationDeadlineSeconds = 8
        operationDeadlineSeconds = Self.operationSeconds
        writerQuiescenceDeadlineSeconds = Self.writerQuiescenceSeconds
        func write(_ key: String, _ type: String, _ hex: String, _ prerequisite: String) -> ProposedWrite {
            ProposedWrite(key: key, dataType: type, payloadHex: hex, maximumAttempts: 1, prerequisite: prerequisite)
        }
        // Candidate bytes are derived from the locally read ui8/flt metadata, not an Intel fallback.
        fixedWrites = [write("Ftst", "ui8 ", "01", "approvedPreflightAndArmedRecovery"),
                       write("F0Md", "ui8 ", "01", "threeSecondWaitAndValidLease"),
                       write("F1Md", "ui8 ", "01", "precedingWriteSucceededAndValidLease"),
                       write("F0Tg", "flt ", "00401c45", "bothFansObservedManualAndValidLease"),
                       write("F1Tg", "flt ", "00401c45", "precedingWriteSucceededAndValidLease")]
        restoreWrites = [write("F0Md", "ui8 ", "00", "pendingRecordAndWriterExited"),
                         write("F1Md", "ui8 ", "00", "writerExitedEvenIfOtherFanFailed"),
                         write("F0Tg", "flt ", "00000000", "fanZeroObservedNonManual"),
                         write("F1Tg", "flt ", "00000000", "fanOneObservedNonManual"),
                         write("Ftst", "ui8 ", "00", "bothFansObservedNonManual")]
        maximumFixedRuns = 1
        maximumRestoreRuns = 1
        maximumOwnerRecoveryRuns = 1 // A separately invoked contingency, never an automatic retry.
        readyForOwnerApproval = false
        restartPolicy = "closeFixed;requireDeviceLifetimeLock;continueUnattemptedAuto;keepOriginalDeadline;noCrossBoot;ambiguousAutoKeepsPending"
    }

    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func sha256() throws -> String { Self.digest(try canonicalJSON()) }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Verifies review integrity and the candidate assumptions. It deliberately grants no authority.
    public func matchesCandidate(binaries actual: Binaries, observation: ControlObservation, now: Date) -> Bool {
        let validHash: (String) -> Bool = { $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        guard validHash(actual.applicationSHA256), validHash(actual.helperSHA256),
              self == Self(binaries: actual), observation.testModeCode == 0,
              ExperimentVerification.preflight(observation.snapshot, now: now, thermalPressure: observation.thermalPressure) == nil else { return false }
        return zip(fans, observation.snapshot.fans).allSatisfy {
            $0.index == $1.index && $0.minimumRPM == $1.minimumRPM && $0.maximumRPM == $1.maximumRPM
        }
    }
}
