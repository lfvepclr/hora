import SwiftUI
import Cocoa

// MARK: - Onboarding Window Manager

@MainActor
final class OnboardingWindowManager {
    static let shared = OnboardingWindowManager()
    private var window: NSWindow?

    /// 检查是否需要显示引导（首次启动）
    var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "mytime.hasCompletedOnboarding")
    }

    /// 显示引导窗口
    func showIfNeeded() {
        guard shouldShowOnboarding else { return }

        let contentView = OnboardingView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 500, height: 340))
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
            UserDefaults.standard.set(true, forKey: "mytime.hasCompletedOnboarding")
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

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var workMinutes = 30
    @State private var restMinutes = 10

    var body: some View {
        Group {
            if currentPage == 0 {
                welcomePage
            } else {
                restNowSettingPage
            }
        }
        .frame(width: 500, height: 340)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("欢迎使用 MyTime")
                .font(.largeTitle.bold())

            Text("你的 macOS 时间管理助手")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "calendar", text: "智能日历：农历、节假日一目了然")
                featureRow(icon: "globe", text: "世界时钟：全球时区实时查看")
                featureRow(icon: "book.closed", text: "专业黄历：宜忌吉凶每日提醒")
                featureRow(icon: "timer", text: "定时休息：科学工作，按时休息")
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("继续") {
                withAnimation {
                    currentPage = 1
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

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("工作时长")
                        .font(.headline)
                    Picker("工作时长", selection: $workMinutes) {
                        Text("20 分钟").tag(20)
                        Text("30 分钟").tag(30)
                        Text("45 分钟").tag(45)
                        Text("60 分钟").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("休息时长")
                        .font(.headline)
                    Picker("休息时长", selection: $restMinutes) {
                        Text("5 分钟").tag(5)
                        Text("10 分钟").tag(10)
                        Text("20 分钟").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            HStack(spacing: 16) {
                Button("稍后设置") {
                    UserDefaults.standard.set(true, forKey: "mytime.hasCompletedOnboarding")
                    OnboardingWindowManager.shared.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("开始使用") {
                    UserDefaults.standard.set(workMinutes * 60, forKey: "mytime.restNow.workDuration")
                    UserDefaults.standard.set(restMinutes * 60, forKey: "mytime.restNow.restDuration")
                    RestNowSession.shared.isEnabled = true
                    UserDefaults.standard.set(true, forKey: "mytime.hasCompletedOnboarding")
                    OnboardingWindowManager.shared.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
    }
}
