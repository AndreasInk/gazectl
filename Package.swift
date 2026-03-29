// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "gazectl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GazectlCore", targets: ["GazectlCore"]),
        .executable(name: "gazectl", targets: ["gazectl"]),
    ],
    targets: [
        .target(
            name: "GazectlCore",
            path: "CoreSources"
        ),
        .executableTarget(
            name: "gazectl",
            dependencies: ["GazectlCore"],
            path: "Sources",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Info.plist",
                ]),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Vision"),
            ]
        ),
        .testTarget(
            name: "GazectlCoreTests",
            dependencies: ["GazectlCore"],
            path: "Tests/GazectlCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
