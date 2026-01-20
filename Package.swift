// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-notes-bridge",
    platforms: [
        .macOS(.v13)  // Required for Core ML semantic search
    ],
    products: [
        .executable(name: "claude-notes-bridge", targets: ["claude-notes-bridge"]),
        .executable(name: "notes-search", targets: ["NotesSearch"]),
        .executable(name: "benchmark", targets: ["Benchmark"]),
        .library(name: "NotesLib", targets: ["NotesLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
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
            resources: [
                .copy("Search/Resources/all-MiniLM-L6-v2.mlmodelc"),
                .process("Search/Resources/bert_tokenizer_vocab.txt")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate")
            ]
        ),
        // Executable that uses the library
        .executableTarget(
            name: "claude-notes-bridge",
            dependencies: [
                "NotesLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/claude-notes-bridge"
        ),
        // SwiftUI Search App
        .executableTarget(
            name: "NotesSearch",
            dependencies: ["NotesLib"],
            path: "Sources/NotesSearch"
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
