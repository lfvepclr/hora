import Cocoa
import SwiftUI

// 通知名称：调整 popover 位置和大小
extension Notification.Name {
    static let adjustPopoverPosition = Notification.Name("adjustPopoverPosition")
    static let adjustPopoverSize = Notification.Name("adjustPopoverSize")
    static let resetPopoverContent = Notification.Name("resetPopoverContent")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MyTime"
        item.behavior = .terminationOnRemoval
        return item
    }()
    
    private var dateRefreshTimer: Timer?
    
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
        // 设置为附件应用，不在 Dock 中显示图标
        NSApp.setActivationPolicy(.accessory)
        
        // 设置菜单栏图标
        updateMenuBarIcon()
        statusItem.isVisible = true
        
        // 设置点击事件
        setupClickHandler()
        
        // 每分钟更新一次图标（日期变化时）
        dateRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                self.updateMenuBarIcon()
            }
        }
        
        // 后台预加载世界地图数据（约1MB内存，换取秒开体验）
        Task.detached(priority: .userInitiated) {
            await WorldMapDataService.shared.ensureLoaded()
        }
        
        // 监听日期变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarDayDidChange),
            name: .NSCalendarDayChanged,
            object: nil
        )
        
        // 监听调整 popover 位置的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAdjustPopoverPosition),
            name: .adjustPopoverPosition,
            object: nil
        )
        
        // 监听调整 popover 大小的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAdjustPopoverSize),
            name: .adjustPopoverSize,
            object: nil
        )
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
                Task { @MainActor in
                    self.showContextMenu()
                }
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
    
    // MARK: - Context Menu
    
    @MainActor
    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        
        let menu = NSMenu()
        
        // 退出菜单项
        let quitItem = NSMenuItem(
            title: NSLocalizedString("Quit MyTime", comment: "Quit menu item"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        // 显示菜单
        let location = NSPoint(x: 0, y: button.bounds.height + 5)
        menu.popUp(positioning: nil, at: location, in: button)
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
    
        // 计算初始窗口位置，确保能容纳世界时钟大小（不超出屏幕边界）
        let buttonBounds = button.bounds
        let screen = NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect.zero
        let maxSize = NSSize(width: 780, height: 380)
            
        // 显示 popover
        popover.show(relativeTo: buttonBounds, of: button, preferredEdge: .maxY)
        
        // 立即调整窗口位置，确保能容纳世界时钟大小（不超出屏幕右边界）
        if let popoverWindow = popover.contentViewController?.view.window {
            let windowFrame = popoverWindow.frame
            let rightMargin: CGFloat = 20
            let screenRightEdge = screenFrame.origin.x + screenFrame.width
            let maxWindowRightEdge = windowFrame.origin.x + maxSize.width
                
            // 如果世界时钟大小的窗口右边缘超出屏幕，调整位置
            if maxWindowRightEdge > screenRightEdge - rightMargin {
                let overflow = maxWindowRightEdge - (screenRightEdge - rightMargin)
                let newOrigin = CGPoint(
                    x: windowFrame.origin.x - overflow - 10,
                    y: windowFrame.origin.y
                )
                popoverWindow.setFrameOrigin(newOrigin)
            }
        }
    
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
    
    // 处理调整 popover 位置的通知
    @objc private func handleAdjustPopoverPosition(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let totalWidth = userInfo["totalWidth"] as? CGFloat else { return }
    
        Task { @MainActor [weak self] in
            self?.adjustPopoverPosition(totalWidth: totalWidth)
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
    
    // 调整 popover 位置，确保完全显示在屏幕内
    @MainActor
    private func adjustPopoverPosition(totalWidth: CGFloat) {
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window,
              let screen = NSScreen.main else { return }
    
        let screenFrame = screen.visibleFrame
        let windowFrame = popoverWindow.frame
    
        // 计算新的右边缘位置
        let newRightEdge = windowFrame.origin.x + totalWidth
        let screenRightEdge = screenFrame.origin.x + screenFrame.width
    
        // 如果超出屏幕右边界，计算需要左移的距离
        // 确保距离屏幕右边至少 20px
        let rightMargin: CGFloat = 20
        if newRightEdge > screenRightEdge - rightMargin {
            let overflow = newRightEdge - (screenRightEdge - rightMargin)
            let newOrigin = CGPoint(
                x: windowFrame.origin.x - overflow - 10,  // 左移超出距离 + 10px 额外边距
                y: windowFrame.origin.y
            )
            popoverWindow.setFrameOrigin(newOrigin)
        }
    }
    
    // 调整 popover 大小（位置已在打开时预设好）
    @MainActor
    private func adjustPopoverSize(width: CGFloat) {
        guard popover.isShown else { return }
        
        // 直接设置新的大小
        popover.contentSize = NSSize(width: width, height: 380)
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
        DateFormatterCache.clearCache()
        HolidayService.shared.clearCache()
        LunarCalendarService.shared.clearCache()
    }
}
