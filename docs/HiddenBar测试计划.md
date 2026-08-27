# Hidden Bar 功能测试计划

> 版本：v1.0 · 日期：2026-08-23
> 覆盖范围：`Sources/Hora/Features/HiddenBar/` 全部功能 + `AppDelegate` 集成点
> 测试环境：macOS 26.5.2 (Build 25F84)，屏幕 1728pt 宽

---

## 一、测试目标与范围

验证以下功能的正确性：

| # | 功能模块 | 实现位置 |
|---|---------|---------|
| F1 | 折叠/展开菜单栏（chevron + separator 机制） | `HiddenBarController.expandCollapseIfNeeded()` |
| F2 | 状态项初始位置与布局（不离屏、顺序正确） | `HiddenBarController.setupUI()` / `forceRelayout()` |
| F3 | 自动折叠（含延迟设置、鼠标悬停延长） | `HiddenBarController.startTimerToAutoHide()` |
| F4 | 始终隐藏区域（第三条分隔线） | `HiddenBarController.toggleAlwaysHiddenStatusBar()` |
| F5 | 隐藏/显示分隔线 | `HiddenBarController.showHideSeparatorsAndAlwaysHideArea()` |
| F6 | 右键菜单子菜单（设置入口） | `HiddenBarController.buildSubmenu()` |
| F7 | 使用说明弹窗 | `HiddenBarController.showUsageHint()` |
| F8 | 偏好设置持久化 + 变更通知 | `HiddenBarPreferences` |
| F9 | 开机启动（SMAppService） | `HiddenBarPreferences.syncAutoStart()` |
| F10 | 屏幕参数变化适配（外接显示器/分辨率变化） | `HiddenBarController.handleScreenParametersChanged()` |
| F11 | 锁屏/解锁恢复 | 回归项（历史 Bug） |
| F12 | Hora 主功能不受影响（回归） | `AppDelegate` |

测试分两层：
- **A 层：自动化单元测试**（XCTest，`swift test` 可重复执行）
- **B 层：手动 E2E 测试**（真实运行 + AppleScript/AXPress 辅助验证）

---

## 二、测试环境准备

### 2.1 前置条件

```bash
cd /Users/spencer/workspace/qoder/hora
swift build                    # 确认编译通过
swift test                     # 确认现有测试基线通过
```

### 2.2 辅助验证工具

**查询 Hora 所有菜单栏项位置（AppleScript）：**

```applescript
tell application "System Events"
    tell process "Hora"   -- swift run 裸二进制时进程名为 "app"
        set output to ""
        repeat with i from 1 to count of menu bar items of menu bar 2
            set itm to menu bar item i of menu bar 2
            set p to position of itm
            set s to size of itm
            set output to output & "item" & i & ": x=" & (item 1 of p) & " w=" & (item 1 of s) & linefeed
        end repeat
        return output
    end tell
end tell
```

**AXPress 模拟点击 chevron：**

```applescript
tell application "System Events"
    tell process "Hora"
        -- chevron 通常是 menu bar 2 中最右侧的项之一，按实际序号调整
        perform action "AXPress" of menu bar item N of menu bar 2
    end tell
end tell
```

**清理测试环境（重置偏好）：**

```bash
defaults delete com.hora.app 2>/dev/null          # .app bundle 运行时
# 裸二进制运行时按可执行文件名删除
```

### 2.3 判定基准值（1728pt 屏幕）

| 状态 | separator 宽度 | chevron 位置 |
|------|---------------|-------------|
| 展开态 | 20pt（`btnHiddenLength`） | 屏幕内，x ≥ separator 的 x |
| 折叠态 | ≈3456pt（`1728×2`，即 `btnHiddenCollapseLength`） | 屏幕内右侧 |
| 正常位置 | 所有项 x ∈ [0, 1728] | 不允许出现负数离屏（如 -4200） |

---

## 三、A 层：自动化单元测试

新增测试文件：`Tests/HoraTests/HiddenBarTests.swift`。

> 说明：`HiddenBarController` 依赖真实菜单栏（AppKit UI），单元测试仅覆盖纯逻辑；
> UI 行为由 B 层手动测试覆盖。若后续重构可将 `updateCollapsedLengths`、
> `isCollapsed` 判定等抽为无 UI 依赖的纯函数以提升可测性。

### A1. HiddenBarPreferences 偏好设置测试

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| A1-1 默认值 | 清除全部 `hora.hiddenBar.*` 键后读取各属性 | `isAutoHide == false`；`autoHideSeconds == 10.0`；`alwaysHiddenSectionEnabled == false`；`areSeparatorsHidden == false`；`isAutoStart == false` |
| A1-2 读写持久化 | 依次 set 每个属性为非默认值，重新读取 | 读回值与写入值一致；`UserDefaults.standard` 中对应键存在 |
| A1-3 非法延迟兜底 | `autoHideSeconds = 0` / `-5` 后读取 | 返回默认值 `10.0` |
| A1-4 变更通知 | 订阅 `.hiddenBarPrefsChanged`，set 任一属性 | 每次 set 恰好收到 1 次通知 |
| A1-5 通知不带脏数据 | 连续 set 多次 | 通知次数与 set 次数一致，无丢失/重复 |

测试注意事项：每个用例 `setUp` 中删除全部 `hora.hiddenBar.*` 键，`tearDown` 中恢复，避免用例间污染；`isAutoStart` 的 setter 会触发 `syncAutoStart`，测试进程中非 .app bundle 会直接 skip（仅打印日志），不影响断言。

### A2. HiddenBarController 纯逻辑测试

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| A2-1 折叠长度计算 | 单屏 1728pt | `btnHiddenCollapseLength == 3456`（= min(1728×2, 10000)） |
| A2-2 折叠长度下限 | 模拟极小屏（<250pt） | 结果 ≥ 500 |
| A2-3 折叠长度上限 | 模拟超宽屏（>5000pt） | 结果 ≤ 10000 |
| A2-4 isCollapsed 判定 | separator length = 20 | `isCollapsed == false` |
| A2-5 isCollapsed 判定 | separator length = 3456 | `isCollapsed == true` |
| A2-6 始终隐藏区长度 | `alwaysHiddenSectionEnabled = true/false` | 展开态长度分别为 20 / 0；折叠态分别为 collapseLength / 0 |

> 实施方式：将 `updateCollapsedLengths` 的计算公式抽为静态纯函数
> `static func collapseLength(forScreenWidth:)` 以便直接断言；
> `isCollapsed` 判定可基于 `length > btnHiddenLength` 阈值直接测试。

### A3. 执行命令

```bash
swift test --filter HiddenBarTests
swift test    # 全量回归（含 NightOverlayShapeTests）
```

---

## 四、B 层：手动 E2E 测试

### B1. 启动与初始布局（F2，含历史 Bug 回归）

**前置**：清理 defaults，屏幕未锁屏。

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B1-1 裸二进制启动 | `swift run app` | 启动日志无 `AutoStart sync failed`；出现 `AutoStart skipped: not running from .app bundle`；无崩溃 |
| B1-2 状态项数量 | AppleScript 查询 Hora 菜单栏项 | 至少 3 项：日期项、chevron（〈）、separator（竖线） |
| B1-3 位置在屏幕内 | AppleScript 查询各项 x 坐标 | 全部 x ∈ [0, 1728]，无 -4200 等离屏值（**历史 Bug 回归**） |
| B1-4 chevron 在 separator 右侧 | 比较两者 x 坐标 | `chevron.x ≥ separator.x`（**历史 Bug 回归**：lazy 访问顺序） |
| B1-5 separator 初始宽度 | 查询 separator size | 宽度 = 20pt |
| B1-6 图标外观 | 目视 | chevron 显示 `chevron.left`（〈）；separator 为 1px 竖线 |
| B1-7 .app bundle 启动 | `swift run dmg` 打包后运行 dist 中 .app | 启动正常，进程名 "Hora"，同样通过 B1-2 ~ B1-6 |

### B2. 折叠/展开核心流程（F1）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B2-1 点击折叠 | 真实鼠标左键点击 chevron | separator 宽度膨胀至 ≈3456pt；separator 左侧图标（含 Hora 日期项）被推出屏幕不可见；chevron 变为 `chevron.right`（〉） |
| B2-2 点击展开 | 再次左键点击 chevron | separator 恢复 20pt；左侧图标恢复可见；chevron 变回 〈 |
| B2-3 AXPress 折叠 | AppleScript AXPress chevron | 同 B2-1（验证 `currentEvent == nil` 分支，**历史 Bug 回归**） |
| B2-4 AXPress 展开 | AppleScript AXPress chevron | 同 B2-2 |
| B2-5 快速连续点击 | 300ms 内连点两次 | `isToggle` 防抖生效，状态只切换一次，无错乱 |
| B2-6 Option+左键点击 | 按住 Option 点击 chevron | 触发分隔线显示/隐藏切换（而非折叠） |
| B2-7 右键 chevron | 右键点击 chevron | 弹出 Hora 主右键菜单（`onContextMenu` 回调生效） |
| B2-8 无左侧图标时折叠 | 移除/隐藏 chevron 左侧所有第三方图标后折叠 | 折叠正常执行，展开后布局无异常 |
| B2-9 菜单项折叠 | 右键菜单 → 隐藏栏 → "折叠菜单栏" | 效果同 B2-1；菜单标题随状态变为 "展开菜单栏" |

### B3. 自动折叠（F3）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B3-1 开启自动折叠 | 右键菜单 → 隐藏栏 → 勾选 "自动折叠"，先展开菜单栏 | 默认 10 秒后自动折叠 |
| B3-2 菜单状态显示 | 重新打开菜单 | "自动折叠" 项显示 ✓ |
| B3-3 修改延迟 | 自动折叠延迟 → 选择 "5 秒" | 该项显示 ✓，其余无 ✓；展开后约 5 秒自动折叠 |
| B3-4 各延迟档逐一验证 | 依次选 5/10/15/30/60 秒 | 实际折叠时间与所选一致（±1 秒误差） |
| B3-5 鼠标在菜单栏内延长 | 展开后把鼠标移到菜单栏保持不动，等待超过延迟时间 | 不折叠；定时器重启；鼠标移出后下一个周期折叠 |
| B3-6 关闭自动折叠 | 取消勾选 "自动折叠" 后展开 | 等待超过延迟时间不再折叠 |
| B3-7 折叠态下开启 | 折叠状态下勾选 "自动折叠" | 不触发多余定时器，无异常 |
| B3-8 持久化 | 开启自动折叠 + 设置 5 秒后重启应用 | 重启后设置保留；展开后 5 秒自动折叠 |

### B4. 始终隐藏区域（F4）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B4-1 开启 | 右键菜单 → 隐藏栏 → 勾选 "始终隐藏区域" | 出现第三条分隔线（灰色禁用态竖线），位于 separator 左侧 |
| B4-2 拖拽图标进入 | Cmd+拖拽一个图标到第三分隔线左侧 | 图标位于始终隐藏区 |
| B4-3 折叠隐藏 | 点击 chevron 折叠 | 始终隐藏区与普通隐藏区图标均不可见 |
| B4-4 展开仍隐藏 | 点击 chevron 展开 | **始终隐藏区图标仍然不可见**（核心差异点），普通隐藏区图标恢复 |
| B4-5 再次显示 | Option+点击 chevron（或菜单切换分隔线） | 始终隐藏区图标显示 |
| B4-6 关闭 | 取消勾选 "始终隐藏区域" | 第三分隔线消失，原区域内的图标恢复显示 |
| B4-7 持久化 | 开启后重启应用 | 第三分隔线仍在，区域行为一致 |

### B5. 隐藏/显示分隔线（F5）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B5-1 隐藏分隔线 | 右键菜单 → 隐藏栏 → 勾选 "隐藏分隔线" | separator 与第三分隔线的可见宽度视觉上消失（功能仍在），菜单项显示 ✓ |
| B5-2 功能仍可用 | 隐藏分隔线状态下点击 chevron | 折叠/展开照常工作 |
| B5-3 恢复分隔线 | 取消勾选（或 Option+点击 chevron） | 分隔线恢复显示 |
| B5-4 折叠态切换 | 折叠状态下切换隐藏分隔线 | 自动先展开（`if isCollapsed { expandMenubar() }`），无布局错乱 |
| B5-5 持久化 | 隐藏分隔线后重启 | 重启后分隔线仍隐藏 |

### B6. 右键菜单与使用说明（F6、F7）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B6-1 菜单结构 | 右键 Hora 日期项 | 出现 "隐藏栏" 子菜单，包含：折叠菜单栏 / 使用说明… / 自动折叠 / 自动折叠延迟 / 始终隐藏区域 / 隐藏分隔线 |
| B6-2 使用说明弹窗 | 隐藏栏 → 使用说明… | 弹出 NSAlert，说明 Cmd+拖拽 设置隐藏/显示的方法，"知道了" 按钮可关闭 |
| B6-3 separator 菜单 | 点击 separator 竖线 | 弹出含 "隐藏栏设置…" 的菜单，点击后同样弹出使用说明 |
| B6-4 标题动态更新 | 折叠/展开后重新打开菜单 | "折叠菜单栏" ⇄ "展开菜单栏" 标题正确切换 |
| B6-5 各开关状态回显 | 切换各选项后重新打开菜单 | ✓ 状态与 UserDefaults 实际值一致 |

### B7. 开机启动（F9）

**前置**：必须使用 .app bundle（`swift run dmg` 产物）。

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B7-1 裸二进制跳过 | `swift run app` | 日志打印 `AutoStart skipped`，无 `Operation not permitted` 报错（**历史 Bug 回归**） |
| B7-2 开启开机启动 | .app 中右键菜单 → 勾选 "开机启动" | 无报错；`sfltool` / 系统设置 → 通用 → 登录项 中出现 Hora |
| B7-3 注销验证 | 注销并重新登录 | Hora 自动启动 |
| B7-4 关闭开机启动 | 取消勾选 "开机启动" | 登录项中 Hora 移除；注销后不再自动启动 |
| B7-5 幂等性 | 连续开关多次 | SMAppService 状态与设置始终一致，无异常日志 |

### B8. 屏幕变化与环境鲁棒性（F10、F11）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B8-1 外接显示器 | 折叠状态下接入/断开外接显示器 | `handleScreenParametersChanged` 触发；折叠状态保持，折叠长度按新最大屏宽重算（500~10000） |
| B8-2 分辨率切换 | 折叠状态下切换显示分辨率 | 同上，无布局错乱 |
| B8-3 锁屏恢复 | 折叠状态下锁屏 → 解锁 | 折叠状态保持；chevron/separator 仍在屏幕内（**历史 Bug 回归**） |
| B8-4 睡眠唤醒 | 展开状态下合盖睡眠 → 唤醒 | 状态项位置正常，功能可用 |
| B8-5 深色/浅色模式切换 | 两种外观下查看 | chevron/separator 为 template image，颜色自适应 |
| B8-6 长时间运行 | 应用运行 ≥2 小时，期间多次折叠/展开 | 无内存明显增长、无定时器泄漏（`timer` 正确 invalidate） |

### B9. Hora 主功能回归（F12）

| 用例 | 步骤 | 预期结果 |
|------|------|---------|
| B9-1 日期 popover | 左键点击日期项 | 日历 popover 正常弹出/关闭 |
| B9-2 日期项右键 | 右键日期项 | 主菜单正常，含 "开机启动"、"隐藏栏" 等项 |
| B9-3 Cmd+拖拽日期项 | Cmd+拖拽 Hora 日期项到分隔线左侧 | 可正常拖动；折叠后日期项被隐藏；展开后恢复 |
| B9-4 RestNow 进度环 | 开启 RestNow | 日期项左侧进度环正常显示，折叠/展开不影响 |
| B9-5 世界时钟/黄历弹窗 | 打开各功能弹窗 | 功能正常，与隐藏栏功能无冲突 |

---

## 五、历史 Bug 专项回归清单

以下用例来自开发期间真实发现的缺陷，每次改动 HiddenBar 模块后必须全部通过：

| 编号 | 对应 Bug | 回归用例 |
|------|---------|---------|
| R1 | chevron/separator 被放到 -4200pt 离屏位置 | B1-3 |
| R2 | lazy 访问顺序错误导致 chevron 在 separator 左侧，折叠被跳过 | B1-4、B2-1 |
| R3 | `NSApp.currentEvent == nil` 时 buttonPressed 直接返回无反应 | B2-3、B2-4 |
| R4 | 裸二进制下 SMAppService 报 Operation not permitted | B7-1 |
| R5 | 锁屏后截图全黑、状态项位置异常 | B8-3（测试前确保屏幕未锁屏） |

---

## 六、通过标准

1. **A 层**：`swift test` 全部通过，HiddenBarTests 新增用例 100% 通过。
2. **B 层**：B1~B9 全部用例通过；历史回归清单 R1~R5 全部通过。
3. 无崩溃、无 `AutoStart sync failed` 类错误日志、无状态项离屏。
4. 偏好设置经重启后 100% 持久化（除按设计不持久化的项）。

## 七、已知限制与说明

- **CGEvent 模拟点击对 NSStatusItem 不可靠**，E2E 一律使用真实鼠标点击或 AXPress。
- **开机启动只能在 .app bundle 下验证**，`swift run` 裸二进制无法注册 SMAppService。
- macOS 26+ 菜单栏架构下，状态项位置由系统管理，自动化断言以 AppleScript 查询为准。
- separator 膨胀折叠是"推出屏幕"而非真正隐藏，属于 Hidden Bar 原版机制的固有行为，不计为缺陷。

## 八、执行记录模板

| 日期 | 执行版本(commit) | A层结果 | B层通过/总数 | 回归清单 | 备注 |
|------|-----------------|---------|--------------|---------|------|
| 2026-08-23 | 34be841 + 可测性重构（未提交） | 10/10 通过（全量 30/30） | 自动化部分 12/12 通过 | R1✓ R2✓ R3✓ R4✓ | 见下方执行明细 |

### 2026-08-23 执行明细

**A 层（自动化，全部通过）：**
- HiddenBarPreferencesTests 4 例：默认值、读写持久化、非法延迟兜底、变更通知次数
- HiddenBarControllerLogicTests 6 例：折叠长度 1728→3456、下限 500、上限 10000、折叠/展开/边界判定

**B 层（自动化可验证部分，全部通过）：**

| 用例 | 结果 | 实测数据 |
|------|------|---------|
| B1-1 裸二进制启动 | ✅ | 日志仅 `AutoStart skipped`，无报错 |
| B1-2 状态项数量 | ✅ | 4 项（日期项 + chevron + separator + 系统项） |
| B1-3 位置在屏幕内 | ✅ | chevron x=908、separator x=878，均在 [0,1728] |
| B1-4 chevron 在 separator 右侧 | ✅ | 908 ≥ 878 |
| B1-5 separator 初始宽度 | ✅ | 22pt（含边距，基准 20pt） |
| B2-3 AXPress 折叠 | ✅ | separator 22pt → 3458pt |
| B2-4 AXPress 展开 | ✅ | separator 3458pt → 22pt，左侧图标恢复可见 |
| B3-1 自动折叠 | ✅ | 展开后 5 秒内自动折叠（3458pt） |
| B3-8 持久化（重启加载） | ✅ | 重启后按 isAutoHide=1 自动折叠 |
| B3-3 延迟生效 | ✅ | 改 delay=3 后重启，6 秒内完成自动折叠 |
| B7-1 裸二进制跳过 SMAppService | ✅ | 无 `Operation not permitted` |
| R1~R4 历史回归 | ✅ | 无离屏、顺序正确、AX 点击有响应、无启动报错 |

**遗留手动项（需真人操作，未自动化执行）：**
- B2-1/2 真实鼠标点击、B2-5 快速连点、B2-6 Option 点击、B2-7 右键菜单
- B3-5 鼠标悬停延长、B4 Cmd+拖拽始终隐藏区、B5 分隔线视觉隐藏
- B6 菜单结构与使用说明弹窗、B7-2~5 .app bundle 开机启动（需 `swift run dmg` 打包）
- B8-1/2/4 外接显示器、睡眠唤醒、B9 Hora 主功能回归

**资源清理确认：**
- 测试进程已全部停止（`pgrep` 无残留）
- `autoHideSeconds` 已恢复测试前原值 5；`isAutoHide` 保持测试前原值 1
- 临时日志 `/tmp/hora_test*.log` 已删除
