import PackagePlugin
import Foundation

@main
struct DMGBuilderPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // 调用 DMGBuilderExec 可执行文件
        let dmgBuilderExec = try context.tool(named: "DMGBuilderExec")
        
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: dmgBuilderExec.path.string)
        process.arguments = arguments
        
        try process.run()
        process.waitUntilExit()
    }
}
