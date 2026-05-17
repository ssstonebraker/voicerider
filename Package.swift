// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceRider",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VoiceRider", targets: ["VoiceRider"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceRider",
            path: "Sources/VoiceRider"
        ),
        .testTarget(
            name: "VoiceRiderTests",
            dependencies: ["VoiceRider"],
            path: "Tests/VoiceRiderTests"
        )
    ]
)
