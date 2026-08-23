import AppKit

/// 菜单栏折叠/展开控制器
///
/// 通过在菜单栏中放置一个可膨胀的 separator 状态项实现图标隐藏：
/// 折叠时将 separator 宽度膨胀至屏幕宽度的两倍，将左侧图标推出可视区域。
/// 精简自 Hidden Bar (https://github.com/dwarvesf/hidden) 的 StatusBarController。
@MainActor
final class HiddenBarController {

    // MARK: - Status Items

    private lazy var btnExpandCollapse: NSStatusItem = {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }()
    private lazy var btnSeparate: NSStatusItem = {
        NSStatusBar.system.statusItem(withLength: 1)
    }()
    private var btnAlwaysHidden: NSStatusItem?

    // MARK: - Lengths

    private let btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000

    private var btnAlwaysHiddenLength: CGFloat {
        HiddenBarPreferences.alwaysHiddenSectionEnabled ? 20 : 0
    }
    private var btnAlwaysHiddenCollapseLength: CGFloat {
        HiddenBarPreferences.alwaysHiddenSectionEnabled ? btnHiddenCollapseLength : 0
    }

    // MARK: - State

    private var isCollapsed: Bool {
        btnSeparate.length > btnHiddenLength
    }

    private var isToggle = false
    private var timer: Timer?

    /// chevron 右键时回调 AppDelegate 弹出主右键菜单
    var onContextMenu: (() -> Void)?

    // MARK: - Init

    init() {
        updateCollapsedLengths()
        setupUI()
        restoreRemovedStatusItems()
        setupAlwaysHiddenIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if HiddenBarPreferences.areSeparatorsHidden { hideSeparators() }
        autoCollapseIfNeeded()
        
        // 延迟强制重新布局，确保状态项位置正确
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.forceRelayout()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    // MARK: - Setup

    private func setupUI() {
        // ⚠️ lazy 属性的访问顺序决定菜单栏位置（先创建的在右侧）
        // 必须先访问 btnExpandCollapse，使 chevron 在 separator 右侧
        if let button = btnExpandCollapse.button {
            button.image = Self.collapseImage
            button.target = self
            button.action = #selector(buttonPressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        btnSeparate.button?.image = Self.separatorLineImage
        // 设置 menu 使 separator 可交互（与原版 Hidden Bar 一致）
        let separateMenu = NSMenu()
        let separateMenuItem = NSMenuItem(
            title: "隐藏栏设置…",
            action: #selector(openSettingsHint),
            keyEquivalent: ""
        )
        separateMenuItem.target = self
        separateMenu.addItem(separateMenuItem)
        btnSeparate.menu = separateMenu

        btnSeparate.autosaveName = "hora_hiddenBar_separate"
        btnExpandCollapse.autosaveName = "hora_hiddenBar_expandCollapse"
    }

    @objc private func openSettingsHint() {
        showUsageHint()
    }

    private func restoreRemovedStatusItems() {
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
    }
    
    /// 切换 isVisible 强制 macOS 重新布局状态栏项
    private func forceRelayout() {
        btnExpandCollapse.isVisible = false
        btnSeparate.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.btnExpandCollapse.isVisible = true
            self.btnSeparate.isVisible = true
        }
    }

    // MARK: - Collapse / Expand

    func expandCollapseIfNeeded() {
        guard !isToggle else { return }
        isToggle = true
        isCollapsed ? expandMenubar() : collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }

    private func collapseMenuBar() {
        guard isBtnSeparateValidPosition, !isCollapsed else {
            autoCollapseIfNeeded()
            return
        }
        btnSeparate.length = btnHiddenCollapseLength
        btnExpandCollapse.button?.image = Self.expandImage
    }

    private func expandMenubar() {
        guard isCollapsed else { return }
        btnSeparate.length = btnHiddenLength
        btnExpandCollapse.button?.image = Self.collapseImage
        autoCollapseIfNeeded()
    }

    // MARK: - Auto Collapse

    private func autoCollapseIfNeeded() {
        guard HiddenBarPreferences.isAutoHide, !isCollapsed else { return }
        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: HiddenBarPreferences.autoHideSeconds, repeats: false) { [weak self] _ in
            guard let self, HiddenBarPreferences.isAutoHide else { return }
            if self.isMouseInMenuBar {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar()
            }
        }
    }

    // MARK: - Separators

    func showHideSeparatorsAndAlwaysHideArea() {
        if HiddenBarPreferences.areSeparatorsHidden {
            showSeparators()
        } else {
            hideSeparators()
        }
        if isCollapsed { expandMenubar() }
    }

    private func showSeparators() {
        HiddenBarPreferences.areSeparatorsHidden = false
        if !isCollapsed { btnSeparate.length = btnHiddenLength }
        btnAlwaysHidden?.length = btnAlwaysHiddenLength
    }

    private func hideSeparators() {
        guard isBtnAlwaysHiddenValidPosition else { return }
        HiddenBarPreferences.areSeparatorsHidden = true
        if !isCollapsed { btnSeparate.length = btnHiddenLength }
        btnAlwaysHidden?.length = btnAlwaysHiddenCollapseLength
    }

    // MARK: - Always Hidden Section

    private func setupAlwaysHiddenIfNeeded() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleAlwaysHiddenStatusBar),
            name: .hiddenBarPrefsChanged,
            object: nil
        )
        toggleAlwaysHiddenStatusBar()
    }

    @objc private func toggleAlwaysHiddenStatusBar() {
        updateCollapsedLengths()
        if HiddenBarPreferences.alwaysHiddenSectionEnabled {
            if let existing = btnAlwaysHidden { NSStatusBar.system.removeStatusItem(existing) }
            let item = NSStatusBar.system.statusItem(withLength: btnAlwaysHiddenLength)
            item.button?.image = Self.separatorLineImage
            item.button?.appearsDisabled = true
            item.autosaveName = "hora_hiddenBar_alwaysHidden"
            item.isVisible = true
            btnAlwaysHidden = item
        } else {
            if let existing = btnAlwaysHidden { NSStatusBar.system.removeStatusItem(existing) }
            btnAlwaysHidden = nil
        }
    }

    // MARK: - Screen Changes

    @objc private func handleScreenParametersChanged() {
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        if wasCollapsed {
            btnSeparate.length = btnHiddenCollapseLength
            if HiddenBarPreferences.areSeparatorsHidden {
                btnAlwaysHidden?.length = btnAlwaysHiddenCollapseLength
            }
        }
    }

    private func updateCollapsedLengths() {
        let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        btnHiddenCollapseLength = max(500, min(screenWidth * 2, 10_000))
    }

    // MARK: - Position Validation

    private var isBtnSeparateValidPosition: Bool {
        guard let expandX = btnExpandCollapse.button?.window?.frame.origin.x,
              let separateX = btnSeparate.button?.window?.frame.origin.x else { return false }
        return expandX >= separateX
    }

    private var isBtnAlwaysHiddenValidPosition: Bool {
        guard HiddenBarPreferences.alwaysHiddenSectionEnabled else { return true }
        guard let separateX = btnSeparate.button?.window?.frame.origin.x,
              let alwaysX = btnAlwaysHidden?.button?.window?.frame.origin.x else { return false }
        return separateX >= alwaysX
    }

    // MARK: - Mouse in Menu Bar

    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // MARK: - Button Handler

    @objc private func buttonPressed(sender: NSStatusBarButton) {
        // currentEvent 为 nil（AX 点击等场景）时默认执行折叠/展开
        guard let event = NSApp.currentEvent else {
            expandCollapseIfNeeded()
            return
        }
        let isOption = event.modifierFlags.contains(.option)

        if event.type == .leftMouseUp && !isOption {
            expandCollapseIfNeeded()
        } else if event.type == .rightMouseUp && !isOption {
            onContextMenu?()
        } else {
            showHideSeparatorsAndAlwaysHideArea()
        }
    }

    // MARK: - Context Menu

    /// 构建"隐藏栏"子菜单，供 AppDelegate 右键菜单调用
    func buildSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 折叠/展开
        let toggleItem = NSMenuItem(
            title: isCollapsed ? "展开菜单栏" : "折叠菜单栏",
            action: #selector(menuToggleCollapse),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        // 使用说明
        let hintItem = NSMenuItem(
            title: "使用说明…",
            action: #selector(showUsageHint),
            keyEquivalent: ""
        )
        hintItem.target = self
        menu.addItem(hintItem)

        menu.addItem(.separator())

        // 自动折叠
        let autoHideItem = NSMenuItem(
            title: "自动折叠",
            action: #selector(menuToggleAutoHide),
            keyEquivalent: ""
        )
        autoHideItem.target = self
        autoHideItem.state = HiddenBarPreferences.isAutoHide ? .on : .off
        menu.addItem(autoHideItem)

        // 自动折叠延迟子菜单
        let delaySubmenu = NSMenu()
        let delayItem = NSMenuItem(
            title: "自动折叠延迟",
            action: nil,
            keyEquivalent: ""
        )
        delayItem.submenu = delaySubmenu
        menu.addItem(delayItem)

        for seconds in [5.0, 10.0, 15.0, 30.0, 60.0] {
            let item = NSMenuItem(
                title: "\(Int(seconds)) 秒",
                action: #selector(menuSetAutoHideDelay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = abs(HiddenBarPreferences.autoHideSeconds - seconds) < 0.1 ? .on : .off
            item.representedObject = seconds
            delaySubmenu.addItem(item)
        }

        menu.addItem(.separator())

        // 始终隐藏区域
        let alwaysHiddenItem = NSMenuItem(
            title: "始终隐藏区域",
            action: #selector(menuToggleAlwaysHidden),
            keyEquivalent: ""
        )
        alwaysHiddenItem.target = self
        alwaysHiddenItem.state = HiddenBarPreferences.alwaysHiddenSectionEnabled ? .on : .off
        menu.addItem(alwaysHiddenItem)

        // 隐藏分隔线
        let separatorsItem = NSMenuItem(
            title: "隐藏分隔线",
            action: #selector(menuToggleSeparatorsHidden),
            keyEquivalent: ""
        )
        separatorsItem.target = self
        separatorsItem.state = HiddenBarPreferences.areSeparatorsHidden ? .on : .off
        menu.addItem(separatorsItem)

        return menu
    }

    // MARK: - Menu Actions

    /// 显示使用说明弹窗（解释如何通过 Cmd+拖拽设置哪些图标隐藏/显示）
    @objc private func showUsageHint() {
        let alert = NSAlert()
        alert.messageText = "隐藏栏使用说明"
        alert.informativeText = """
        菜单栏中会出现一个竖线分隔符和一个折叠按钮：

        • 折叠按钮（〈）：点击展开/折叠左侧图标
        • 竖线分隔符（|）：隐藏区域的分界线

        设置哪些图标隐藏：

        按住 Command 键，拖动菜单栏图标：
        • 拖到竖线分隔符左侧 → 折叠时隐藏
        • 拖到竖线分隔符右侧 → 始终显示

        隐藏的分界原理：折叠时，分隔符左侧的图标会被推到屏幕外；展开时恢复显示。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func menuToggleCollapse() {
        expandCollapseIfNeeded()
    }

    @objc private func menuToggleAutoHide() {
        HiddenBarPreferences.isAutoHide.toggle()
    }

    @objc private func menuSetAutoHideDelay(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double {
            HiddenBarPreferences.autoHideSeconds = seconds
        }
    }

    @objc private func menuToggleAlwaysHidden() {
        HiddenBarPreferences.alwaysHiddenSectionEnabled.toggle()
    }

    @objc private func menuToggleSeparatorsHidden() {
        showHideSeparatorsAndAlwaysHideArea()
    }

    // MARK: - Icons

    private static var collapseImage: NSImage? {
        let img = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "折叠")
        img?.isTemplate = true
        return img
    }

    private static var expandImage: NSImage? {
        let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "展开")
        img?.isTemplate = true
        return img
    }

    /// 1px 宽竖线，用作菜单栏分隔符图标
    private static var separatorLineImage: NSImage {
        let size = NSSize(width: 1, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.separatorColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
