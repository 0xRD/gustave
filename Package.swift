// swift-tools-version: 6.0
import PackageDescription

// Zero third-party dependencies on purpose. See CLAUDE.md, hard rule 3.
let package = Package(
    name: "Gustave",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Gustave", targets: ["Gustave"]),
    ],
    targets: [
        // Pure logic. No AppKit, no Accessibility, no I/O. Strict Swift 6.
        .target(name: "GustaveCore"),

        // AppKit and Accessibility glue. Starts in Swift 5 language mode so the first
        // builds are not blocked by AppKit concurrency diagnostics. Move to Swift 6 mode
        // once stable (tracked in TASKS.md, M5).
        .executableTarget(
            name: "Gustave",
            dependencies: ["GustaveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(name: "GustaveCoreTests", dependencies: ["GustaveCore"]),
    ]
)
