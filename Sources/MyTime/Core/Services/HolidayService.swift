import Foundation
import LunarSwift

/// 节假日服务 - 使用 lunar-swift 的 HolidayUtil
/// 无需本地存储 JSON，直接查询内置的节假日数据（2001-2026年）
@MainActor
class HolidayService {
    static let shared = HolidayService()
    
    // 缓存
    private var typeCache: [String: HolidayType?] = [:]
    private var nameCache: [String: String?] = [:]
    private let maxCacheSize = 200
    
    private init() {}
    
    private func cacheKey(year: Int, month: Int, day: Int) -> String {
        "\(year)-\(month)-\(day)"
    }
    
    /// 获取指定日期的节假日类型
    func getHolidayType(for date: Date) -> HolidayType? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        let key = cacheKey(year: year, month: month, day: day)
        if let cached = typeCache[key] { return cached }
        
        guard let holiday = HolidayUtil.getHolidayByYmd(year: year, month: month, day: day) else {
            typeCache[key] = nil
            return nil
        }
        
        let result: HolidayType = holiday.work ? .workday : .holiday
        if typeCache.count > maxCacheSize {
            typeCache.removeAll()
            nameCache.removeAll()
        }
        typeCache[key] = result
        return result
    }
    
    /// 获取节假日名称
    func getHolidayName(for date: Date) -> String? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        let key = cacheKey(year: year, month: month, day: day)
        if let cached = nameCache[key] { return cached }
        
        let result = HolidayUtil.getHolidayByYmd(year: year, month: month, day: day)?.name
        if nameCache.count > maxCacheSize {
            nameCache.removeAll()
        }
        nameCache[key] = result
        return result
    }
    
    /// 判断是否为节假日
    func isHoliday(_ date: Date) -> Bool {
        return getHolidayType(for: date) == .holiday
    }
    
    /// 判断是否为调休工作日
    func isWorkday(_ date: Date) -> Bool {
        return getHolidayType(for: date) == .workday
    }
    
    func clearCache() {
        typeCache.removeAll()
        nameCache.removeAll()
    }
}

// MARK: - Data Models

enum HolidayType {
    case holiday   // 法定节假日 (2)
    case workday   // 调休上班日 (1)
}
