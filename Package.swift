// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Litto",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LittoCore", targets: ["LittoCore"]),
        .executable(name: "litto-mcp", targets: ["LittoMCP"]),
    ],
    dependencies: [
        // FSRS-6 is only on main; v5.0.0 (2024) predates it.
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git", revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "LittoCore", dependencies: [.product(name: "FSRS", package: "swift-fsrs")]),
        .executableTarget(name: "LittoMCP", dependencies: ["LittoCore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "LittoCoreTests", dependencies: ["LittoCore"]),
    ]
)
