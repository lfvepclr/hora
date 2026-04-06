import PackagePlugin
import Foundation

@main
struct DMGBuilderPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let fileManager = FileManager.default
        let buildPath = context.package.directory.appending(".build/release").string
        let appPath = buildPath + "/MyTime"
        
        // 检查 release 构建是否存在
        guard fileManager.fileExists(atPath: appPath) else {
            print("❌ Release build not found. Please run: swift build -c release")
            throw NSError(domain: "DMGBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Release build not found"])
        }
        
        // 调用 DMGBuilderExec 可执行文件
        print("📦 Creating DMG...")
        let dmgBuilderExec = try context.tool(named: "DMGBuilderExec")
        
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: dmgBuilderExec.path.string)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: context.package.directory.string)
        
        // 创建输出管道
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        // 输出日志
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            print(output)
        }
        if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
            print(error)
        }
    }
}
