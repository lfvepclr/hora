// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hora",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hora", targets: ["Hora"]),
        .executable(name: "app", targets: ["Hora"]),
        .executable(name: "dmg", targets: ["DMGBuilderExec"]),
        .plugin(name: "DMGBuilder", targets: ["DMGBuilder"])
    ],
    dependencies: [
        .package(url: "https://github.com/malcommac/SwiftDate.git", from: "7.0.0"),
        .package(url: "https://github.com/6tail/lunar-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hora",
            dependencies: [
                .product(name: "SwiftDate", package: "SwiftDate"),
                .product(name: "LunarSwift", package: "lunar-swift"),
            ],
            resources: [
                .copy("Resources/Cities.json"),
                .copy("Resources/Localizable.xcstrings"),
                .copy("Resources/worldclock.html"),
                .copy("Resources/world.json"),
                .copy("Resources/cities24tz.json"),
                .copy("Resources/countryTimezones.json"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
        ),
        
        // DMG 构建插件
        .plugin(
            name: "DMGBuilder",
            capability: .command(
                intent: .custom(
                    verb: "dmg",
                    description: "Build release and create DMG with Ad-Hoc signing"
                ),
                permissions: [.writeToPackageDirectory(reason: "Create DMG")]
            ),
            dependencies: ["DMGBuilderExec"]
        ),
        
        .executableTarget(
            name: "DMGBuilderExec",
            dependencies: []
        ),
        
        // 测试目标
        .testTarget(
            name: "HoraTests",
            dependencies: ["Hora"],
            resources: [
                .copy("world.json"),
            ]
        ),
    ]
)
