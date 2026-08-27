import XCTest
@testable import Hora

// MARK: - HiddenBarPreferences Tests (A1)

/// 偏好设置测试：默认值、持久化、非法值兜底、变更通知
final class HiddenBarPreferencesTests: XCTestCase {

    /// 所有隐藏栏偏好键（与 HiddenBarPreferences.DefaultsKey 保持一致）
    private let allKeys = [
        "hora.hiddenBar.isEnabled",
        "hora.hiddenBar.isAutoHide",
        "hora.hiddenBar.autoHideSeconds",
        "hora.hiddenBar.alwaysHiddenSectionEnabled",
        "hora.hiddenBar.areSeparatorsHidden",
        "hora.hiddenBar.isAutoStart",
    ]

    override func setUp() {
        super.setUp()
        resetAllKeys()
    }

    override func tearDown() {
        resetAllKeys()
        super.tearDown()
    }

    private func resetAllKeys() {
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: A1-1 默认值

    func testDefaultValues() {
        XCTAssertTrue(HiddenBarPreferences.isEnabled, "isEnabled 默认应为 true")
        XCTAssertFalse(HiddenBarPreferences.isAutoHide, "isAutoHide 默认应为 false")
        XCTAssertEqual(HiddenBarPreferences.autoHideSeconds, 10.0, "autoHideSeconds 默认应为 10.0")
        XCTAssertFalse(HiddenBarPreferences.alwaysHiddenSectionEnabled, "alwaysHiddenSectionEnabled 默认应为 false")
        XCTAssertFalse(HiddenBarPreferences.areSeparatorsHidden, "areSeparatorsHidden 默认应为 false")
        XCTAssertFalse(HiddenBarPreferences.isAutoStart, "isAutoStart 默认应为 false")
    }

    // MARK: A1-2 读写持久化

    func testReadWritePersistence() {
        HiddenBarPreferences.isEnabled = false
        HiddenBarPreferences.isAutoHide = true
        HiddenBarPreferences.autoHideSeconds = 30.0
        HiddenBarPreferences.alwaysHiddenSectionEnabled = true
        HiddenBarPreferences.areSeparatorsHidden = true
        // 注意：不写 isAutoStart，避免在测试进程中触发 SMAppService 同步

        XCTAssertFalse(HiddenBarPreferences.isEnabled)
        XCTAssertTrue(HiddenBarPreferences.isAutoHide)
        XCTAssertEqual(HiddenBarPreferences.autoHideSeconds, 30.0)
        XCTAssertTrue(HiddenBarPreferences.alwaysHiddenSectionEnabled)
        XCTAssertTrue(HiddenBarPreferences.areSeparatorsHidden)

        // 验证值确实落在 UserDefaults 中
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hora.hiddenBar.isEnabled"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hora.hiddenBar.isAutoHide"))
        XCTAssertEqual(UserDefaults.standard.double(forKey: "hora.hiddenBar.autoHideSeconds"), 30.0)
    }

    // MARK: A1-3 非法延迟兜底

    func testInvalidAutoHideSecondsFallback() {
        HiddenBarPreferences.autoHideSeconds = 0
        XCTAssertEqual(HiddenBarPreferences.autoHideSeconds, 10.0, "写入 0 应兜底为默认 10.0")

        HiddenBarPreferences.autoHideSeconds = -5
        XCTAssertEqual(HiddenBarPreferences.autoHideSeconds, 10.0, "写入负数应兜底为默认 10.0")

        HiddenBarPreferences.autoHideSeconds = 5.0
        XCTAssertEqual(HiddenBarPreferences.autoHideSeconds, 5.0, "合法值应原样返回")
    }

    // MARK: A1-4 / A1-5 变更通知

    func testPrefsChangedNotificationFiredOncePerSet() {
        var count = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .hiddenBarPrefsChanged, object: nil, queue: nil
        ) { _ in
            count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        HiddenBarPreferences.isAutoHide = true
        XCTAssertEqual(count, 1, "set isAutoHide 应恰好触发 1 次通知")

        HiddenBarPreferences.autoHideSeconds = 15.0
        XCTAssertEqual(count, 2, "set autoHideSeconds 应恰好触发 1 次通知")

        HiddenBarPreferences.alwaysHiddenSectionEnabled = true
        XCTAssertEqual(count, 3, "set alwaysHiddenSectionEnabled 应恰好触发 1 次通知")

        HiddenBarPreferences.areSeparatorsHidden = true
        XCTAssertEqual(count, 4, "set areSeparatorsHidden 应恰好触发 1 次通知")
    }
}

// MARK: - HiddenBarController Logic Tests (A2)

/// 控制器纯逻辑测试：折叠长度计算、折叠状态判定
/// HiddenBarController 为 @MainActor，测试方法同样标注 @MainActor
@MainActor
final class HiddenBarControllerLogicTests: XCTestCase {

    // MARK: A2-1 常规屏幕折叠长度

    func testCollapseLengthForTypicalScreen() {
        // 1728pt 屏幕（本机环境）：1728 * 2 = 3456
        let length = HiddenBarController.collapseLength(forScreenWidth: 1728)
        XCTAssertEqual(length, 3456, "1728pt 屏幕折叠长度应为 3456")
    }

    // MARK: A2-2 折叠长度下限

    func testCollapseLengthLowerBound() {
        let length = HiddenBarController.collapseLength(forScreenWidth: 200)
        XCTAssertGreaterThanOrEqual(length, 500, "极小屏折叠长度不得低于 500")
        XCTAssertEqual(length, 500, "200pt 屏幕应取下限 500")
    }

    // MARK: A2-3 折叠长度上限

    func testCollapseLengthUpperBound() {
        let length = HiddenBarController.collapseLength(forScreenWidth: 6000)
        XCTAssertLessThanOrEqual(length, 10_000, "超宽屏折叠长度不得超过 10000")
        XCTAssertEqual(length, 10_000, "6000pt 屏幕应取上限 10000")
    }

    // MARK: A2-4 展开态判定

    func testIsCollapsedStateWhenExpanded() {
        // separator 长度 = 20（普通长度）→ 未折叠
        XCTAssertFalse(
            HiddenBarController.isCollapsedState(separatorLength: 20, hiddenLength: 20),
            "separator 长度等于普通长度时应为展开态"
        )
    }

    // MARK: A2-5 折叠态判定

    func testIsCollapsedStateWhenCollapsed() {
        // separator 长度 = 3456（膨胀长度）→ 已折叠
        XCTAssertTrue(
            HiddenBarController.isCollapsedState(separatorLength: 3456, hiddenLength: 20),
            "separator 长度超过普通长度时应为折叠态"
        )
    }

    // MARK: A2-6 边界值判定

    func testIsCollapsedStateBoundary() {
        // 边界：恰好大于阈值 1pt 即折叠
        XCTAssertTrue(HiddenBarController.isCollapsedState(separatorLength: 20.5, hiddenLength: 20))
        XCTAssertFalse(HiddenBarController.isCollapsedState(separatorLength: 1, hiddenLength: 20))
    }
}
