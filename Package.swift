// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoopSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LoopSDK", targets: ["LoopSDK"])
    ],
    targets: [
        .target(
            name: "LoopSDK",
            path: "Sources/LoopSDK",
            resources: [
                .process("PrivacyInfo.xcprivacy"),
                .process("Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(
            name: "LoopSDKTests",
            dependencies: ["LoopSDK"],
            path: "Tests/LoopSDKTests"
        )
    ]
)
