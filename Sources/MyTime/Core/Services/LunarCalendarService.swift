import Foundation
import LunarSwift

/// 农历日历服务 - 使用 6tail/lunar-swift 库
/// 文档: https://6tail.cn/calendar/api.html
@MainActor
class LunarCalendarService {
    static let shared = LunarCalendarService()
    
    private init() {}
    
    /// 获取指定日期的农历信息
    func getLunarInfo(for date: Date) -> LunarInfo {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return LunarInfo.empty
        }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        // 获取闰月信息 - 通过 LunarYear
        let lunarYear = LunarYear.fromYear(lunarYear: lunar.year)
        let leapMonth = lunarYear.leapMonth
        let isLeap = leapMonth > 0 && abs(lunar.month) == leapMonth
        
        return LunarInfo(
            lunarDay: lunar.dayInChinese,
            lunarMonth: lunar.monthInChinese,
            lunarYear: lunar.yearInChinese,
            ganZhiYear: lunar.yearInGanZhi,
            ganZhiMonth: lunar.monthInGanZhi,
            ganZhiDay: lunar.dayInGanZhi,
            zodiac: lunar.yearShengXiao,
            isLeapMonth: isLeap
        )
    }
    
    /// 获取指定日期的黄历信息
    func getAlmanacInfo(for date: Date) -> AlmanacData {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return AlmanacData.empty
        }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        let eightChar = lunar.eightChar
        
        return AlmanacData(
            yi: lunar.dayYi,
            ji: lunar.dayJi,
            wuXing: eightChar.dayWuXing,
            chong: lunar.dayChong,
            sha: lunar.daySha,
            zhiShen: "",  // lunar-swift 中没有直接的 dayZhiShen
            jianChu: "",
            jiShen: lunar.dayJiShen,
            xiongShen: lunar.dayXiongSha,
            taiShen: "",  // lunar-swift 中没有直接的 taiShen
            pengZu: "\(lunar.pengZuGan) \(lunar.pengZuZhi)",
            xingXiu: lunar.xiu
        )
    }
    
    /// 获取时辰吉凶
    func getShiChenInfo(for date: Date) -> [ShiChenData] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
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
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        let jieQi = lunar.jieQi
        return jieQi.isEmpty ? nil : jieQi
    }
    
    /// 获取农历节日
    func getLunarFestival(for date: Date) -> String? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        
        let solar = Solar(year: year, month: month, day: day)
        let lunar = solar.lunar
        
        // 优先返回农历节日 (festivals 是数组)
        if !lunar.festivals.isEmpty {
            return lunar.festivals.first
        }
        
        // 然后检查公历节日
        if !solar.festivals.isEmpty {
            return solar.festivals.first
        }
        
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
