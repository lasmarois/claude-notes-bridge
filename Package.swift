// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-notes-bridge",
    platforms: [
        .macOS(.v13)  // Required for SimilaritySearchKit
    ],
    products: [
        .executable(name: "claude-notes-bridge", targets: ["claude-notes-bridge"]),
        .executable(name: "benchmark", targets: ["Benchmark"]),
        .library(name: "NotesLib", targets: ["NotesLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "main"),
        .package(url: "https://github.com/ZachNagengast/similarity-search-kit.git", from: "0.0.1")
    ],
    targets: [
        // Core library with all the logic
        .target(
            name: "NotesLib",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SimilaritySearchKit", package: "similarity-search-kit"),
                .product(name: "SimilaritySearchKitMiniLMAll", package: "similarity-search-kit")
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
        // Benchmark tool
        .executableTarget(
            name: "Benchmark",
            dependencies: ["NotesLib"],
            path: "Sources/Benchmark"
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
