import Foundation
import LunarSwift

/// 农历日历服务 - 使用 6tail/lunar-swift 库
/// 文档: https://6tail.cn/calendar/api.html
@MainActor
class LunarCalendarService {
    static let shared = LunarCalendarService()
    
    // 缓存（使用有序字典支持LRU驱逐）
    private var lunarCache: [String: LunarInfo] = [:]
    private var almanacCache: [String: AlmanacData] = [:]
    private var festivalCache: [String: String?] = [:]
    private var solarTermCache: [String: String?] = [:]
    private var lunarOrder: [String] = []
    private var almanacOrder: [String] = []
    private var festivalOrder: [String] = []
    private var solarTermOrder: [String] = []
    private let maxLunarCache = 100
    private let maxAlmanacCache = 50
    private let maxFestivalCache = 100
    private let maxSolarTermCache = 100
    
    private init() {}
    
    private func cacheKey(year: Int, month: Int, day: Int) -> String {
        "\(year)-\(month)-\(day)"
    }
    
    private func dateComponents(from date: Date) -> (year: Int, month: Int, day: Int)? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return (year, month, day)
    }
    
    private func trimCacheIfNeeded() {
        if lunarCache.count > maxLunarCache {
            let removeCount = lunarCache.count / 2
            let keysToRemove = Array(lunarOrder.prefix(removeCount))
            keysToRemove.forEach { lunarCache.removeValue(forKey: $0) }
            lunarOrder.removeFirst(removeCount)
        }
        if almanacCache.count > maxAlmanacCache {
            let removeCount = almanacCache.count / 2
            let keysToRemove = Array(almanacOrder.prefix(removeCount))
            keysToRemove.forEach { almanacCache.removeValue(forKey: $0) }
            almanacOrder.removeFirst(removeCount)
        }
        if festivalCache.count > maxFestivalCache {
            let removeCount = festivalCache.count / 2
            let keysToRemove = Array(festivalOrder.prefix(removeCount))
            keysToRemove.forEach { festivalCache.removeValue(forKey: $0) }
            festivalOrder.removeFirst(removeCount)
        }
        if solarTermCache.count > maxSolarTermCache {
            let removeCount = solarTermCache.count / 2
            let keysToRemove = Array(solarTermOrder.prefix(removeCount))
            keysToRemove.forEach { solarTermCache.removeValue(forKey: $0) }
            solarTermOrder.removeFirst(removeCount)
        }
    }
    
    func clearCache() {
        lunarCache.removeAll()
        almanacCache.removeAll()
        festivalCache.removeAll()
        solarTermCache.removeAll()
        lunarOrder.removeAll()
        almanacOrder.removeAll()
        festivalOrder.removeAll()
        solarTermOrder.removeAll()
    }
    
    /// 预热当月日历数据（42天），确保首次打开0延迟
    func preWarmCurrentMonth() {
        let calendar = Calendar.current
        let now = Date()
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return }
        
        var date = monthInterval.start
        let weekday = calendar.component(.weekday, from: date)
        let leadingDays = weekday == 1 ? 6 : weekday - 2
        
        // 前置天数
        var dates: [Date] = []
        if leadingDays > 0 {
            for i in 1...leadingDays {
            if let prevDate = calendar.date(byAdding: .day, value: -i, to: date) {
                dates.insert(prevDate, at: 0)
            }
            }
        }
        // 当月天数
        while date < monthInterval.end {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        // 填满42天
        while dates.count < 42 {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        // 预热所有缓存
        for d in dates {
            _ = getLunarInfo(for: d)
            _ = getLunarFestival(for: d)
            _ = getSolarTerm(for: d)
        }
    }
    
    /// 获取指定日期的农历信息
    func getLunarInfo(for date: Date) -> LunarInfo {
        guard let (year, month, day) = dateComponents(from: date) else {
            return LunarInfo.empty
        }
        
        let key = cacheKey(year: year, month: month, day: day)
        if let cached = lunarCache[key] { return cached }
        trimCacheIfNeeded()
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        // 获取闰月信息 - 通过 LunarYear
        let lunarYear = LunarYear.fromYear(lunarYear: lunar.year)
        let leapMonth = lunarYear.leapMonth
        let isLeap = leapMonth > 0 && abs(lunar.month) == leapMonth
        
        let result = LunarInfo(
            lunarDay: lunar.dayInChinese,
            lunarMonth: lunar.monthInChinese,
            lunarYear: lunar.yearInChinese,
            ganZhiYear: lunar.yearInGanZhi,
            ganZhiMonth: lunar.monthInGanZhi,
            ganZhiDay: lunar.dayInGanZhi,
            zodiac: lunar.yearShengXiao,
            isLeapMonth: isLeap
        )
        lunarCache[key] = result
        lunarOrder.append(key)
        return result
    }
    
    /// 获取指定日期的黄历信息
    func getAlmanacInfo(for date: Date) -> AlmanacData {
        guard let (year, month, day) = dateComponents(from: date) else {
            return AlmanacData.empty
        }
        
        let key = cacheKey(year: year, month: month, day: day)
        if let cached = almanacCache[key] { return cached }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        let eightChar = lunar.eightChar
        
        let result = AlmanacData(
            yi: lunar.dayYi,
            ji: lunar.dayJi,
            wuXing: eightChar.dayWuXing,
            chong: lunar.dayChong,
            sha: lunar.daySha,
            zhiShen: "",
            jianChu: "",
            jiShen: lunar.dayJiShen,
            xiongShen: lunar.dayXiongSha,
            taiShen: "",
            pengZu: "\(lunar.pengZuGan) \(lunar.pengZuZhi)",
            xingXiu: lunar.xiu
        )
        almanacCache[key] = result
        almanacOrder.append(key)
        return result
    }
    
    /// 获取时辰吉凶
    func getShiChenInfo(for date: Date) -> [ShiChenData] {
        guard let (year, month, day) = dateComponents(from: date) else {
            return []
        }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        return lunar.times.map { time in
            ShiChenData(
                name: time.zhi,
                timeRange: "\(time.minHm)-\(time.maxHm)",
                isGood: time.yi.count > time.ji.count,
                chong: time.chong,
                sha: time.sha,
                yi: time.yi,
                ji: time.ji
            )
        }
    }
    
    /// 判断是否为节气
    func getSolarTerm(for date: Date) -> String? {
        guard let (year, month, day) = dateComponents(from: date) else {
            return nil
        }
        
        let key = cacheKey(year: year, month: month, day: day)
        if let cached = solarTermCache[key] { return cached }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        let jieQi = lunar.jieQi
        let result = jieQi.isEmpty ? nil : jieQi
        solarTermCache[key] = result
        solarTermOrder.append(key)
        return result
    }
    
    /// 获取农历节日
    func getLunarFestival(for date: Date) -> String? {
        guard let (year, month, day) = dateComponents(from: date) else {
            return nil
        }
        
        let key = cacheKey(year: year, month: month, day: day)
        if let cached = festivalCache[key] { return cached }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        // 优先返回农历节日 (festivals 是数组)
        if !lunar.festivals.isEmpty {
            let result = lunar.festivals.first
            festivalCache[key] = result
            festivalOrder.append(key)
            return result
        }
        
        // 然后检查公历节日
        if !solar.festivals.isEmpty {
            let result = solar.festivals.first
            festivalCache[key] = result
            festivalOrder.append(key)
            return result
        }
        
        festivalCache[key] = nil
        festivalOrder.append(key)
        return nil
    }
}

// MARK: - Data Models

struct LunarInfo {
    let lunarDay: String
    let lunarMonth: String
    let lunarYear: String
    let ganZhiYear: String
    let ganZhiMonth: String
    let ganZhiDay: String
    let zodiac: String
    let isLeapMonth: Bool
    
    var displayLunarDate: String {
        if isLeapMonth {
            return "闰\(lunarMonth)\(lunarDay)"
        }
        return "\(lunarMonth)\(lunarDay)"
    }
    
    static let empty = LunarInfo(
        lunarDay: "",
        lunarMonth: "",
        lunarYear: "",
        ganZhiYear: "",
        ganZhiMonth: "",
        ganZhiDay: "",
        zodiac: "",
        isLeapMonth: false
    )
}

struct AlmanacData {
    let yi: [String]
    let ji: [String]
    let wuXing: String
    let chong: String
    let sha: String
    let zhiShen: String
    let jianChu: String
    let jiShen: [String]
    let xiongShen: [String]
    let taiShen: String
    let pengZu: String
    let xingXiu: String
    
    var yiDisplay: String {
        yi.prefix(5).joined(separator: "、")
    }
    
    var jiDisplay: String {
        ji.prefix(5).joined(separator: "、")
    }
    
    static let empty = AlmanacData(
        yi: [],
        ji: [],
        wuXing: "",
        chong: "",
        sha: "",
        zhiShen: "",
        jianChu: "",
        jiShen: [],
        xiongShen: [],
        taiShen: "",
        pengZu: "",
        xingXiu: ""
    )
}

struct ShiChenData {
    let name: String
    let timeRange: String
    let isGood: Bool
    let chong: String
    let sha: String
    let yi: [String]
    let ji: [String]
}
