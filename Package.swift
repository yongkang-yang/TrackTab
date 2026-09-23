// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrackTab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TrackTab", targets: ["TrackTab"])
    ],
    targets: [
        .target(
            name: "MultitouchBridge",
            path: "Sources/MultitouchBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fobjc-arc", "-fblocks"])
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "TrackTabCore",
            path: "Sources/TrackTabCore"
        ),
        .executableTarget(
            name: "TrackTab",
            dependencies: ["MultitouchBridge", "TrackTabCore"],
            path: "Sources/TrackTab",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "TrackTabCoreTests",
            dependencies: ["TrackTabCore"],
            path: "Tests/TrackTabCoreTests"
        )
    ]
)
