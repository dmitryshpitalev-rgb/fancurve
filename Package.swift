// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FanCurve",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FanCurveCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "FanCurveHardware",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(name: "FanCurveDaemon", dependencies: ["FanCurveCore", "FanCurveHardware"]),
        .target(name: "FanCurveIPC", dependencies: ["FanCurveCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "FanCurveUI", dependencies: ["FanCurveCore", "FanCurveIPC"]),
        .executableTarget(name: "smc-probe", dependencies: ["FanCurveHardware"]),
        .executableTarget(name: "fancurvectl", dependencies: ["FanCurveIPC", "FanCurveCore"]),
        .executableTarget(name: "fancurved", dependencies: ["FanCurveCore", "FanCurveHardware", "FanCurveDaemon", "FanCurveIPC"]),
        .executableTarget(name: "FanCurveApp", dependencies: ["FanCurveUI", "FanCurveCore", "FanCurveIPC"]),
        .testTarget(name: "FanCurveCoreTests", dependencies: ["FanCurveCore"]),
        .testTarget(name: "FanCurveHardwareTests", dependencies: ["FanCurveHardware"]),
        .testTarget(name: "FanCurveDaemonTests", dependencies: ["FanCurveDaemon", "FanCurveCore", "FanCurveHardware"]),
        .testTarget(name: "FanCurveIPCTests", dependencies: ["FanCurveIPC", "FanCurveCore"]),
        .testTarget(name: "FanCurveUITests", dependencies: ["FanCurveUI", "FanCurveCore", "FanCurveIPC"]),
    ],
    swiftLanguageModes: [.v5]
)
