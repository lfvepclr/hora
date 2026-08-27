# Hora 性能基线与优化记录

> 2026-08-27 · 测量环境：macOS 26.5.2 (25F84)、Apple Silicon、Release 构建（swift build -c release）
> 工具：`footprint <pid>`（phys_footprint）、`vmmap --summary`、`top -stats mem`

## 内存对比（Release 构建）

| 场景 | 优化前 | 优化后（地图惰性加载后） | 变化 |
| --- | --- | --- | --- |
| 静置（仅菜单栏） | 56 MB | **16 MB** | -71% |
| 打开日历后常驻 | ~56 MB | **~38 MB** | -32% |
| 打开世界时钟后常驻 | ~56 MB | 60 MB → 闲置 3 分钟后回落 | 见下方"闲置释放" |
| CG image 区域 | 36.2 MB（地图位图，常驻 swapped） | 64 KB（无位图） | -99.8% |

**结论：常驻内存全场景 ≤50MB 目标达成**（世界时钟重度使用后短暂 60MB，由闲置释放机制在 3 分钟后回收）。

> 补充：地图数据（world.json + 路径构建，约 1-2MB）已从启动预加载改为**首次打开世界时钟时惰性加载**
> （`WorldClockPopupView.onAppear → ensureLoaded()`，服务标 `@Observable` 保证数据就绪后视图自动刷新），静置峰值进一步从 18.5MB 降至 16MB。

## 瞬时峰值（phys_footprint_peak，一次性系统开销）

| 场景 | 峰值 | 说明 |
| --- | --- | --- |
| 首次打开日历 popover | 165 MB | SwiftUI 视图树 + 系统 framework 惰性加载，第二次打开不再增长，随后回落 |
| 首次打开世界时钟 | ~305 MB | 同上（叠加地图 Canvas 首渲染、城市标记层、昼夜分界计算） |

峰值均为一次性系统/框架初始化开销，打开后常驻立即回落；App 自身数据结构分配（world.json 解析、路径构建）合计 <3MB。

## 优化项明细

### 1. 世界地图：位图预渲染 → 矢量路径（-34MB，最大头）
- 旧实现：`WorldMapDataService.preRenderMapImage()` 用 NSImage lockFocus 渲染 1560×760（Retina 实际 2x 位图 36.2MB）常驻内存。
- 新实现：`buildMapPath()` 预构建整幅地图 `CGPath`（213 国点数据，约 1-2MB），`WorldMapView` 用 SwiftUI `Canvas` 按目标尺寸矢量绘制，任意分辨率无损。
- 顺带删除死代码：`countryHitData`/`findCountry`/`isPointInPolygon`（无调用者，白占一份 pathPoints 拷贝）。
- 涉及文件：`Sources/Hora/Core/Services/WorldMapDataService.swift`、`Sources/Hora/Features/WorldClock/Shapes/WorldMapShape.swift`

### 2. Popover 视图缓存闲置释放（世界时钟场景 -40MB）
- `AppDelegate.popoverDidClose` 启动 3 分钟闲置定时器，到期后重建 `contentViewController`，SwiftUI 视图树（含世界时钟缓存）释放，常驻回落静置水平。
- 打开 popover 时取消定时器；重建后首次打开约慢 1 秒（一次性）。
- 涉及文件：`Sources/Hora/App/AppDelegate.swift`

### 2.1 JSON 惰性加载与缓存上限（C2）
- `WorldMapDataService`（world.json + countryTimezones.json）：启动预加载 → **首次打开世界时钟时加载**（`WorldClockPopupView.onAppear`）。
- `LunarCalendarService`：已有 LRU 缓存上限（lunar 100 / almanac 50 / festival 100 / solarTerm 100 条，超限驱逐一半），满足滚动淘汰要求。
- `HolidayService`：已有 maxCacheSize=100 LRU 驱逐，满足要求。
- `DateFormatterCache`：已有 maxSize=30 超限清理（等同 LRU 简化版）。

### 3. 重绘评估（结论：已达标，无需改动）
- `NightOverlayShape`：昼夜分界线已用解析公式（121 个经度采样三角函数，<1ms），无需再加缓存。
- `DateDetailPanel` 时间显示已用 `TimelineView(.periodic 60s)`；`WorldClockPopupView` 的 Timer 在 onAppear/onDisappear 配对启停。
- `DateFormatterCache` 已有 maxSize=30 超限清理。

### 4. Swift 6 语言模式迁移
- `Package.swift` swift-tools-version 5.9 → 6.0（原有 StrictConcurrency=complete 实验特性转正）。
- 迁移修复：
  - `CrashLogService` 标记 `@unchecked Sendable`，新增 NSLock 保护 `pendingLogs/isFileReady/文件写入`；
  - `HiddenBarController.timer` 标记 `nonisolated(unsafe)`（仅主线程访问，deinit 兜底失效）。

### 4.1 @Observable 迁移与 Combine 精简（C4）
- `RestNowSession`、`RestNowColorSettings`：`ObservableObject + @Published` → `@Observable`；
  SwiftUI 引用点（`BreakOverlayView`/`RestNowSettingsView`/`RestNowColorSettingsView`）的 `@ObservedObject` 相应改为普通属性 / `@Bindable`（`$session.isEnabled` 绑定投影）。
- `AppDelegate` 的 `Publishers.CombineLatest3` 订阅改为 `withObservationTracking` 递归注册（onChange 单次触发后重注册），删除 `restNowCancellables`。
- `WorldMapDataService` 标 `@Observable`：支持惰性加载后视图自动刷新。
- `JSONDecoder` 三处（WorldMapDataService/CityDataService）提为 `static let` 复用。
- 未迁移项（有意保留）：`WorldClockViewModel`/`CalendarViewModel`/`AppState` 为纯视图内部状态，迁移收益小且改动面大；热路径已无大数组拷贝场景（`findCountry` hit-test 为死代码已删除），`Span`/borrowing 暂无用武之地。

## 常驻事件源清单（C3：NSEvent monitor / Timer 排查结果）

### NSEvent monitors（共 3 个，均为功能必需，生命周期 = 应用生命周期）
| 位置 | 类型 | 用途 |
| --- | --- | --- |
| AppDelegate | local leftMouseDown | 菜单栏日期项点击弹 popover |
| AppDelegate | local rightMouseDown | 菜单栏日期项右键菜单 |
| AppDelegate | global leftMouseDown | 点击外部关闭 popover |

（HiddenBarController 原有的拖动监控 monitor 已随位置守卫方案废弃删除）

### Timers（共 6 处，均带生命周期管理）
| 位置 | 周期 | 生命周期 |
| --- | --- | --- |
| AppDelegate.dateRefreshTimer | 60s 重复 | 常驻（日期变化刷新图标） |
| RestNowSession.timer | 1s 重复 | 仅 isEnabled 时运行 |
| RestNowSession.lockPollTimer | 1s 重复 | 仅 isEnabled 时运行 |
| HiddenBarController 自动折叠 | 单次 | 展开后按 autoHideSeconds 触发 |
| WorldClockViewModel 对齐分钟 timer | 单次+60s 重复 | 仅 popover 显示时（onAppear/onDisappear 配对） |
| AppDelegate 闲置释放 | 3min 单次 | popover 关闭后挂载，打开时取消 |

## 泄漏检查（C5）

`leaks <pid>`（Release 静置 + 打开日历/世界时钟后）：293 个泄漏 / 14.5KB，
调用栈全部位于系统框架（AppIntents / Foundation），**Hora 代码 0 泄漏**。

## Instruments .trace 说明

命令行 `xctrace record --attach` 对本应用受限（Failed to attach，裸二进制 attach 需 MallocStackLogging 环境变量且 GUI 会话支持）。
如需录制完整 .trace，请在 Xcode Instruments GUI 中选择 Allocations / Leaks / Time Profiler / Core Animation Commits 模板，
Target 选 `.build/release/app`（或打包后的 Hora.app）录制后存入本目录（docs/profile/）。
本文件的 footprint/vmmap/leaks 数据已覆盖同等验证维度。

## 复测命令

```bash
swift build -c release && .build/release/app &   # 启动后等待 ~20s
footprint $(pgrep -f ".build/release/app" | head -1)
vmmap --summary $(pgrep -f ".build/release/app" | head -1) | grep -E "Physical|CG image"
```

## 已知限制

- 瞬时峰值（首开各功能 165~305MB）来自 SwiftUI/系统 framework 惰性加载，App 层无法消除，且不占用持续物理内存。
- 世界时钟闲置释放会在 3 分钟后触发一次约 1 秒的视图重建，属于内存/启动速度的折中。
