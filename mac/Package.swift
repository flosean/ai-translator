// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextAITranslatorMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NextAITranslatorMac", targets: ["NextAITranslatorMac"])],
    targets: [
        .executableTarget(name: "NextAITranslatorMac"),
        .testTarget(name: "NextAITranslatorMacTests", dependencies: ["NextAITranslatorMac"])
    ]
)
