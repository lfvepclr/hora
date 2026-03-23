import Foundation

@main
struct DMGBuilder {
    
    static func createIconSet(from svgPath: String, to iconsetPath: String, resourcesPath: String) throws {
        let fileManager = FileManager.default
        
        // 创建 iconset 目录
        try fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
        
        // 定义需要的尺寸
        let sizes = [
            ("16x16", 16),
            ("16x16@2x", 32),
            ("32x32", 32),
            ("32x32@2x", 64),
            ("128x128", 128),
            ("128x128@2x", 256),
            ("256x256", 256),
            ("256x256@2x", 512),
            ("512x512", 512),
            ("512x512@2x", 1024)
        ]
        
        // 首先将 SVG 转换为临时 PNG (使用 sips 的 -s format 选项)
        let tempPngPath = "\(iconsetPath)/temp_icon.png"
        
        // 使用 qlmanage 或 textutil 预览并转换 SVG
        let qlProcess = Process()
        qlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        qlProcess.arguments = [
            "-t", "-s", "1024",
            "-o", iconsetPath,
            svgPath
        ]
        try qlProcess.run()
        qlProcess.waitUntilExit()
        
        // qlmanage 会生成一个预览文件
        let qlPreviewPath = "\(iconsetPath)/icon.svg.png"
        
        if fileManager.fileExists(atPath: qlPreviewPath) {
            // 使用 sips 生成各种尺寸
            for (iconName, size) in sizes {
                let outputPath = "\(iconsetPath)/icon_\(iconName).png"
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                process.arguments = [
                    "-z", String(size), String(size),
                    qlPreviewPath,
                    "--out", outputPath
                ]
                try process.run()
                process.waitUntilExit()
            }
            
            // 删除临时文件
            try? fileManager.removeItem(atPath: qlPreviewPath)
        } else {
            print("⚠️  Could not generate icon from SVG. Please install icon manually.")
        }
    }
    
    static func main() async throws {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        let buildPath = "\(currentPath)/.build/release"
        let appName = "MyTime"
        let appBundlePath = "\(buildPath)/\(appName).app"
        
        // 1. 创建 .app bundle 结构
        print("📦 Creating app bundle...")
        
        // 如果已存在则删除
        if fileManager.fileExists(atPath: appBundlePath) {
            try fileManager.removeItem(atPath: appBundlePath)
        }
        
        // 创建目录结构
        let contentsPath = "\(appBundlePath)/Contents"
        let macOSPath = "\(contentsPath)/MacOS"
        let resourcesPath = "\(contentsPath)/Resources"
        
        try fileManager.createDirectory(atPath: macOSPath, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: resourcesPath, withIntermediateDirectories: true)
        
        // 复制可执行文件
        let executableSource = "\(buildPath)/\(appName)"
        let executableDest = "\(macOSPath)/\(appName)"
        try fileManager.copyItem(atPath: executableSource, toPath: executableDest)
        
        // 复制资源 bundle
        let bundleSource = "\(buildPath)/\(appName)_MyTime.bundle"
        if fileManager.fileExists(atPath: bundleSource) {
            try fileManager.copyItem(atPath: bundleSource, toPath: "\(resourcesPath)/\(appName)_MyTime.bundle")
        }
        
        // 创建应用图标
        print("🎨 Creating app icon...")
        let svgPath = "\(currentPath)/icon.svg"
        let iconsetPath = "\(currentPath)/.build/MyTime.iconset"
        let icnsPath = "\(resourcesPath)/AppIcon.icns"
        
        if fileManager.fileExists(atPath: svgPath) {
            try createIconSet(from: svgPath, to: iconsetPath, resourcesPath: resourcesPath)
            
            // 使用 iconutil 转换为 icns
            let iconutilProcess = Process()
            iconutilProcess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            iconutilProcess.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
            try iconutilProcess.run()
            iconutilProcess.waitUntilExit()
            
            // 清理 iconset
            try? fileManager.removeItem(atPath: iconsetPath)
        }
        
        // 创建 Info.plist
        let iconFileName = fileManager.fileExists(atPath: svgPath) ? "AppIcon" : ""
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>\(appName)</string>
            <key>CFBundleIconFile</key>
            <string>\(iconFileName)</string>
            <key>CFBundleIdentifier</key>
            <string>com.mytime.app</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(appName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key>
            <string>14.0</string>
            <key>NSHighResolutionCapable</key>
            <true/>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
        </dict>
        </plist>
        """
        
        let infoPlistPath = "\(contentsPath)/Info.plist"
        try infoPlist.write(toFile: infoPlistPath, atomically: true, encoding: .utf8)
        
        let distPath = "\(currentPath)/dist"
        
        // 确保 dist 目录存在
        if !fileManager.fileExists(atPath: distPath) {
            try fileManager.createDirectory(atPath: distPath, withIntermediateDirectories: true)
        }
        
        // 2. Ad-Hoc 签名 .app
        print("🔏 Signing app...")
        let signProcess = Process()
        signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProcess.arguments = [
            "-s", "-",
            "--deep",
            "--force",
            "--options", "runtime",
            appBundlePath
        ]
        try signProcess.run()
        signProcess.waitUntilExit()
        
        // 3. 创建临时目录用于 DMG
        print("💿 Creating DMG...")
        let tempDmgDir = "\(currentPath)/.build/dmg_temp"
        if fileManager.fileExists(atPath: tempDmgDir) {
            try fileManager.removeItem(atPath: tempDmgDir)
        }
        try fileManager.createDirectory(atPath: tempDmgDir, withIntermediateDirectories: true)
        
        // 复制 app 到临时目录
        try fileManager.copyItem(atPath: appBundlePath, toPath: "\(tempDmgDir)/\(appName).app")
        
        // 创建 Applications 符号链接
        try fileManager.createSymbolicLink(
            atPath: "\(tempDmgDir)/Applications",
            withDestinationPath: "/Applications"
        )
        
        // 4. 使用 hdiutil 创建 DMG (使用 detach 方法)
        let dmgPath = "\(distPath)/\(appName).dmg"
        let tempDmgPath = "\(distPath)/\(appName)-temp.dmg"
        
        // 删除已存在的 DMG
        if fileManager.fileExists(atPath: dmgPath) {
            try fileManager.removeItem(atPath: dmgPath)
        }
        if fileManager.fileExists(atPath: tempDmgPath) {
            try fileManager.removeItem(atPath: tempDmgPath)
        }
        
        // 步骤 1: 创建一个空的可读写 DMG (使用 -megabytes 避免大小问题)
        let createProcess = Process()
        createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        createProcess.arguments = [
            "create",
            "-megabytes", "100",
            "-fs", "HFS+",
            "-volname", appName,
            "-attach",
            tempDmgPath
        ]
        var createOutputPipe = Pipe()
        createProcess.standardOutput = createOutputPipe
        createProcess.standardError = createOutputPipe
        try createProcess.run()
        createProcess.waitUntilExit()
        
        // 检查是否成功，如果失败尝试另一种方法
        if createProcess.terminationStatus != 0 {
            print("⚠️ hdiutil attach failed, trying alternative method...")
            
            // 替代方法: 直接使用 srcfolder
            let altProcess = Process()
            altProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            altProcess.arguments = [
                "create",
                "-volname", appName,
                "-srcfolder", tempDmgDir,
                "-ov",
                "-format", "UDZO",
                "-imagekey", "zlib-level=9",
                dmgPath
            ]
            try altProcess.run()
            altProcess.waitUntilExit()
            
            if altProcess.terminationStatus != 0 {
                // 最后尝试: 使用 UDRW 格式
                print("⚠️ Trying UDRW format...")
                let udzoProcess = Process()
                udzoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                udzoProcess.arguments = [
                    "create",
                    "-volname", appName,
                    "-srcfolder", tempDmgDir,
                    "-ov",
                    "-format", "UDRW",
                    dmgPath
                ]
                try udzoProcess.run()
                udzoProcess.waitUntilExit()
                
                guard udzoProcess.terminationStatus == 0 else {
                    throw NSError(domain: "DMGBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "hdiutil failed"])
                }
            }
            
            // 清理临时目录
            try? fileManager.removeItem(atPath: tempDmgDir)
            
            // 签名 DMG
            print("🔏 Signing DMG...")
            let dmgSignProcess = Process()
            dmgSignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            dmgSignProcess.arguments = ["-s", "-", dmgPath]
            try dmgSignProcess.run()
            dmgSignProcess.waitUntilExit()
            
            print("✅ DMG created at: \(dmgPath)")
            return
        }
        
        // 找到挂载点
        let mountPoint = "/Volumes/\(appName)"
        
        // 等待挂载完成
        Thread.sleep(forTimeInterval: 1.0)
        
        // 复制文件到 DMG
        print("📁 Copying files to DMG...")
        let cpProcess = Process()
        cpProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
        cpProcess.arguments = ["-R", "\(tempDmgDir)/\(appName).app", "\(mountPoint)/"]
        try cpProcess.run()
        cpProcess.waitUntilExit()
        
        // 创建 Applications 符号链接
        let linkProcess = Process()
        linkProcess.executableURL = URL(fileURLWithPath: "/bin/ln")
        linkProcess.arguments = ["-s", "/Applications", "\(mountPoint)/Applications"]
        try linkProcess.run()
        linkProcess.waitUntilExit()
        
        // 卸载 DMG
        print("📤 Detaching DMG...")
        let detachProcess = Process()
        detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detachProcess.arguments = ["detach", mountPoint]
        try detachProcess.run()
        detachProcess.waitUntilExit()
        
        // 转换为压缩格式
        print("📦 Converting to compressed format...")
        let convertProcess = Process()
        convertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        convertProcess.arguments = [
            "convert", tempDmgPath,
            "-format", "UDZO",
            "-imagekey", "zlib-level=9",
            "-o", dmgPath
        ]
        try convertProcess.run()
        convertProcess.waitUntilExit()
        
        // 删除临时 DMG
        try? fileManager.removeItem(atPath: tempDmgPath)
        
        // 5. Ad-Hoc 签名 DMG
        print("🔏 Signing DMG...")
        let dmgSignProcess = Process()
        dmgSignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        dmgSignProcess.arguments = ["-s", "-", dmgPath]
        try dmgSignProcess.run()
        dmgSignProcess.waitUntilExit()
        
        // 清理临时目录
        try fileManager.removeItem(atPath: tempDmgDir)
        
        print("✅ DMG created at: \(dmgPath)")
    }
}
