import Foundation
import ServiceManagement

// MARK: - Notification

extension Notification.Name {
    static let hiddenBarPrefsChanged = Notification.Name("hora.hiddenBar.prefsChanged")
}

// MARK: - Preferences

/// 菜单栏折叠功能偏好设置，基于 UserDefaults，风格与 RestNowSession 一致
enum HiddenBarPreferences {

    private enum DefaultsKey {
        static let isEnabled = "hora.hiddenBar.isEnabled"
        static let isAutoHide = "hora.hiddenBar.isAutoHide"
        static let autoHideSeconds = "hora.hiddenBar.autoHideSeconds"
        static let alwaysHiddenSectionEnabled = "hora.hiddenBar.alwaysHiddenSectionEnabled"
        static let areSeparatorsHidden = "hora.hiddenBar.areSeparatorsHidden"
        static let isAutoStart = "hora.hiddenBar.isAutoStart"
    }

    // MARK: - Enabled（总开关）

    /// 隐藏栏总开关（默认开启）：关闭时 chevron 与竖线分隔符从菜单栏移除
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.isEnabled) == nil ? true : UserDefaults.standard.bool(forKey: DefaultsKey.isEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.isEnabled)
            NotificationCenter.default.post(name: .hiddenBarPrefsChanged, object: nil)
        }
    }

    // MARK: - Auto Hide

    static var isAutoHide: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.isAutoHide) == nil ? false : UserDefaults.standard.bool(forKey: DefaultsKey.isAutoHide) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.isAutoHide)
            NotificationCenter.default.post(name: .hiddenBarPrefsChanged, object: nil)
        }
    }

    // MARK: - Auto Hide Delay

    static var autoHideSeconds: Double {
        get { let v = UserDefaults.standard.double(forKey: DefaultsKey.autoHideSeconds); return v > 0 ? v : 10.0 }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoHideSeconds)
            NotificationCenter.default.post(name: .hiddenBarPrefsChanged, object: nil)
        }
    }

    // MARK: - Always Hidden Section

    static var alwaysHiddenSectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.alwaysHiddenSectionEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.alwaysHiddenSectionEnabled)
            NotificationCenter.default.post(name: .hiddenBarPrefsChanged, object: nil)
        }
    }

    // MARK: - Separators Hidden

    static var areSeparatorsHidden: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.areSeparatorsHidden) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.areSeparatorsHidden)
            NotificationCenter.default.post(name: .hiddenBarPrefsChanged, object: nil)
        }
    }

    // MARK: - Auto Start at Login

    static var isAutoStart: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.isAutoStart) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.isAutoStart)
            syncAutoStart(newValue)
            NotificationCenter.default.post(name: .hiddenBarPrefsChanged, object: nil)
        }
    }

    /// 将开机启动状态与 SMAppService 同步（仅限 .app bundle，裸二进制无法注册）
    static func syncAutoStart(_ enabled: Bool) {
        // SMAppService 要求正规 .app bundle，裸二进制（swift run）下会报 Operation not permitted
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            fputs("[Hora] AutoStart skipped: not running from .app bundle\n", stderr)
            return
        }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            fputs("[Hora] AutoStart sync failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
