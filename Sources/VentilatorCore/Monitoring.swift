import CSMCRead
import CHIDTemperature
import Darwin
import Foundation

public struct FanReading: Equatable, Identifiable, Sendable {
    public let index: Int
    public let actualRPM: Double?
    public let targetRPM: Double?
    public let minimumRPM: Double?
    public let maximumRPM: Double?
    public let modeCode: UInt8?

    public init(index: Int, actualRPM: Double?, targetRPM: Double?, minimumRPM: Double?, maximumRPM: Double?, modeCode: UInt8?) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.modeCode = modeCode
    }

    public var id: Int { index }

    public var relativeLevel: Int? {
        guard let actualRPM, let minimumRPM, let maximumRPM,
              actualRPM.isFinite, minimumRPM.isFinite, maximumRPM.isFinite,
              minimumRPM >= 0, maximumRPM > minimumRPM else { return nil }
        if actualRPM <= 0 { return 0 }
        let fraction = max(0, min(1, (actualRPM - minimumRPM) / (maximumRPM - minimumRPM)))
        return max(1, min(5, Int(ceil(fraction * 5))))
    }

    public var modeDescription: String {
        guard let modeCode else { return "Нет данных" }
        switch modeCode {
        case 0: return "Код 0 (возможный Auto)"
        case 1: return "Код 1 (возможный ручной)"
        case 3: return "Код 3 (возможный системный)"
        default: return "Код \(modeCode)"
        }
    }
}

public struct TemperatureReading: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let celsius: Double?
    public let source: String
    public let verified: Bool
}

public struct MonitorSnapshot: Equatable, Sendable {
    public let modelIdentifier: String
    public let macOSVersion: String
    public let macOSBuild: String
    public let sampledAt: Date
    public let fans: [FanReading]
    public let temperatures: [TemperatureReading]
    public let smcAvailable: Bool

    public init(modelIdentifier: String, macOSVersion: String, macOSBuild: String, sampledAt: Date,
                fans: [FanReading], temperatures: [TemperatureReading], smcAvailable: Bool) {
        self.modelIdentifier = modelIdentifier
        self.macOSVersion = macOSVersion
        self.macOSBuild = macOSBuild
        self.sampledAt = sampledAt
        self.fans = fans
        self.temperatures = temperatures
        self.smcAvailable = smcAvailable
    }

    public var maximumFanLevel: Int? {
        fans.compactMap(\.relativeLevel).max()
    }

    public var cpuTemperature: Double? {
        temperatures.first { $0.id == "cpu" }?.celsius
    }

    public static var placeholder: MonitorSnapshot {
        MonitorSnapshot(
            modelIdentifier: "—", macOSVersion: "—", macOSBuild: "—",
            sampledAt: .distantPast, fans: [], temperatures: [], smcAvailable: false
        )
    }
}

public enum SMCMonitor {
    public static func poll() -> MonitorSnapshot {
        let identity = hardwareIdentity()
        var temperatures = temperatureReadings(identity)
        guard let connection = SMCReadOpen() else {
            temperatures.append(unlabelledReading(nil))
            return MonitorSnapshot(
                modelIdentifier: identity.model, macOSVersion: identity.version,
                macOSBuild: identity.build, sampledAt: Date(), fans: [],
                temperatures: temperatures, smcAvailable: false
            )
        }
        defer { SMCReadClose(connection) }

        let count = min(8, Int(readUInt8(connection, key: "FNum") ?? 0))
        let fans = (0..<count).map { index in
            let prefix = "F\(index)"
            return FanReading(
                index: index,
                actualRPM: readNumber(connection, key: prefix + "Ac"),
                targetRPM: readNumber(connection, key: prefix + "Tg"),
                minimumRPM: readNumber(connection, key: prefix + "Mn"),
                maximumRPM: readNumber(connection, key: prefix + "Mx"),
                modeCode: readUInt8(connection, key: prefix + "Md")
            )
        }
        let candidate = readNumber(connection, key: "Tf26")
        temperatures.append(unlabelledReading(candidate))
        return MonitorSnapshot(
            modelIdentifier: identity.model, macOSVersion: identity.version,
            macOSBuild: identity.build, sampledAt: Date(), fans: fans,
            temperatures: temperatures, smcAvailable: true
        )
    }

    private static func temperatureReadings(_ identity: (model: String, version: String, build: String)) -> [TemperatureReading] {
        var nand: Double?
        if TemperatureSources.supportsNAND(model: identity.model, version: identity.version, build: identity.build) {
            var value = Double.nan
            if HIDTemperatureReadNAND(&value) == 0 { nand = value }
        }
        return [
            TemperatureReading(id: "cpu", label: "CPU", celsius: nil, source: "Источник не подтверждён", verified: false),
            TemperatureReading(id: "gpu", label: "GPU", celsius: nil, source: "Источник не подтверждён", verified: false),
            TemperatureSources.nandReading(model: identity.model, version: identity.version, build: identity.build, rawCelsius: nand)
        ]
    }

    private static func unlabelledReading(_ value: Double?) -> TemperatureReading {
        TemperatureReading(id: "Tf26", label: "Неразмеченный датчик", celsius: plausibleTemperature(value),
                           source: "SMC Tf26", verified: false)
    }

    private static func plausibleTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (-10...125).contains(value) else { return nil }
        return value
    }

    private static func readUInt8(_ connection: OpaquePointer, key: String) -> UInt8? {
        guard let value = read(connection, key: key), value.type == fourCC("ui8 "), value.size == 1 else {
            return nil
        }
        return withUnsafeBytes(of: value.bytes) { $0[0] }
    }

    private static func readNumber(_ connection: OpaquePointer, key: String) -> Double? {
        guard let value = read(connection, key: key) else { return nil }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0) }
        if value.type == fourCC("flt ") && value.size == 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let number = Double(Float(bitPattern: bits))
            return number.isFinite ? number : nil
        }
        if value.type == fourCC("fpe2") && value.size == 2 {
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        }
        if value.type == fourCC("sp78") && value.size == 2 {
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        }
        return nil
    }

    private static func read(_ connection: OpaquePointer, key: String) -> SMCReadValue? {
        var value = SMCReadValue()
        let result = key.withCString { SMCReadKey(connection, $0, &value) }
        return result == 0 ? value : nil
    }

    private static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func hardwareIdentity() -> (model: String, version: String, build: String) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (
            sysctlString("hw.model") ?? "Неизвестная модель",
            "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            sysctlString("kern.osversion") ?? "Неизвестная сборка"
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
