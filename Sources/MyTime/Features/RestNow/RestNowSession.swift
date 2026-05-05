import Foundation
import AppKit
import Combine
import CoreGraphics

@MainActor
final class RestNowSession: NSObject, ObservableObject {
    enum Phase: Sendable {
        case work
        case rest
    }

    static let shared = RestNowSession()

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let workDuration = "mytime.restNow.workDuration"
        static let restDuration = "mytime.restNow.restDuration"
        static let isEnabled = "mytime.restNow.isEnabled"
    }

    // MARK: - Published Properties

    @Published private(set) var phase: Phase = .work
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isPaused: Bool = false
    @Published var isEnabled: Bool {
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
                BreakOverlayWindowManager.shared.hide()
            }
        }
    }

    // MARK: - Computed Properties

    var workDuration: Int {
        max(UserDefaults.standard.integer(forKey: DefaultsKey.workDuration), 20 * 60)
    }

    var restDuration: Int {
        max(UserDefaults.standard.integer(forKey: DefaultsKey.restDuration), 5 * 60)
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

    /// 统一启动会话：计时器 + 锁屏轮询 + 唤醒监听
    private func startSession() {
        startTimer()
        if lockPollTimer == nil {
            startLockPoll()
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

        resetCycle()
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
