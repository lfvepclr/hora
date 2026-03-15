import Cocoa
import SwiftUI

// 通知名称：调整 popover 位置
extension Notification.Name {
    static let adjustPopoverPosition = Notification.Name("adjustPopoverPosition")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MyTime"
        item.behavior = .terminationOnRemoval
        return item
    }()
    
    private weak var presentedPopover: NSPopover?
    private var dateRefreshTimer: Timer?
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置菜单栏图标
        updateMenuBarIcon()
        statusItem.isVisible = true
        
        // 设置点击事件
        setupClickHandler()
        
        // 每分钟更新一次图标（日期变化时）
        dateRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarIcon()
            }
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
        
        // 监听全局点击（点击外部关闭）
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let popover = self.presentedPopover, popover.isShown else { return }
                popover.close()
            }
        }
    }
    
    // MARK: - Popover
    
    @MainActor
    private func togglePopover() {
        if let popover = presentedPopover, popover.isShown {
            popover.close()
        } else {
            openPopover()
        }
    }
    
    @MainActor
    private func openPopover() {
        guard let button = statusItem.button else { return }
        
        let popover = NSPopover()
        popover.behavior = .semitransient  // 允许立即响应点击，点击外部关闭
        popover.contentSize = NSSize(width: 320, height: 400)
        
        // 使用 SwiftUI 视图
        let contentView = CalendarPopoverView()
        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
        popover.delegate = self
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        presentedPopover = popover
        
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
        Task { @MainActor in
            updateMenuBarIcon()
        }
    }
    
    // 处理调整 popover 位置的通知
    @objc private func handleAdjustPopoverPosition(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let totalWidth = userInfo["totalWidth"] as? CGFloat else { return }
        
        Task { @MainActor in
            adjustPopoverPosition(totalWidth: totalWidth)
        }
    }
    
    // 调整 popover 位置，确保完全显示在屏幕内
    @MainActor
    private func adjustPopoverPosition(totalWidth: CGFloat) {
        guard let popover = presentedPopover,
              let popoverWindow = popover.contentViewController?.view.window,
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = popoverWindow.frame
        
        // 计算新的右边缘位置
        let newRightEdge = windowFrame.origin.x + totalWidth
        let screenRightEdge = screenFrame.origin.x + screenFrame.width
        
        // 如果超出屏幕右边界，计算需要左移的距离
        if newRightEdge > screenRightEdge {
            let overflow = newRightEdge - screenRightEdge
            let newOrigin = CGPoint(
                x: windowFrame.origin.x - overflow - 10,  // 左移超出距离 + 10px 边距
                y: windowFrame.origin.y
            )
            popoverWindow.setFrameOrigin(newOrigin)
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
        presentedPopover = nil
    }
}
