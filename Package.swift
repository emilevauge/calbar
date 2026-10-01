// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Calbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Calbar", targets: ["Calbar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "CalbarCore",
            path: "Sources/CalbarCore"
        ),
        .executableTarget(
            name: "Calbar",
            dependencies: [
                "CalbarCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Calbar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CalbarCoreTests",
            dependencies: ["CalbarCore"],
            path: "Tests/CalbarCoreTests"
        )
    ]
)
