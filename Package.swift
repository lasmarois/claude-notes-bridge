// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-notes-bridge",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "claude-notes-bridge", targets: ["claude-notes-bridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0")
    ],
    targets: [
        .executableTarget(
            name: "claude-notes-bridge",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/claude-notes-bridge",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
