// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyTime",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/malcommac/SwiftDate.git", from: "7.0.0"),
        .package(url: "https://github.com/6tail/lunar-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyTime",
            dependencies: [
                .product(name: "SwiftDate", package: "SwiftDate"),
                .product(name: "LunarSwift", package: "lunar-swift"),
            ],
            resources: [
                .copy("Resources/Cities.json"),
                .copy("Resources/Localizable.xcstrings"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
        ),
    ]
)
