// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RealTimeCaptionsTranslator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RealTimeCaptionsTranslatorCore", targets: ["RealTimeCaptionsTranslatorCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "135.0.0")
    ],
    targets: [
        .target(
            name: "RealTimeCaptionsTranslatorCore",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/RealTimeCaptionsTranslatorCore"
        ),
        .testTarget(
            name: "RealTimeCaptionsTranslatorTests",
            dependencies: ["RealTimeCaptionsTranslatorCore"]
        )
    ],
    swiftLanguageModes: [
        .v5
    ]
)
