// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SoundbarKeys",
    // Liquid Glass (NSGlassEffectView, SwiftUI .glass) requires macOS 26.
    // macOS 27 APIs are used additionally behind #available.
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic without UI, network or Keychain: testable with `swift test`.
        .target(
            name: "SoundbarKeysCore",
            path: "Sources/SoundbarKeysCore"
        ),
        .executableTarget(
            name: "SoundbarKeys",
            dependencies: ["SoundbarKeysCore"],
            path: "Sources/SoundbarKeys",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "SoundbarKeysCoreTests",
            dependencies: ["SoundbarKeysCore"],
            path: "Tests/SoundbarKeysCoreTests"
        ),
    ]
)
