// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ventilator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ventilator", targets: ["Ventilator"]),
        .executable(name: "VentilatorHelper", targets: ["VentilatorHelper"]),
        .library(name: "VentilatorCore", targets: ["VentilatorCore"])
    ],
    targets: [
        .target(
            name: "CSMCRead",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "CHIDTemperature",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(name: "VentilatorCore", dependencies: ["CSMCRead", "CHIDTemperature"]),
        .target(name: "VentilatorControl", dependencies: ["VentilatorCore"]),
        .target(name: "CSMCExperiment", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "VentilatorExperiment", dependencies: ["VentilatorControl", "CSMCExperiment"]),
        .target(name: "CSystemPower", publicHeadersPath: "include"),
        .executableTarget(name: "VentilatorHelper", dependencies: ["VentilatorControl", "VentilatorExperiment", "CSystemPower"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Ventilator",
            dependencies: ["VentilatorCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "VentilatorCoreTests", dependencies: ["VentilatorCore"]),
        .testTarget(name: "VentilatorControlTests", dependencies: ["VentilatorControl"]),
        .testTarget(name: "VentilatorExperimentTests", dependencies: ["VentilatorExperiment", "CSMCExperiment"])
    ]
)
