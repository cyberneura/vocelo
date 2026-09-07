// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Vocelo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Vocelo", targets: ["Vocelo"])],
    targets: [
        .executableTarget(name: "Vocelo", linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("Carbon"),
            .linkedFramework("Speech"), .linkedFramework("AVFoundation"),
            .linkedFramework("ApplicationServices")
        ]),
        .testTarget(name: "VoceloTests", dependencies: ["Vocelo"])
    ],
    swiftLanguageModes: [.v6]
)
