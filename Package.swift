// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Scout",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Scout", targets: ["ScoutApp"]),
        .executable(name: "scout-bench", targets: ["ScoutBench"]),
        .executable(name: "scout-signals", targets: ["ScoutSignals"]),
        .library(name: "ScoutCore", targets: ["ScoutCore"]),
    ],
    targets: [
        .target(name: "ScoutCore"),
        .executableTarget(
            name: "ScoutApp",
            dependencies: ["ScoutCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("WebKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(name: "ScoutBench", dependencies: ["ScoutCore"]),
        .executableTarget(name: "ScoutSignals", dependencies: ["ScoutCore"]),
        .testTarget(name: "ScoutCoreTests", dependencies: ["ScoutCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
