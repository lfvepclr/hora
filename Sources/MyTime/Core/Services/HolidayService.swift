import Foundation
import LunarSwift

/// 节假日服务 - 使用 lunar-swift 的 HolidayUtil
/// 无需本地存储 JSON，直接查询内置的节假日数据（2001-2026年）
class HolidayService {
    static let shared = HolidayService()
    
    private init() {}
    
    /// 获取指定日期的节假日类型
    func getHolidayType(for date: Date) -> HolidayType? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        guard let holiday = HolidayUtil.getHolidayByYmd(year: year, month: month, day: day) else {
            return nil
        }
        
        // work = true 表示调休上班，work = false 表示放假
        return holiday.work ? .workday : .holiday
    }
    
    /// 获取节假日名称
    func getHolidayName(for date: Date) -> String? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        return HolidayUtil.getHolidayByYmd(year: year, month: month, day: day)?.name
    }
    
    /// 判断是否为节假日
    func isHoliday(_ date: Date) -> Bool {
        return getHolidayType(for: date) == .holiday
    }
    
    /// 判断是否为调休工作日
    func isWorkday(_ date: Date) -> Bool {
        return getHolidayType(for: date) == .workday
    }
}

// MARK: - Data Models

enum HolidayType {
    case holiday   // 法定节假日 (2)
    case workday   // 调休上班日 (1)
}
