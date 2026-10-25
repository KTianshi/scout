// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lookout",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lookout", targets: ["LookoutApp"]),
        .executable(name: "lookout-bench", targets: ["LookoutBench"]),
        .executable(name: "lookout-signals", targets: ["LookoutSignals"]),
        .library(name: "LookoutCore", targets: ["LookoutCore"]),
    ],
    targets: [
        .target(name: "LookoutCore"),
        .target(name: "ObjCTry"),
        .executableTarget(
            name: "LookoutApp",
            dependencies: ["LookoutCore", "ObjCTry"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("WebKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(name: "LookoutBench", dependencies: ["LookoutCore"]),
        .executableTarget(name: "LookoutSignals", dependencies: ["LookoutCore"]),
        .testTarget(name: "LookoutCoreTests", dependencies: ["LookoutCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
