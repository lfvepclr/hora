import PackagePlugin
import Foundation

@main
struct DMGBuilderPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // 1. 先执行 swift build -c release
        print("🔨 Building release...")
        let buildProcess = Foundation.Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        buildProcess.arguments = ["build", "-c", "release"]
        buildProcess.currentDirectoryURL = URL(fileURLWithPath: context.package.directory.string)
        
        try buildProcess.run()
        buildProcess.waitUntilExit()
        
        guard buildProcess.terminationStatus == 0 else {
            throw NSError(domain: "DMGBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Build failed"])
        }
        
        // 2. 调用 DMGBuilderExec 可执行文件
        print("📦 Creating DMG...")
        let dmgBuilderExec = try context.tool(named: "DMGBuilderExec")
        
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: dmgBuilderExec.path.string)
        process.arguments = arguments
        
        try process.run()
        process.waitUntilExit()
    }
}
