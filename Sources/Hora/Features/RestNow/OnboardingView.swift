import SwiftUI
import Cocoa

// MARK: - Onboarding Window Manager

@MainActor
final class OnboardingWindowManager {
    static let shared = OnboardingWindowManager()
    private var window: NSWindow?

    /// 引导页索引：欢迎 / 定时休息 / 隐藏栏
    enum Page {
        static let welcome = 0
        static let restNow = 1
        static let hiddenBar = 2
    }

    /// 检查是否需要显示引导（首次启动）
    var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "hora.hasCompletedOnboarding")
    }

    /// 首次启动自动弹窗（从欢迎页开始）
    func showIfNeeded() {
        guard shouldShowOnboarding else { return }
        show(initialPage: Page.welcome)
    }

    /// 从菜单入口重新打开，可直接落到指定页
    func show(page: Int) {
        show(initialPage: page)
    }

    private func show(initialPage: Int) {
        // 已有引导窗口在展示时，通过通知切换到目标页（rootView 是值拷贝，不能直接改）
        if let existing = window {
            NotificationCenter.default.post(
                name: .onboardingJumpToPage,
                object: nil,
                userInfo: ["page": initialPage]
            )
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(initialPage: initialPage)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 500, height: 520))
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()

        window.isReleasedWhenClosed = false
        self.window = window

        // 窗口关闭时标记完成 onboarding
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            UserDefaults.standard.set(true, forKey: "hora.hasCompletedOnboarding")
            Task { @MainActor in
                OnboardingWindowManager.shared.window = nil
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关闭引导窗口
    func dismiss() {
        window?.close()
        window = nil
    }
}

// MARK: - Notification

extension Notification.Name {
    /// 菜单入口「设置向导」要求引导窗口跳到指定页（userInfo["page"]: Int）
    static let onboardingJumpToPage = Notification.Name("hora.onboarding.jumpToPage")
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var currentPage: Int
    @State private var workMinutes = 30
    @State private var restMinutes = 10
    @State private var forcedRestSeconds = 60

    // 隐藏栏页状态
    @State private var hiddenBarEnabled = HiddenBarPreferences.isEnabled
    @State private var autoHideChoice: Double
    @State private var isDemoCollapsed = false

    /// 菜单入口跳页通知
    private let jumpToPage = NotificationCenter.default
        .publisher(for: .onboardingJumpToPage)
        .receive(on: DispatchQueue.main)

    init(initialPage: Int = OnboardingWindowManager.Page.welcome) {
        _currentPage = State(initialValue: initialPage)
        let seconds = HiddenBarPreferences.autoHideSeconds
        _autoHideChoice = State(initialValue: HiddenBarPreferences.isAutoHide ? seconds : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentPage {
                case OnboardingWindowManager.Page.restNow: restNowSettingPage
                case OnboardingWindowManager.Page.hiddenBar: hiddenBarPage
                default: welcomePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pageIndicator
        }
        .frame(width: 500, height: 520)
        .onReceive(jumpToPage) { note in
            if let page = note.userInfo?["page"] as? Int {
                withAnimation(.easeInOut(duration: 0.25)) { currentPage = page }
            }
        }
    }

    // MARK: - 页码指示器

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 20 : 8, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
        .padding(.bottom, 14)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hora.hasCompletedOnboarding")
        OnboardingWindowManager.shared.dismiss()
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("欢迎使用 Hora")
                .font(.largeTitle.bold())

            Text("你的 macOS 时间管理助手")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "calendar", text: "智能日历：农历、节假日一目了然")
                featureRow(icon: "globe", text: "世界时钟：全球时区实时查看")
                featureRow(icon: "book.closed", text: "专业黄历：宜忌吉凶每日提醒")
                featureRow(icon: "timer", text: "定时休息：科学工作，按时休息")
                featureRow(icon: "menubar.dock.rectangle", text: "隐藏栏：收纳菜单栏图标，还你清爽空间")
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("继续") {
                withAnimation {
                    currentPage = OnboardingWindowManager.Page.restNow
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Page 2: RestNow Settings

    private var restNowSettingPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("设置定时休息")
                .font(.title.bold())

            Text("选择适合你的工作和休息时长")
                .font(.body)
                .foregroundStyle(.secondary)

            RestNowDurationPicker(
                workMinutes: $workMinutes,
                restMinutes: $restMinutes,
                forcedRestSeconds: $forcedRestSeconds,
                workOptions: [20, 30, 45, 60],
                restOptions: [1, 3, 5, 10]
            )
            .padding(.horizontal, 40)

            Spacer()

            HStack(spacing: 16) {
                Button("稍后设置") {
                    finishOnboarding()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("下一步") {
                    UserDefaults.standard.set(workMinutes * 60, forKey: "hora.restNow.workDuration")
                    UserDefaults.standard.set(restMinutes * 60, forKey: "hora.restNow.restDuration")
                    UserDefaults.standard.set(forcedRestSeconds, forKey: "hora.restNow.forcedRestSeconds")
                    RestNowSession.shared.isEnabled = true
                    withAnimation {
                        currentPage = OnboardingWindowManager.Page.hiddenBar
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Page 3: Hidden Bar

    private var hiddenBarPage: some View {
        VStack(spacing: 14) {
            Spacer()

            Text("菜单栏收纳")
                .font(.title.bold())

            Text("把不常用的菜单栏图标收进隐藏栏，需要时一键展开")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            hiddenBarDemoCard
                .padding(.horizontal, 44)

            VStack(spacing: 12) {
                Toggle(isOn: $hiddenBarEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: "menubar.dock.rectangle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        Text("启用隐藏栏")
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: hiddenBarEnabled) { _, newValue in
                    HiddenBarPreferences.isEnabled = newValue
                }

                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    Text("自动收起")
                    Spacer()
                    Picker("", selection: $autoHideChoice) {
                        Text("关闭").tag(0.0)
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                        Text("15 秒").tag(15.0)
                        Text("30 秒").tag(30.0)
                        Text("60 秒").tag(60.0)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 120)
                    .disabled(!hiddenBarEnabled)
                    .onChange(of: autoHideChoice) { _, newValue in
                        if newValue > 0 {
                            HiddenBarPreferences.autoHideSeconds = newValue
                            HiddenBarPreferences.isAutoHide = true
                        } else {
                            HiddenBarPreferences.isAutoHide = false
                        }
                    }
                }
            }
            .padding(.horizontal, 48)

            dragHintCard

            Spacer()

            Button("完成") {
                finishOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }

    /// 菜单栏折叠示意卡：左侧图标淡入淡出，模拟折叠/展开效果
    private var hiddenBarDemoCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    demoIcon("wifi")
                    demoIcon("paperplane.fill")
                    demoIcon("bell.fill")
                }
                .opacity(isDemoCollapsed ? 0.15 : 1)
                .blur(radius: isDemoCollapsed ? 0.8 : 0)

                Spacer(minLength: 10)

                // 分隔线（与真实 separatorLineImage 同视觉：白色 2px 圆角竖线）
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.65))
                    .frame(width: 2, height: 15)

                Image(systemName: isDemoCollapsed ? "chevron.right" : "chevron.left")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                Spacer(minLength: 10)

                Text("08月24日")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            Text(isDemoCollapsed ? "图标已隐藏，点击 < 展开" : "点击 | 折叠，图标收到隐藏栏")
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.4), value: isDemoCollapsed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("隐藏栏效果演示：折叠后左侧图标隐藏，点击箭头展开")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isDemoCollapsed = true
            }
        }
    }

    private func demoIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// ⌘+拖拽指引卡：macOS 26 下移动分隔线的唯一官方通道
    private var dragHintCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("小技巧：按住 ⌘ 拖动白色竖线，可以把它放到任意位置（建议紧挨右侧日期旁），Hora 会记住该位置")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 44)
        .accessibilityElement(children: .combine)
    }
}
