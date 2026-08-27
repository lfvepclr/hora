import AppKit

/// 菜单栏折叠/展开控制器
///
/// 通过在菜单栏中放置一个可膨胀的 separator 状态项实现图标隐藏：
/// 折叠时将 separator 宽度膨胀至屏幕宽度的两倍，将左侧图标推出可视区域。
/// 精简自 Hidden Bar (https://github.com/dwarvesf/hidden) 的 StatusBarController。
@MainActor
final class HiddenBarController {

    // MARK: - Status Items

    /// ⚠️ 创建顺序决定菜单栏相对位置，必须由 createStatusItems() 统一创建
    /// ⚠️ 运行期永不 removeStatusItem / isVisible 切换显隐：总开关关闭用 length=0 隐藏（保住系统位置槽位）
    private var btnExpandCollapse: NSStatusItem?
    private var btnSeparate: NSStatusItem?
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
        guard let btnSeparate else { return false }
        return Self.isCollapsedState(separatorLength: btnSeparate.length, hiddenLength: btnHiddenLength)
    }

    private var isToggle = false
    /// nonisolated(unsafe)：仅在主线程创建/触发；deinit 兜底失效（实际对象与 app 同生命周期）
    nonisolated(unsafe) private var timer: Timer?
    /// 菜单打开期间为 true，暂停自动折叠（避免用户设置时被折回）
    private var isMenuTracking = false

    /// chevron 右键 / separator 点击时回调 AppDelegate 弹出主右键菜单
    var onContextMenu: (() -> Void)?
    /// 菜单「设置向导…」回调 AppDelegate 打开引导窗口
    var onOpenWizard: (() -> Void)?

    // MARK: - Init

    init() {
        updateCollapsedLengths()
        if HiddenBarPreferences.isEnabled {
            setupUI()
            restoreRemovedStatusItems()
        }
        setupAlwaysHiddenIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if HiddenBarPreferences.areSeparatorsHidden { hideSeparators() }
        autoCollapseIfNeeded()

        // 监听菜单开合，打开期间暂停自动折叠
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )

        guard HiddenBarPreferences.isEnabled else { return }

        // 布局稳定后检测刘海遮挡/离屏（仅记录日志，位移依赖用户 ⌘+拖动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.checkOccludedPositions()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    // MARK: - Setup

    private func setupUI() {
        createStatusItems()
        configureStatusItems()
    }

    /// 创建 chevron 和 separator 状态项
    /// ⚠️ 创建顺序决定菜单栏位置：先创建的在右侧，必须先创建 btnExpandCollapse
    private func createStatusItems() {
        btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
    }

    /// 配置状态项外观与行为（初始配置与位置修复重建后共用）
    private func configureStatusItems() {
        guard let btnExpandCollapse, let btnSeparate else { return }

        if let button = btnExpandCollapse.button {
            button.image = isCollapsed ? Self.expandImage : Self.collapseImage
            button.target = self
            button.action = #selector(buttonPressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        btnSeparate.button?.image = Self.separatorLineImage
        // 点击竖线分隔符（左键/右键）弹出主右键菜单，与 chevron 右键一致
        if let button = btnSeparate.button {
            button.target = self
            button.action = #selector(separatorPressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        btnSeparate.autosaveName = "hora_hiddenBar_separate"
        btnExpandCollapse.autosaveName = "hora_hiddenBar_expandCollapse"

        // 非折叠态展开分隔线为正常宽度，保证可辨、可 Cmd+拖拽
        if !isCollapsed { btnSeparate.length = btnHiddenLength }
    }

    /// 点击竖线分隔符：弹出主右键菜单
    @objc private func separatorPressed(sender: NSStatusBarButton) {
        onContextMenu?()
    }

    private func restoreRemovedStatusItems() {
        btnExpandCollapse?.isVisible = true
        btnSeparate?.isVisible = true
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
        btnSeparate?.length = btnHiddenCollapseLength
        btnExpandCollapse?.button?.image = Self.expandImage
    }

    private func expandMenubar() {
        guard isCollapsed else { return }
        btnSeparate?.length = btnHiddenLength
        btnExpandCollapse?.button?.image = Self.collapseImage
        autoCollapseIfNeeded()
    }

    // MARK: - Auto Collapse

    private func autoCollapseIfNeeded() {
        guard HiddenBarPreferences.isEnabled, HiddenBarPreferences.isAutoHide, !isCollapsed else { return }
        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: HiddenBarPreferences.autoHideSeconds, repeats: false) { [weak self] _ in
            guard let self, HiddenBarPreferences.isEnabled, HiddenBarPreferences.isAutoHide else { return }
            if self.isMenuTracking || self.isMouseInMenuBar {
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
        if !isCollapsed { btnSeparate?.length = btnHiddenLength }
        btnAlwaysHidden?.length = btnAlwaysHiddenLength
    }

    private func hideSeparators() {
        guard isBtnAlwaysHiddenValidPosition else { return }
        HiddenBarPreferences.areSeparatorsHidden = true
        if !isCollapsed { btnSeparate?.length = btnHiddenLength }
        btnAlwaysHidden?.length = btnAlwaysHiddenCollapseLength
    }

    // MARK: - Always Hidden Section

    private func setupAlwaysHiddenIfNeeded() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrefsChanged),
            name: .hiddenBarPrefsChanged,
            object: nil
        )
        toggleAlwaysHiddenStatusBar()
    }

    /// 偏好变更统一入口：先应用总开关显隐，再同步始终隐藏区域
    @objc private func handlePrefsChanged() {
        applyEnabledState()
        toggleAlwaysHiddenStatusBar()
    }

    /// 根据总开关显隐 chevron/separator（幂等）
    /// ⚠️ macOS 26 实证：isVisible/removeStatusItem/setFrame 均无法保留位置——
    /// 菜单栏布局由 ControlCenter 集中管控，隐藏/重建后系统重排到默认位，setFrame 只改 AX frame 不改渲染。
    /// 唯一保留位置槽位的隐藏方式是 length=0（项仍注册在菜单栏，系统保留其位置记忆，仅不渲染）。
    private var savedLengths: (expand: CGFloat, separate: CGFloat)?

    private func applyEnabledState() {
        let enabled = HiddenBarPreferences.isEnabled
        if enabled {
            if btnExpandCollapse == nil {
                // 启动时总开关为关闭、运行中首次开启 → 创建（系统按 autosaveName 恢复保存位置）
                setupUI()
                restoreRemovedStatusItems()
            } else {
                // 运行中重开 → 恢复原宽度。项未被移除，位置槽位由系统保留
                let expandLen = savedLengths?.expand ?? NSStatusItem.variableLength
                let separateLen = savedLengths?.separate ?? btnHiddenLength
                btnExpandCollapse?.length = expandLen
                btnSeparate?.length = separateLen
                btnExpandCollapse?.isVisible = true
                btnSeparate?.isVisible = true
            }
            autoCollapseIfNeeded()
        } else {
            // 关闭前记录当前宽度，供重开时恢复
            if let btnExpandCollapse, let btnSeparate {
                savedLengths = (btnExpandCollapse.length, btnSeparate.length)
            }
            timer?.invalidate()
            // 用 0 宽隐藏而非 isVisible/removeStatusItem：项保持注册，系统保留位置记忆
            btnExpandCollapse?.length = 0
            btnSeparate?.length = 0
        }
    }

    @objc private func toggleAlwaysHiddenStatusBar() {
        updateCollapsedLengths()
        let shouldShow = HiddenBarPreferences.isEnabled && HiddenBarPreferences.alwaysHiddenSectionEnabled
        guard shouldShow else {
            // ⚠️ 用 0 宽隐藏而非 isVisible/removeStatusItem：项保持注册，系统保留位置槽位
            if let item = btnAlwaysHidden { savedAlwaysHiddenLength = item.length }
            btnAlwaysHidden?.length = 0
            return
        }
        if btnAlwaysHidden == nil {
            let item = NSStatusBar.system.statusItem(withLength: btnAlwaysHiddenLength)
            item.button?.image = Self.separatorLineImage
            item.button?.appearsDisabled = true
            item.autosaveName = "hora_hiddenBar_alwaysHidden"
            btnAlwaysHidden = item
        }
        btnAlwaysHidden?.length = savedAlwaysHiddenLength ?? btnAlwaysHiddenLength
        btnAlwaysHidden?.isVisible = true
    }

    /// 始终隐藏区第二分隔符关闭前的宽度，重开时恢复
    private var savedAlwaysHiddenLength: CGFloat?

    // MARK: - Screen Changes

    @objc private func handleScreenParametersChanged() {
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        if wasCollapsed {
            btnSeparate?.length = btnHiddenCollapseLength
            if HiddenBarPreferences.areSeparatorsHidden {
                btnAlwaysHidden?.length = btnAlwaysHiddenCollapseLength
            }
        }
    }

    private func updateCollapsedLengths() {
        let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        btnHiddenCollapseLength = Self.collapseLength(forScreenWidth: screenWidth)
    }

    /// 根据屏幕宽度计算折叠膨胀长度（纯函数，便于单元测试）
    /// 下限 500pt，上限 10000pt，通常为最大屏宽的 2 倍
    static func collapseLength(forScreenWidth width: CGFloat) -> CGFloat {
        max(500, min(width * 2, 10_000))
    }

    /// 折叠状态判定：separator 长度超过普通长度即为折叠（纯函数，便于单元测试）
    static func isCollapsedState(separatorLength: CGFloat, hiddenLength: CGFloat) -> Bool {
        separatorLength > hiddenLength
    }

    // MARK: - Position Validation

    private var isBtnSeparateValidPosition: Bool {
        guard let expandX = btnExpandCollapse?.button?.window?.frame.origin.x,
              let separateX = btnSeparate?.button?.window?.frame.origin.x else { return false }
        return expandX >= separateX
    }

    private var isBtnAlwaysHiddenValidPosition: Bool {
        guard HiddenBarPreferences.alwaysHiddenSectionEnabled else { return true }
        guard let separateX = btnSeparate?.button?.window?.frame.origin.x,
              let alwaysX = btnAlwaysHidden?.button?.window?.frame.origin.x else { return false }
        return separateX >= alwaysX
    }

    // MARK: - Menu Tracking

    @objc private func handleMenuDidBeginTracking() {
        isMenuTracking = true
        timer?.invalidate()
    }

    @objc private func handleMenuDidEndTracking() {
        isMenuTracking = false
        autoCollapseIfNeeded()
    }

    // MARK: - Position Repair

    /// 检测 chevron/separator 是否被刘海遮挡或离屏。
    /// ⚠️ macOS 26 实证：菜单栏布局由 ControlCenter(StatusKit) 管控，setFrame/写
    /// "NSStatusItem Preferred Position" 均无法移动渲染位置（setFrame 只改 AX frame），
    /// 因此仅记录诊断日志；位移依赖用户 ⌘+拖动（见启动向导指引）。
    private func checkOccludedPositions() {
        guard HiddenBarPreferences.isEnabled,
              let btnExpandCollapse, let btnSeparate else { return }

        let expandX = btnExpandCollapse.button?.window?.frame.origin.x
        let separateX = btnSeparate.button?.window?.frame.origin.x

        // 折叠态下 separator 左缘离屏是折叠机制使然，不视为异常，仅校验 chevron
        let expandBad = expandX.map(Self.isOccludedOrOffscreen) ?? true
        let separateBad = isCollapsed ? false : (separateX.map(Self.isOccludedOrOffscreen) ?? true)

        guard expandBad || separateBad else { return }

        CrashLogService.shared.log(
            "[HiddenBar] 状态项不可见（刘海遮挡或离屏）: chevron x=\(expandX ?? -1), separator x=\(separateX ?? -1)。请按住 ⌘ 拖动竖线调整位置"
        )
    }

    /// 判定菜单栏 x 坐标是否离屏或被刘海遮挡
    private static func isOccludedOrOffscreen(x: CGFloat) -> Bool {
        if x < 0 { return true }
        for screen in NSScreen.screens where x >= screen.frame.minX && x < screen.frame.maxX {
            guard let leftArea = screen.auxiliaryTopLeftArea,
                  let rightArea = screen.auxiliaryTopRightArea else { return false }
            let notchMinX = screen.frame.minX + leftArea.maxX
            let notchMaxX = screen.frame.minX + rightArea.minX
            return x >= notchMinX && x < notchMaxX
        }
        return true
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
        // 打开设置菜单时自动展开，让分隔线立即可见、可 Cmd+拖拽
        if isCollapsed { expandMenubar() }

        let menu = NSMenu()
        menu.autoenablesItems = false

        // 设置向导（随时可重新打开引导窗口，落到隐藏栏页）
        let wizardItem = NSMenuItem(
            title: "设置向导…",
            action: #selector(menuOpenWizard),
            keyEquivalent: ""
        )
        wizardItem.target = self
        menu.addItem(wizardItem)
        menu.addItem(.separator())

        // 开启/关闭隐藏栏（总开关）
        let enableItem = NSMenuItem(
            title: "开启隐藏栏",
            action: #selector(menuToggleEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = HiddenBarPreferences.isEnabled ? .on : .off
        menu.addItem(enableItem)

        // 自动隐藏时间子菜单
        let delaySubmenu = NSMenu()
        delaySubmenu.autoenablesItems = false
        let delayItem = NSMenuItem(
            title: "自动隐藏时间",
            action: nil,
            keyEquivalent: ""
        )
        delayItem.submenu = delaySubmenu
        delayItem.isEnabled = HiddenBarPreferences.isEnabled
        menu.addItem(delayItem)

        // 关闭自动隐藏
        let offItem = NSMenuItem(
            title: "关闭",
            action: #selector(menuSetAutoHideOff),
            keyEquivalent: ""
        )
        offItem.target = self
        offItem.state = HiddenBarPreferences.isAutoHide ? .off : .on
        delaySubmenu.addItem(offItem)
        delaySubmenu.addItem(.separator())

        for seconds in [5.0, 10.0, 15.0, 30.0, 60.0] {
            let item = NSMenuItem(
                title: "\(Int(seconds)) 秒",
                action: #selector(menuSetAutoHideDelay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = (HiddenBarPreferences.isAutoHide
                && abs(HiddenBarPreferences.autoHideSeconds - seconds) < 0.1) ? .on : .off
            item.representedObject = seconds
            delaySubmenu.addItem(item)
        }

        return menu
    }

    // MARK: - Menu Actions

    @objc private func menuToggleEnabled() {
        HiddenBarPreferences.isEnabled.toggle()
    }

    @objc private func menuOpenWizard() {
        onOpenWizard?()
    }

    @objc private func menuSetAutoHideOff() {
        HiddenBarPreferences.isAutoHide = false
        timer?.invalidate()
    }

    /// 选择自动隐藏时间：写入秒数并启用自动折叠
    @objc private func menuSetAutoHideDelay(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        HiddenBarPreferences.autoHideSeconds = seconds
        if !HiddenBarPreferences.isAutoHide { HiddenBarPreferences.isAutoHide = true }
        autoCollapseIfNeeded()
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

    /// 2px 宽圆角竖线，用作菜单栏分隔符图标（对齐原版 Hidden Bar 视觉效果）
    private static var separatorLineImage: NSImage {
        let size = NSSize(width: 2, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 1, yRadius: 1).fill()
        image.unlockFocus()
        // 直接显色（非 template），保证彩色壁纸上可辨
        return image
    }
}
