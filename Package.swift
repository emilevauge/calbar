// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Macal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Macal", targets: ["Macal"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "MacalCore",
            path: "Sources/MacalCore"
        ),
        .executableTarget(
            name: "Macal",
            dependencies: [
                "MacalCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Macal",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacalCoreTests",
            dependencies: ["MacalCore"],
            path: "Tests/MacalCoreTests"
        )
    ]
)
