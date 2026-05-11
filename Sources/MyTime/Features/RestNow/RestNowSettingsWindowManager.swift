import SwiftUI
import Cocoa

/// 定时休息配置面板窗口生命周期管理（单例）
@MainActor
final class RestNowSettingsWindowManager {
    static let shared = RestNowSettingsWindowManager()
    private var window: NSWindow?

    func show() {
        // 复用已存在的窗口
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = RestNowSettingsView(onDismiss: { [weak self] in
            self?.dismiss()
        })
        let hostingController = NSHostingController(rootView: view)

        let w = NSWindow(contentViewController: hostingController)
        w.title = "定时休息设置"
        w.styleMask = [.titled, .closable]
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w

        // 监听窗口关闭，清理引用
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.window?.contentView = nil
                self?.window = nil
            }
        }
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
