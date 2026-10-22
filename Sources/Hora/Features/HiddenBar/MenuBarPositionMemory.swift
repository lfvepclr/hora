import AppKit

/// 记住第三方状态项的位置，并在应用退出后写回。
///
/// 部分应用（如阿里钉）退出时会删除自己的 `NSStatusItem Preferred Position`
/// 偏好，下次启动时系统会把图标插回隐藏区。Hora 周期记录运行中应用的位置，
/// 在应用退出、位置键被删除后写回，使图标下次仍出现在原来的位置。
@MainActor
final class MenuBarPositionMemory {
    static let shared = MenuBarPositionMemory()

    nonisolated private static let storageKey = "hora.hiddenBar.statusItemPositions"
    nonisolated private static let positionPrefix = "NSStatusItem Preferred Position "

    private let defaults: UserDefaults
    private let ownBundleID: String?
    private let runningBundleIDs: () -> [String]
    private let readPositions: (String) -> [String: Double]
    private let writePositions: (String, [String: Double]) -> Void

    private var snapshots: [String: [String: Double]]
    private var persistedSnapshots: [String: [String: Double]]
    private var knownRunningBundleIDs: Set<String>
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    init(
        defaults: UserDefaults = .standard,
        ownBundleID: String? = Bundle.main.bundleIdentifier,
        runningBundleIDs: @escaping () -> [String] = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        },
        readPositions: @escaping (String) -> [String: Double] = MenuBarPositionMemory.readSystemPositions,
        writePositions: @escaping (String, [String: Double]) -> Void = MenuBarPositionMemory.writeSystemPositions
    ) {
        self.defaults = defaults
        self.ownBundleID = ownBundleID
        self.runningBundleIDs = runningBundleIDs
        self.readPositions = readPositions
        self.writePositions = writePositions
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: [String: Double]] ?? [:]
        self.snapshots = stored
        self.persistedSnapshots = stored
        self.knownRunningBundleIDs = Set(runningBundleIDs())
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let running = Set(runningBundleIDs())
        knownRunningBundleIDs = running
        capture(bundleIDs: running)
        restoreMissingPositions(in: running)
        installObservers()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        captureAll()
        persistNow()
    }

    func capture(bundleID: String) {
        guard Self.isEligible(bundleID: bundleID, ownBundleID: ownBundleID) else { return }
        let positions = readPositions(bundleID).filter { $0.key.hasPrefix(Self.positionPrefix) }
        guard !positions.isEmpty else { return }
        guard snapshots[bundleID] != positions else { return }
        snapshots[bundleID] = positions
        persistNow()
    }

    func captureAll() {
        capture(bundleIDs: Set(runningBundleIDs()))
    }

    /// 周期检查：记录仍运行的应用，并对已经退出或丢失位置键的应用补写位置。
    /// 部分应用（如阿里钉）的退出不会触发 NSWorkspace 终止通知，因此不能只依赖通知。
    func tick() {
        let running = Set(runningBundleIDs())
        let exited = knownRunningBundleIDs.subtracting(running)
        knownRunningBundleIDs = running
        capture(bundleIDs: running)
        for bundleID in exited {
            restore(bundleID: bundleID)
        }
    }

    /// 只补写缺失的位置键，保留第三方应用自己仍保留的键。
    func restore(bundleID: String) {
        guard Self.isEligible(bundleID: bundleID, ownBundleID: ownBundleID),
              let saved = snapshots[bundleID],
              !saved.isEmpty else { return }

        let current = readPositions(bundleID)
        let missing = saved.filter { current[$0.key] == nil }
        guard !missing.isEmpty else { return }

        writePositions(bundleID, missing)
        CrashLogService.shared.log(
            "[MenuBarPositionMemory] Restored \(missing.count) position key(s) for \(bundleID)"
        )
    }

    func savedPositions(for bundleID: String) -> [String: Double]? {
        snapshots[bundleID]
    }

    func persistNow() {
        guard snapshots != persistedSnapshots else { return }
        defaults.set(snapshots, forKey: Self.storageKey)
        persistedSnapshots = snapshots
    }

    // MARK: - Observers

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            Task { @MainActor in
                self?.restore(bundleID: bundleID)
            }
        })

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            Task { @MainActor in
                // 应用尚未创建状态项，此时补写的位置键会在本次启动生效。
                self?.restore(bundleID: bundleID)
            }
        })

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.captureAll()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.captureAll()
                self?.persistNow()
            }
        })
    }

    private func capture(bundleIDs: Set<String>) {
        for bundleID in bundleIDs {
            capture(bundleID: bundleID)
        }
    }

    private func restoreMissingPositions(in bundleIDs: Set<String>) {
        for bundleID in bundleIDs {
            restore(bundleID: bundleID)
        }
    }

    // MARK: - System Preference Store

    nonisolated static func isEligible(bundleID: String, ownBundleID: String?) -> Bool {
        guard !bundleID.isEmpty else { return false }
        if bundleID == ownBundleID { return false }
        if bundleID.hasPrefix("com.apple.") { return false }
        return true
    }

    nonisolated static func readSystemPositions(bundleID: String) -> [String: Double] {
        guard let keys = CFPreferencesCopyKeyList(
            bundleID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String] else { return [:] }

        var positions: [String: Double] = [:]
        for key in keys where key.hasPrefix(positionPrefix) {
            guard let value = CFPreferencesCopyAppValue(key as CFString, bundleID as CFString) else { continue }
            if let number = value as? NSNumber {
                positions[key] = number.doubleValue
            } else if let string = value as? String, let number = Double(string) {
                positions[key] = number
            }
        }
        return positions
    }

    nonisolated static func writeSystemPositions(bundleID: String, positions: [String: Double]) {
        for (key, value) in positions {
            CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), bundleID as CFString)
        }
        CFPreferencesAppSynchronize(bundleID as CFString)
    }
}
