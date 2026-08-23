import Foundation

// MARK: - Version Constants (keep in sync with AppInfo.swift)
private let appName = "Hora"
private let appVersion = "6.1.0"
private let appBuild = "1"
private let bundleIdentifier = "com.hora.app"
private let minimumSystemVersion = "14.0"

@main
struct DMGBuilder {
    
    // MARK: - Helper: Run shell process
    
    @discardableResult
    static func shell(_ executable: String, arguments: [String], silent: Bool = false) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if silent {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
    
    // MARK: - Icon Generation
    
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
        
        // 使用 qlmanage 预览并转换 SVG
        let qlProcess = Process()
        qlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        qlProcess.arguments = ["-t", "-s", "1024", "-o", iconsetPath, svgPath]
        qlProcess.standardOutput = FileHandle.nullDevice
        qlProcess.standardError = FileHandle.nullDevice
        try qlProcess.run()
        qlProcess.waitUntilExit()
        
        // qlmanage 会生成一个预览文件
        let qlPreviewPath = "\(iconsetPath)/icon.svg.png"
        
        if fileManager.fileExists(atPath: qlPreviewPath) {
            // 使用 sips 生成各种尺寸
            for (iconName, size) in sizes {
                let outputPath = "\(iconsetPath)/icon_\(iconName).png"
                try shell("/usr/bin/sips", arguments: [
                    "-z", String(size), String(size),
                    qlPreviewPath,
                    "--out", outputPath
                ], silent: true)
            }
            
            // 删除临时文件
            try? fileManager.removeItem(atPath: qlPreviewPath)
        } else {
            print("⚠️  Could not generate icon from SVG. Please install icon manually.")
        }
    }
    
    // MARK: - Main Entry Point
    
    static func main() async throws {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        // ============================================================
        // Step 0: Release Build
        // ============================================================
        print("🔨 Building release...")
        let buildStatus = try shell("/usr/bin/swift", arguments: ["build", "-c", "release"])
        guard buildStatus == 0 else {
            print("❌ Release build failed! Aborting.")
            Foundation.exit(1)
        }
        print("✅ Build succeeded.")
        
        let buildPath = "\(currentPath)/.build/release"
        let appBundlePath = "\(buildPath)/\(appName).app"
        
        // ============================================================
        // Step 1: Create .app bundle
        // ============================================================
        print("📦 Creating app bundle...")
        
        if fileManager.fileExists(atPath: appBundlePath) {
            try fileManager.removeItem(atPath: appBundlePath)
        }
        
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
        // SPM 生成的 resource_bundle_accessor 只搜索 Bundle.main.bundleURL 根目录，
        // 不搜索 Contents/Resources/，因此必须在 .app 根目录也放置 bundle（符号链接即可）
        let bundleSource = "\(buildPath)/\(appName)_Hora.bundle"
        if fileManager.fileExists(atPath: bundleSource) {
            // 1. 复制到 Contents/Resources/（符合 macOS 规范）
            try fileManager.copyItem(atPath: bundleSource, toPath: "\(resourcesPath)/\(appName)_Hora.bundle")

            // 2. 在 .app 根目录创建符号链接，指向 Contents/Resources/ 中的 bundle
            //    这样 SPM 的 Bundle.module 访问器能找到资源
            try fileManager.createSymbolicLink(
                atPath: "\(appBundlePath)/\(appName)_Hora.bundle",
                withDestinationPath: "Contents/Resources/\(appName)_Hora.bundle"
            )
            print("✅ Resource bundle placed in Contents/Resources/ with symlink at app root")
        } else {
            print("⚠️  Resource bundle not found at \(bundleSource)")
        }
        
        // ============================================================
        // Step 2: Create app icon (SVG → iconset → icns)
        // ============================================================
        // Step 2: Use pre-built icon or convert from existing iconset
        print("🎨 Creating app icon...")
        let icnsPath = "\(resourcesPath)/AppIcon.icns"

        // 优先使用预生成的 icns 文件
        let prebuiltIcns = "\(currentPath)/Icon.icns"
        if fileManager.fileExists(atPath: prebuiltIcns) {
            try fileManager.copyItem(atPath: prebuiltIcns, toPath: icnsPath)
            print("✅ Copied pre-built icon from Icon.icns")
        } else if fileManager.fileExists(atPath: "\(currentPath)/Icon.iconset") {
            // 使用已有的 iconset 目录直接转换
            let iconsetPath = "\(currentPath)/Icon.iconset"
            try shell("/usr/bin/iconutil", arguments: ["-c", "icns", iconsetPath, "-o", icnsPath], silent: true)
            print("✅ Converted Icon.iconset to AppIcon.icns")
        } else {
            // 回退：从 SVG 生成
            var svgPath = "\(currentPath)/icon_new.svg"
            if !fileManager.fileExists(atPath: svgPath) {
                svgPath = "\(currentPath)/icon.svg"
            }
            let iconsetPath = "\(currentPath)/.build/Hora.iconset"

            if fileManager.fileExists(atPath: svgPath) {
                try createIconSet(from: svgPath, to: iconsetPath, resourcesPath: resourcesPath)
                try shell("/usr/bin/iconutil", arguments: ["-c", "icns", iconsetPath, "-o", icnsPath], silent: true)
                try? fileManager.removeItem(atPath: iconsetPath)
            }
        }


        // ============================================================
        // Step 3: Create Info.plist
        // ============================================================
        let hasIcon = fileManager.fileExists(atPath: "\(currentPath)/Icon.icns")
            || fileManager.fileExists(atPath: "\(currentPath)/Icon.iconset")
            || fileManager.fileExists(atPath: "\(currentPath)/icon_new.svg")
            || fileManager.fileExists(atPath: "\(currentPath)/icon.svg")
        let iconFileName = hasIcon ? "AppIcon" : ""
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
            <string>\(bundleIdentifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(appName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>\(appVersion)</string>
            <key>CFBundleVersion</key>
            <string>\(appBuild)</string>
            <key>LSMinimumSystemVersion</key>
            <string>\(minimumSystemVersion)</string>
            <key>NSHighResolutionCapable</key>
            <true/>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
        </dict>
        </plist>
        """
        
        let infoPlistPath = "\(contentsPath)/Info.plist"
        try infoPlist.write(toFile: infoPlistPath, atomically: true, encoding: .utf8)
        
        // ============================================================
        // Step 4: Ad-Hoc sign .app
        // ============================================================
        print("🔏 Signing app bundle...")
        try shell("/usr/bin/codesign", arguments: [
            "-s", "-", "--deep", "--force", "--options", "runtime", appBundlePath
        ])
        
        // ============================================================
        // Step 5: Prepare DMG staging directory
        // ============================================================
        print("💿 Creating DMG...")
        let distPath = "\(currentPath)/dist"
        let dmgPath = "\(distPath)/\(appName).dmg"
        let rwDmgPath = "\(currentPath)/.build/\(appName)-rw.dmg"
        let stagingDir = "\(currentPath)/.build/dmg-root"
        
        // 确保 dist 目录存在
        if !fileManager.fileExists(atPath: distPath) {
            try fileManager.createDirectory(atPath: distPath, withIntermediateDirectories: true)
        }
        
        // 清理旧文件
        if fileManager.fileExists(atPath: stagingDir) {
            try fileManager.removeItem(atPath: stagingDir)
        }
        if fileManager.fileExists(atPath: rwDmgPath) {
            try fileManager.removeItem(atPath: rwDmgPath)
        }
        if fileManager.fileExists(atPath: dmgPath) {
            try fileManager.removeItem(atPath: dmgPath)
        }
        
        // 创建临时目录，复制 .app + 创建 Applications 符号链接
        try fileManager.createDirectory(atPath: stagingDir, withIntermediateDirectories: true)
        try fileManager.copyItem(atPath: appBundlePath, toPath: "\(stagingDir)/\(appName).app")
        try fileManager.createSymbolicLink(atPath: "\(stagingDir)/Applications", withDestinationPath: "/Applications")
        
        // ============================================================
        // Step 6: Create read-write DMG (UDRW, HFS+)
        // ============================================================
        print("📀 Creating writable DMG image...")
        let createStatus = try shell("/usr/bin/hdiutil", arguments: [
            "create",
            "-volname", appName,
            "-srcfolder", stagingDir,
            "-fs", "HFS+",
            "-format", "UDRW",
            "-ov",
            rwDmgPath
        ], silent: true)
        
        guard createStatus == 0 else {
            print("❌ Failed to create writable DMG!")
            Foundation.exit(1)
        }
        
        // ============================================================
        // Step 7: Mount and configure with AppleScript
        // ============================================================
        print("🎨 Configuring DMG window layout...")
        
        // Mount the DMG
        let mountPoint = "/Volumes/\(appName)"
        
        // Detach if already mounted
        try? shell("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-quiet"], silent: true)
        
        let attachStatus = try shell("/usr/bin/hdiutil", arguments: [
            "attach", rwDmgPath,
            "-mountpoint", mountPoint,
            "-nobrowse", "-noverify"
        ], silent: true)
        
        guard attachStatus == 0 else {
            print("❌ Failed to mount DMG for styling!")
            Foundation.exit(1)
        }
        
        // AppleScript to configure window appearance
        let appleScript = """
        tell application "Finder"
            tell disk "\(appName)"
                open
                delay 1

                set theWindow to container window
                set current view of theWindow to icon view
                delay 0.5

                set toolbar visible of theWindow to false
                set statusbar visible of theWindow to false

                set bounds of theWindow to {200, 200, 800, 600}

                set viewOptions to the icon view options of theWindow
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to 128
                set background color of viewOptions to {65535, 65535, 65535}

                delay 0.5

                set position of item "\(appName).app" of theWindow to {150, 200}
                set position of item "Applications" of theWindow to {450, 200}

                close
                open
                delay 0.5
                update without registering applications
            end tell
        end tell
        """
        
        // Execute AppleScript (graceful degradation if Finder unavailable)
        let osascriptProcess = Process()
        osascriptProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptProcess.arguments = ["-e", appleScript]
        osascriptProcess.standardOutput = FileHandle.nullDevice
        osascriptProcess.standardError = FileHandle.nullDevice
        try osascriptProcess.run()
        osascriptProcess.waitUntilExit()
        
        if osascriptProcess.terminationStatus != 0 {
            print("⚠️  AppleScript window styling failed (CI environment?). Continuing without styling...")
        } else {
            print("✅ DMG window styled successfully.")
        }
        
        // Wait for Finder to sync
        try await Task.sleep(for: .seconds(2.0))
        
        // ============================================================
        // Step 8: Detach DMG
        // ============================================================
        print("📤 Detaching DMG...")
        try shell("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-quiet"], silent: true)
        
        // ============================================================
        // Step 9: Convert to compressed UDZO format (zlib-level=9)
        // ============================================================
        print("📦 Converting to compressed format (UDZO)...")
        let convertStatus = try shell("/usr/bin/hdiutil", arguments: [
            "convert", rwDmgPath,
            "-format", "UDZO",
            "-imagekey", "zlib-level=9",
            "-ov",
            "-o", dmgPath
        ], silent: true)
        
        guard convertStatus == 0 else {
            print("❌ Failed to convert DMG to compressed format!")
            Foundation.exit(1)
        }
        
        // ============================================================
        // Step 10: Ad-Hoc sign final DMG
        // ============================================================
        print("🔏 Signing DMG...")
        try shell("/usr/bin/codesign", arguments: ["-s", "-", dmgPath])
        
        // ============================================================
        // Step 11: Cleanup temporary files
        // ============================================================
        print("🧹 Cleaning up...")
        try? fileManager.removeItem(atPath: rwDmgPath)
        try? fileManager.removeItem(atPath: stagingDir)
        
        print("")
        print("✅ DMG created successfully: dist/\(appName).dmg")
        print("   Version: \(appVersion) (build \(appBuild))")
    }
}
