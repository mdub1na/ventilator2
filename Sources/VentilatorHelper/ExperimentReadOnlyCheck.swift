import Darwin
import Foundation
import VentilatorCore
import VentilatorExperiment

/// A hardware read has no approval path and never constructs NativeExperimentDevice.
func experimentReadOnlyCheck() throws {
    guard geteuid() != 0 else { throw CheckError.failed("Read-only observation must run without root") }
    let observer = try ReadOnlyExperimentObserver.native()
    let result = try observer.sample(), observation = result.observation
    let snapshot = observation.snapshot
    let fans: [[String: Any]] = snapshot.fans.map {
        ["index": $0.index, "actualRPM": $0.actualRPM.map { $0 as Any } ?? NSNull(), "targetRPM": $0.targetRPM.map { $0 as Any } ?? NSNull(),
         "minimumRPM": $0.minimumRPM.map { $0 as Any } ?? NSNull(), "maximumRPM": $0.maximumRPM.map { $0 as Any } ?? NSNull(),
         "mode": $0.modeCode.map { Int($0) as Any } ?? NSNull()]
    }
    let preflight = observation.testModeCode == 0 ?
        (ExperimentVerification.preflight(snapshot, now: Date(), thermalPressure: observation.thermalPressure)?.rawValue ?? "candidatePassed") : "testModeNotZero"
    let document: [String: Any] = ["model": snapshot.modelIdentifier, "version": snapshot.macOSVersion,
        "build": snapshot.macOSBuild, "sampleStartedAt": ISO8601DateFormatter().string(from: snapshot.sampledAt),
        "readSeconds": result.readSeconds, "fans": fans, "testMode": observation.testModeCode.map { Int($0) as Any } ?? NSNull(),
        "thermalPressure": String(describing: observation.thermalPressure),
        "preflight": preflight,
        "hardwareControlAvailable": false, "hardwareWritesExecuted": 0]
    print(String(decoding: try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
}
