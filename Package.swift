// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-notes-bridge",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "claude-notes-bridge", targets: ["claude-notes-bridge"]),
        .library(name: "NotesLib", targets: ["NotesLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "main")
    ],
    targets: [
        // Core library with all the logic
        .target(
            name: "NotesLib",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/NotesLib",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        // Executable that uses the library
        .executableTarget(
            name: "claude-notes-bridge",
            dependencies: ["NotesLib"],
            path: "Sources/claude-notes-bridge"
        ),
        // Tests for the library
        .testTarget(
            name: "NotesLibTests",
            dependencies: [
                "NotesLib",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/NotesLibTests"
        )
    ]
)
