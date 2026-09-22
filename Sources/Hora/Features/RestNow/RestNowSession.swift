import Foundation
import AppKit
import CoreGraphics

/// 定时休息会话（@Observable 替代 ObservableObject/Combine，减少订阅开销）
@MainActor
@Observable
final class RestNowSession: NSObject {
    enum Phase: Sendable {
        case work
        case rest
    }

    static let shared = RestNowSession()

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let workDuration = "hora.restNow.workDuration"
        static let restDuration = "hora.restNow.restDuration"
        static let isEnabled = "hora.restNow.isEnabled"
        static let forcedRestSeconds = "hora.restNow.forcedRestSeconds"
        static let idleDetectionEnabled = "hora.restNow.idleDetectionEnabled"
        static let idleThresholdSeconds = "hora.restNow.idleThresholdSeconds"
    }

    // MARK: - Observable Properties

    private(set) var phase: Phase = .work
    private(set) var remainingSeconds: Int = 0
    private(set) var isPaused: Bool = false
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
            if isEnabled {
                resetCycle()
                startSession()
            } else {
                timer?.invalidate()
                timer = nil
                lockPollTimer?.invalidate()
                lockPollTimer = nil
                idlePollTimer?.invalidate()
                idlePollTimer = nil
                wasIdle = false
                BreakOverlayWindowManager.shared.hide()
            }
        }
    }

    // MARK: - Computed Properties

    var workDuration: Int {
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.workDuration)
        return stored > 0 ? stored : 20 * 60
    }

    var restDuration: Int {
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.restDuration)
        return stored > 0 ? stored : 5 * 60
    }

    /// 强制休息时间（秒）：休息开始后经过此秒数才显示跳过按钮，默认 10 秒
    var forcedRestSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.forcedRestSeconds)
        return stored > 0 ? stored : 10
    }

    /// 离开检测开关，默认开启。每轮空闲轮询现读 UserDefaults，切换即时生效
    var idleDetectionEnabled: Bool {
        (UserDefaults.standard.object(forKey: DefaultsKey.idleDetectionEnabled) as? Bool) ?? true
    }

    /// 键鼠空闲阈值（秒），低于 1 分钟视为未设置，回退默认 300
    var idleThresholdSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.idleThresholdSeconds)
        return stored > 0 ? stored : 300
    }

    var totalDuration: Int {
        switch phase {
        case .work: return workDuration
        case .rest: return restDuration
        }
    }

    var progress: Double {
        let total = Double(totalDuration)
        guard total > 0 else { return 0 }
        let raw = 1.0 - (Double(remainingSeconds) / total)
        return min(max(raw, 0.0), 1.0)
    }

    var menuBarTitle: String {
        let baseTitle: String
        switch phase {
        case .work:
            baseTitle = formattedTime(remainingSeconds)
        case .rest:
            baseTitle = "休息 " + formattedTime(remainingSeconds)
        }
        if isPaused {
            return "暂停 " + baseTitle
        }
        return baseTitle
    }

    // MARK: - Private State

    private var timer: Timer?
    private var lockPollTimer: Timer?
    private var wasScreenLocked: Bool = false
    private var lastWakeHandled: Date?
    private var lockedAt: Date?
    private var hasRegisteredWakeObservers = false
    /// 空闲轮询定时器（独立于主计时器：主计时器暂停后仍需检测活动恢复）
    private var idlePollTimer: Timer?
    /// 当前是否处于「键鼠空闲 → 计时暂停」状态
    private var wasIdle = false

    // MARK: - Init

    private override init() {
        // Load isEnabled from UserDefaults, default to false
        let stored = UserDefaults.standard.object(forKey: DefaultsKey.isEnabled)
        self.isEnabled = (stored as? Bool) ?? false
        super.init()

        if isEnabled {
            resetCycle()
            startSession()
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Public Methods

    func resetCycle() {
        BreakOverlayWindowManager.shared.hide()
        phase = .work
        remainingSeconds = workDuration
    }

    func startBreakNow() {
        phase = .rest
        remainingSeconds = restDuration
        if isPaused {
            isPaused = false
            startTimer()
        }
        playBell()
        BreakOverlayWindowManager.shared.show()
    }

    func skipBreak() {
        BreakOverlayWindowManager.shared.hide()
        phase = .work
        remainingSeconds = workDuration
        playBell()
    }

    func togglePause() {
        if isPaused {
            resumeCycle()
        } else {
            pauseCycle()
        }
    }

    func pauseCycle() {
        guard !isPaused else { return }
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resumeCycle() {
        guard isPaused else { return }
        isPaused = false
        startTimer()
    }

    // MARK: - Session

    /// 统一启动会话：计时器 + 锁屏轮询 + 空闲轮询 + 唤醒监听
    private func startSession() {
        startTimer()
        if lockPollTimer == nil {
            startLockPoll()
        }
        if idlePollTimer == nil {
            startIdlePoll()
        }
        if !hasRegisteredWakeObservers {
            registerWakeObservers()
            hasRegisteredWakeObservers = true
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private func tick() {
        guard !isPaused else { return }
        guard remainingSeconds > 0 else {
            switchPhase()
            return
        }
        remainingSeconds -= 1
    }

    private func switchPhase() {
        switch phase {
        case .work:
            startBreakNow()
        case .rest:
            skipBreak()
        }
    }

    // MARK: - Lock Detection

    private func startLockPoll() {
        wasScreenLocked = isScreenLocked()
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkLockState()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        lockPollTimer = poll
    }

    private func checkLockState() {
        let locked = isScreenLocked()
        if !wasScreenLocked && locked {
            lockedAt = Date()
            pauseCycle()
        }
        if wasScreenLocked && !locked {
            handleWakeEvent()
        }
        wasScreenLocked = locked
    }

    private nonisolated func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    // MARK: - Idle Detection

    private func startIdlePoll() {
        wasIdle = false
        let poll = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }
        poll.tolerance = 1
        RunLoop.main.add(poll, forMode: .common)
        idlePollTimer = poll
    }

    /// 空闲状态机（仅工作阶段生效）：
    /// 键鼠空闲超过阈值 → 暂停倒计时（保留剩余时间，不重置）；
    /// 检测到活动 → 继续剩余倒计时。
    private func checkIdleState() {
        guard isEnabled, idleDetectionEnabled, phase == .work else {
            if wasIdle {
                wasIdle = false
                resumeCycle()
            }
            return
        }
        // 锁屏期间归锁屏轮询管（checkLockState/handleWakeEvent），避免双重状态迁移
        guard !isScreenLocked() else { return }

        let idle = secondsSinceUserActivity()
        let threshold = TimeInterval(idleThresholdSeconds)
        if idle >= threshold {
            if !wasIdle || !isPaused {
                // 新进入空闲；或被唤醒处理器恢复但人仍未归（Watch/Touch ID 解锁无键鼠输入）
                wasIdle = true
                pauseCycle()
                CrashLogService.shared.log("Idle detection: 空闲 \(Int(idle))s ≥ 阈值 \(Int(threshold))s，工作倒计时已暂停")
            }
        } else if wasIdle {
            wasIdle = false
            resumeCycle()
            CrashLogService.shared.log("Idle detection: 检测到键鼠活动（空闲 \(Int(idle))s），工作倒计时继续")
        }
    }

    /// 距最近一次用户输入事件的秒数。
    /// 用白名单事件类型取最小值——`~0`（任意类型）在部分 macOS 版本会被系统/第三方
    /// 合成的 `.null` 事件持续重置，导致空闲秒数恒为 0。
    private func secondsSinceUserActivity() -> CFTimeInterval {
        Self.activityEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private static let activityEventTypes: [CGEventType] = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseUp, .rightMouseUp, .otherMouseUp,
        .keyDown, .keyUp, .flagsChanged, .scrollWheel
    ]

    // MARK: - Wake Handling

    private func registerWakeObservers() {
        let wakeNames: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in wakeNames {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleWake(_:)),
                name: name,
                object: nil
            )
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func handleWake(_ notification: Notification) {
        handleWakeEvent()
    }

    private func handleWakeEvent() {
        let now = Date()
        if let last = lastWakeHandled, now.timeIntervalSince(last) < 3 {
            return
        }
        lastWakeHandled = now

        let previousLockedAt = lockedAt
        lockedAt = nil

        if let previousLockedAt {
            let lockedFor = now.timeIntervalSince(previousLockedAt)

            if phase == .work {
                resetCycle()
                if isPaused {
                    isPaused = false
                    startTimer()
                }
                playBell()
                return
            }

            // Break phase: credit lock time against remaining break
            let creditedRemaining = Double(remainingSeconds) - lockedFor
            if creditedRemaining <= 0 {
                skipBreak()
                if isPaused {
                    isPaused = false
                    startTimer()
                }
            } else {
                remainingSeconds = Int(creditedRemaining)
                if isPaused {
                    isPaused = false
                    startTimer()
                }
            }
            return
        }

        // 无 lockedAt 记录（系统睡眠未经过锁屏、或锁屏检测被跳过）
        // 根据当前阶段分别处理，避免休息遮罩显示工作时间
        if phase == .rest {
            skipBreak()
        } else {
            resetCycle()
        }
        if isPaused {
            isPaused = false
            startTimer()
        }
        playBell()
    }

    // MARK: - Helpers

    private func playBell() {
        NSSound(named: NSSound.Name("Submarine"))?.play()
    }

    private func formattedTime(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
