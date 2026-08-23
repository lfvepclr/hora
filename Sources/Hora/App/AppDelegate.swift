import Cocoa
import SwiftUI
import Combine

// 通知名称：调整 popover 位置和大小
extension Notification.Name {
    static let adjustPopoverSize = Notification.Name("adjustPopoverSize")
    static let resetPopoverContent = Notification.Name("resetPopoverContent")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    // SPM 资源 bundle 名称
    private static let resourceBundleName = "Hora_Hora"
    
    /// 确保 SPM 资源 bundle 在 Bundle.module 可访问的路径上
    /// SPM 生成的 resource_bundle_accessor 只搜索两个位置:
    ///   1. Bundle.main.bundleURL 根目录（如 Hora.app/Hora_Hora.bundle）
    ///   2. 构建时硬编码的路径
    /// 但 macOS .app bundle 的资源应在 Contents/Resources/ 中，
    /// 导致部署后 Bundle.module 首次访问时 fatalError
    @MainActor
    private static func ensureResourceBundleAccessible() {
        let bundleName = resourceBundleName + ".bundle"
        let appBundleURL = Bundle.main.bundleURL
        let expectedPath = appBundleURL.appendingPathComponent(bundleName)

        // 如果 Bundle.module 期望的位置已经存在 bundle，无需修复
        if FileManager.default.fileExists(atPath: expectedPath.path) {
            return
        }

        // 检查 Contents/Resources/ 中是否存在资源 bundle
        let resourceDir = appBundleURL.appendingPathComponent("Contents/Resources")
        let resourceBundlePath = resourceDir.appendingPathComponent(bundleName)

        if FileManager.default.fileExists(atPath: resourceBundlePath.path) {
            // 创建符号链接: Hora.app/Hora_Hora.bundle → Contents/Resources/Hora_Hora.bundle
            do {
                // 如果目标位置是文件而非目录，先删除
                if FileManager.default.fileExists(atPath: expectedPath.path) {
                    try FileManager.default.removeItem(at: expectedPath)
                }
                try FileManager.default.createSymbolicLink(
                    atPath: expectedPath.path,
                    withDestinationPath: "Contents/Resources/" + bundleName
                )
                // 记录到 stderr（此时 CrashLogService 尚未初始化）
                fputs("[Hora] Created symlink for resource bundle: \(expectedPath.path) -> Contents/Resources/\(bundleName)\n", stderr)
            } catch {
                fputs("[Hora] Failed to create symlink for resource bundle: \(error)\n", stderr)
                // 符号链接失败时，尝试直接复制
                do {
                    try FileManager.default.copyItem(atPath: resourceBundlePath.path, toPath: expectedPath.path)
                    fputs("[Hora] Copied resource bundle to expected location\n", stderr)
                } catch {
                    fputs("[Hora] Failed to copy resource bundle: \(error)\n", stderr)
                }
            }
        } else {
            // Contents/Resources/ 中也不存在 bundle，无法修复
            fputs("[Hora] WARNING: Resource bundle \(bundleName) not found in Contents/Resources/\n", stderr)
            // 尝试在可执行文件旁边搜索
            if let execURL = Bundle.main.executableURL {
                let execDir = execURL.deletingLastPathComponent()
                let execDirBundle = execDir.appendingPathComponent(bundleName)
                if FileManager.default.fileExists(atPath: execDirBundle.path) {
                    do {
                        try FileManager.default.createSymbolicLink(
                            atPath: expectedPath.path,
                            withDestinationPath: execDir.appendingPathComponent(bundleName).path
                        )
                        fputs("[Hora] Created symlink from executable dir bundle\n", stderr)
                    } catch {
                        fputs("[Hora] Failed to create symlink: \(error)\n", stderr)
                    }
                }
            }
        }
    }
    
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Hora"
        item.behavior = .terminationOnRemoval
        return item
    }()
    
    private var dateRefreshTimer: Timer?
    private var restNowCancellables = Set<AnyCancellable>()
    private var hiddenBarController: HiddenBarController?
    
    // 懒初始化 popover（复用，避免每次重新创建）
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .semitransient
        p.contentSize = NSSize(width: 500, height: 380)
        let contentView = CalendarPopoverView()
        p.contentViewController = NSHostingController(rootView: contentView)
        p.delegate = self
        return p
    }()
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⚠️ 第一步：修复 SPM 资源 bundle 路径（必须在访问 Bundle.module 之前！）
        // SPM 的 resource_bundle_accessor 只搜索 Bundle.main.bundleURL 根目录和构建目录，
        // 不会搜索 Contents/Resources/，导致部署后 Bundle.module 访问时 fatalError
        Self.ensureResourceBundleAccessible()
        
        let logger = CrashLogService.shared
        
        // 第二步：初始化崩溃日志系统
        logger.setup()
        logger.log("=== Hora starting ===")
        logger.log("Version: \(AppInfo.version) (\(AppInfo.build))")
        logger.log("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        logger.log("Bundle: \(Bundle.main.bundlePath)")
        logger.log("Module Bundle: \(Bundle.module.bundlePath)")
        
        // 设置为附件应用，不在 Dock 中显示图标
        NSApp.setActivationPolicy(.accessory)
        logger.log("Activation policy set to accessory")
        
        // 设置菜单栏图标
        updateMenuBarIcon()
        statusItem.isVisible = true
        logger.log("Menu bar icon set successfully")
        
        // 设置点击事件
        setupClickHandler()
        logger.log("Click handler set up")
        
        // 启动菜单栏折叠功能
        hiddenBarController = HiddenBarController()
        hiddenBarController?.onContextMenu = { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.showContextMenu()
        }
        HiddenBarPreferences.syncAutoStart(HiddenBarPreferences.isAutoStart)
        logger.log("Hidden Bar controller set up")
        
        // 每分钟更新一次图标（日期变化时）
        dateRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                self.updateMenuBarIcon()
            }
        }
        
        // 后台预加载世界地图数据（约1MB内存，换取秒开体验）
        logger.log("Starting WorldMapDataService preload")
        Task.detached(priority: .userInitiated) {
            await WorldMapDataService.shared.ensureLoaded()
            await MainActor.run {
                logger.log("WorldMapDataService preload completed")
            }
        }
        
        // 后台预热当月日历数据（农历+节假日），确保首次打开0延迟
        logger.log("Starting calendar data prewarm")
        Task { @MainActor in
            LunarCalendarService.shared.preWarmCurrentMonth()
            logger.log("LunarCalendarService prewarm completed")
            HolidayService.shared.preWarmCurrentMonth()
            logger.log("HolidayService prewarm completed")
        }
        
        // 启动 RestNow 订阅
        setupRestNowSubscription()
        logger.log("RestNow subscription set up")
        
        // 监听日期变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarDayDidChange),
            name: .NSCalendarDayChanged,
            object: nil
        )
        
        // 监听调整 popover 大小的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAdjustPopoverSize),
            name: .adjustPopoverSize,
            object: nil
        )
        
        // 首次启动显示引导
        if OnboardingWindowManager.shared.shouldShowOnboarding {
            // 延迟0.5秒显示，确保菜单栏已初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowManager.shared.showIfNeeded()
            }
            logger.log("Onboarding will be shown")
        }
        
        logger.log("=== Hora startup completed ===")
    }
    
    // MARK: - Menu Bar Icon
    
    @MainActor
    func updateMenuBarIcon() {
        let calendar = Calendar.current
        let date = Date()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        // 设置标题为 "03月14日" 格式
        statusItem.button?.title = String(format: "%02d月%02d日", month, day)
        statusItem.button?.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        
        // 更新 Tooltip
        updateTooltip()
    }
    
    private func createDateIcon(day: Int) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // 绘制背景
        let rect = NSRect(origin: .zero, size: size)
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        
        // 绘制边框
        NSColor.separatorColor.setStroke()
        let borderRect = NSRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)
        let path = NSBezierPath(roundedRect: borderRect, xRadius: 3, yRadius: 3)
        path.stroke()
        
        // 绘制日期数字
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlTextColor
        ]
        let string = String(day)
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let stringSize = attributedString.size()
        let point = NSPoint(
            x: (size.width - stringSize.width) / 2,
            y: (size.height - stringSize.height) / 2
        )
        attributedString.draw(at: point)
        
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
    
    @MainActor
    private func updateTooltip() {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        
        let lunarInfo = LunarCalendarService.shared.getLunarInfo(for: Date())
        let lunarDate = lunarInfo.displayLunarDate
        
        statusItem.button?.toolTip = """
        \(formatter.string(from: Date()))
        \(lunarDate)
        """
    }
    
    // MARK: - Click Handler
    
    @MainActor
    private func setupClickHandler() {
        // 使用 NSEvent 监听点击，而不是 target-action
        // 这样可以保持按钮高亮状态与 popover 同步
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            
            // 检查点击是否在状态栏按钮上
            if event.window == self.statusItem.button?.window {
                // 如果按住 Command 键，让系统处理拖拽（不拦截事件）
                if event.modifierFlags.contains(.command) {
                    return event
                }
                Task { @MainActor in
                    self.togglePopover()
                }
                return nil
            }
            
            return event
        }
        
        // 监听右键点击，显示菜单
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self else { return event }
            
            // 检查点击是否在状态栏按钮上
            if event.window == self.statusItem.button?.window {
                self.showContextMenu()
                return nil
            }
            
            return event
        }
        
        // 监听全局点击（点击外部关闭）
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.popover.isShown else { return }
                self.popover.close()
            }
        }
    }
    
    // MARK: - RestNow Subscription
    
    @MainActor
    private func setupRestNowSubscription() {
        let session = RestNowSession.shared
        Publishers.CombineLatest3(session.$isEnabled, session.$remainingSeconds, session.$phase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled, _, phase in
                guard let self = self else { return }
                if isEnabled {
                    let progress = session.progress
                    self.statusItem.button?.image = self.createProgressRingImage(progress: progress, phase: phase)
                    self.statusItem.button?.imagePosition = .imageLeading
                } else {
                    self.statusItem.button?.image = nil
                }
            }
            .store(in: &restNowCancellables)
    }
    
    // MARK: - Progress Ring Image
    
    @MainActor
    private func createProgressRingImage(progress: Double, phase: RestNowSession.Phase) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let colorSettings = RestNowColorSettings.shared
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.0
            let lineWidth: CGFloat = 2.0
            
            // 根据阶段选择颜色
            let progressColor: NSColor = (phase == .work) ? colorSettings.workColor : colorSettings.restColor
            
            // 底圈（浅灰色，使用进度色 opacity 0.3）
            let bgPath = NSBezierPath()
            bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            bgPath.lineWidth = lineWidth
            progressColor.withAlphaComponent(0.3).setStroke()
            bgPath.stroke()
            
            // 彩色进度弧线（从12点钟方向顺时针）
            let startAngle: CGFloat = 90 // 12点钟方向
            let endAngle: CGFloat = 90 - CGFloat(progress) * 360
            let progressPath = NSBezierPath()
            progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            progressPath.lineWidth = lineWidth
            progressPath.lineCapStyle = .round
            progressColor.setStroke()
            progressPath.stroke()
            
            // 休息阶段：中心绘制咖啡图标
            if phase == .rest {
                if let symbolImage = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) {
                    let iconSize: CGFloat = 7.0
                    let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
                    let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                    let iconRect = NSRect(
                        x: center.x - iconSize / 2,
                        y: center.y - iconSize / 2,
                        width: iconSize,
                        height: iconSize
                    )
                    progressColor.set()
                    configured.draw(in: iconRect)
                }
            }
            
            return true
        }
        image.isTemplate = false
        return image
    }
    
    // MARK: - Context Menu
    
    @MainActor
    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        
        let menu = NSMenu()
        
        // 开机启动
        let autoStartItem = NSMenuItem(
            title: "开机启动",
            action: #selector(toggleAutoStart),
            keyEquivalent: ""
        )
        autoStartItem.target = self
        autoStartItem.state = HiddenBarPreferences.isAutoStart ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(.separator())
        
        // 隐藏栏
        if let hiddenBarSubmenu = hiddenBarController?.buildSubmenu() {
            let hiddenBarItem = NSMenuItem(
                title: "隐藏栏",
                action: nil,
                keyEquivalent: ""
            )
            hiddenBarItem.submenu = hiddenBarSubmenu
            menu.addItem(hiddenBarItem)
        }
        
        menu.addItem(.separator())
        
        // 定时休息
        let restNowItem = NSMenuItem(
            title: "定时休息",
            action: #selector(showRestNowSettings),
            keyEquivalent: ""
        )
        restNowItem.target = self
        restNowItem.isEnabled = true
        menu.addItem(restNowItem)
        
        menu.addItem(.separator())
        
        // 关于
        let aboutItem = NSMenuItem(
            title: "关于 \(AppInfo.name)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(.separator())
        
        // 退出
        let quitItem = NSMenuItem(
            title: "退出 \(AppInfo.name)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        // 显示菜单（使用 popUpContextMenu 让系统自动处理定位）
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            // 无当前事件时（极端情况），直接在按钮下方显示
            NSMenu.popUpContextMenu(menu, with: NSEvent(), for: button)
        }
    }
    

    
    @objc private func showRestNowSettings() {
        RestNowSettingsWindowManager.shared.show()
    }
    
    @objc private func toggleAutoStart() {
        HiddenBarPreferences.isAutoStart.toggle()
    }
    
    @objc private func showAbout() {
        let iconImage: NSImage? = {
            if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
                return NSImage(contentsOfFile: path)
            }
            return NSApplication.shared.applicationIconImage
        }()

        let aboutView = AboutView(
            appName: AppInfo.name,
            version: AppInfo.version,
            build: AppInfo.build,
            iconImage: iconImage,
            license: "MIT License",
            githubURL: AppInfo.githubURL
        )

        let hostingController = NSHostingController(rootView: aboutView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "关于 \(AppInfo.name)"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

struct AboutView: View {
    let appName: String
    let version: String
    let build: String
    let iconImage: NSImage?
    let license: String
    let githubURL: String

    var body: some View {
        VStack(spacing: 16) {
            if let icon = iconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 128, height: 128)
            }

            Text(appName)
                .font(.title.bold())

            Text("Version \(version) (\(build))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(license)
                .font(.caption)
                .foregroundColor(.secondary)

            if let url = URL(string: githubURL) {
                Link(githubURL, destination: url)
                    .font(.footnote)
            }
        }
        .padding(40)
        .frame(width: 300, height: 320)
    }
}
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Popover
    
    @MainActor
    private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else {
            showPopover()
        }
    }
    
    @MainActor
    private func showPopover() {
        guard let button = statusItem.button else { return }
    
        // 重置到日历视图
        popover.contentSize = NSSize(width: 500, height: 380)
        NotificationCenter.default.post(name: .resetPopoverContent, object: nil)
    
        // 显示 popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    
        // 激活应用并让 popover 获取焦点
        NSApp.activate(ignoringOtherApps: true)
    
        // 让 popover 内容视图成为第一响应者，确保立即响应点击
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    
        // 保持按钮高亮
        button.highlight(true)
    
        // 清除 tooltip 防止重叠
        button.toolTip = nil
    }
    
    // MARK: - Notifications
    
    @objc private func calendarDayDidChange() {
        Task { @MainActor [weak self] in
            self?.updateMenuBarIcon()
        }
    }
    
    // 处理调整 popover 大小的通知
    @objc private func handleAdjustPopoverSize(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let width = userInfo["width"] as? CGFloat else { return }
    
        Task { @MainActor [weak self] in
            self?.adjustPopoverSize(width: width)
        }
    }
    
    // 调整 popover 大小，并在窗口溢出屏幕右侧时左移避让
    @MainActor
    private func adjustPopoverSize(width: CGFloat) {
        guard popover.isShown else { return }
        popover.contentSize = NSSize(width: width, height: 380)
        // 等待 NSPopover 按新尺寸重新布局后，再左移避溢出
        DispatchQueue.main.async { [weak self] in
            self?.shiftPopoverLeftIfNeeded()
        }
    }
    
    /// 窗口右边缘超出屏幕可视区域时，整体左移以补足缺口
    @MainActor
    private func shiftPopoverLeftIfNeeded() {
        guard popover.isShown,
              let window = popover.contentViewController?.view.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        let overflow = frame.maxX - visible.maxX
        if overflow > 0 {
            var origin = frame.origin
            origin.x = max(visible.minX, origin.x - overflow)
            window.setFrameOrigin(origin)
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        // 取消按钮高亮
        statusItem.button?.highlight(false)
        
        // 恢复 tooltip
        updateTooltip()
    }
    
    func popoverDidClose(_ notification: Notification) {
        // 不再清空缓存：保持缓存温热确保下次秒开
        // 缓存自身的 maxCacheSize 限制已提供内存保护
    }
}
