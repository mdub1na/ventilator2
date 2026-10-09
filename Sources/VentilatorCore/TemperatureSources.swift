import Foundation

enum TemperatureSources {
    static func supportsNAND(model: String, version: String, build: String) -> Bool {
        guard model == "Mac15,7" else { return false }
        return (version == "27.0.0" && build == "26A428") ||
            (version == "27.0.1" && build == "26A434")
    }

    // The native boundary has already checked product, location, driver, uniqueness and event age.
    static func nandReading(model: String, version: String, build: String, rawCelsius: Double?) -> TemperatureReading {
        let supported = supportsNAND(model: model, version: version, build: build)
        let value = supported ? rawCelsius.flatMap { $0.isFinite && (-10...125).contains($0) ? $0 : nil } : nil
        return TemperatureReading(
            id: "ssd", label: "SSD (NAND CH0)", celsius: value,
            source: supported ? "NAND CH0 temp · встроенный накопитель" : "Источник не подтверждён для этой модели/macOS",
            verified: value != nil
        )
    }
}
