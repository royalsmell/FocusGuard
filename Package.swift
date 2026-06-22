// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusGuardCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v18)
    ],
    products: [
        .library(name: "SharedCore", targets: ["SharedCore"])
    ],
    targets: [
        .target(
            name: "SharedCore",
            path: "SharedCore/Sources",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedLibrary("compression")
            ]
        ),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["SharedCore"],
            path: "CoreChecks"
        ),
        .testTarget(
            name: "SharedCoreTests",
            dependencies: ["SharedCore"],
            path: "SharedCoreTests"
        )
    ]
)
