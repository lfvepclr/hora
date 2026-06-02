import SwiftUI

/// 日历网格视图 - 用于菜单栏弹窗
struct CalendarGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(daysInMonth(), id: \.self) { date in
                CompactDayCell(
                    date: date,
                    isSelected: isSameDay(date, viewModel.selectedDate),
                    isToday: Calendar.current.isDateInToday(date),
                    currentMonth: viewModel.currentDate,
                    onTap: {
                        viewModel.selectedDate = date
                    }
                )
            }
        }
    }
    
    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    private func daysInMonth() -> [Date] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: viewModel.currentDate) else {
            return []
        }
        
        var dates: [Date] = []
        var date = monthInterval.start
        
        // 添加前一个月的天数来填充网格
        let weekday = Calendar.current.component(.weekday, from: date)
        // 调整为周一开始 (周日=1, 周一=2, ...)
        let leadingDays = weekday == 1 ? 6 : weekday - 2
        if leadingDays > 0 {
            for i in 1...leadingDays {
                if let prevDate = Calendar.current.date(byAdding: .day, value: -i, to: date) {
                    dates.insert(prevDate, at: 0)
                }
            }
        }
        
        // 添加当月天数
        while date < monthInterval.end {
            dates.append(date)
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        // 添加后一个月的天数来填满网格（按实际需要的行数填充，而非固定6行）
        let rows = (dates.count + 6) / 7  // 向上取整计算所需行数
        let totalCells = rows * 7
        while dates.count < totalCells {
            dates.append(date)
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        return dates
    }
}

/// 紧凑的日期单元格 - 1:1复刻百度日历风格
struct CompactDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let currentMonth: Date
    let onTap: () -> Void
    private let cellData: CellData
    
    init(date: Date, isSelected: Bool, isToday: Bool, currentMonth: Date, onTap: @escaping () -> Void) {
        self.date = date
        self.isSelected = isSelected
        self.isToday = isToday
        self.currentMonth = currentMonth
        self.onTap = onTap
        self.cellData = CellData(date: date)
    }
    
    struct CellData {
        let lunarInfo: LunarInfo
        let holidayType: HolidayType?
        let holidayName: String?
        let lunarFestival: String?
        let solarTerm: String?
        
        var displayText: String {
            if let name = holidayName { return name }
            if let festival = lunarFestival { return festival }
            if let term = solarTerm { return term }
            return lunarInfo.lunarDay
        }
        
        @MainActor
        init(date: Date) {
            self.lunarInfo = LunarCalendarService.shared.getLunarInfo(for: date)
            self.holidayType = HolidayService.shared.getHolidayType(for: date)
            self.holidayName = HolidayService.shared.getHolidayName(for: date)
            self.lunarFestival = LunarCalendarService.shared.getLunarFestival(for: date)
            self.solarTerm = LunarCalendarService.shared.getSolarTerm(for: date)
        }
    }
    
    // 是否是节假日（需要红色背景）
    private var isHoliday: Bool {
        cellData.holidayType == .holiday
    }
    
    // 是否是调休上班日
    private var isWorkday: Bool {
        cellData.holidayType == .workday
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 背景层 - 圆角8px，高度54px
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .frame(height: 54)

            // 内容层 - 使用frame(maxWidth:)确保居中
            VStack(spacing: 2) {
                // 日期数字 - 百度日历使用更大的字体
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(dateTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // 农历/节日/节气
                Text(cellData.displayText)
                    .font(.system(size: 10))
                    .foregroundStyle(festivalColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 4)
            
            // 节假日/调休标记（右上角）- 休/班徽章
            if let type = cellData.holidayType {
                HolidayBadge(type: type)
                    .offset(x: -2, y: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .help(cellData.holidayName != nil ? cellData.holidayName! : "") // hover显示完整节假日名称
        .onTapGesture {
            onTap()
        }
    }
    
    // 日期数字颜色 - 百度日历风格
    private var dateTextColor: Color {
        let calendar = Calendar.current
        let isCurrentMonth = calendar.component(.month, from: date) == calendar.component(.month, from: currentMonth)
        
        // 非当前月份的日期显示为浅灰色
        if !isCurrentMonth {
            return Color.gray.opacity(0.35)
        }
        
        // 节假日：红色
        if isHoliday {
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
        
        // 调休上班日：灰色（非黑色）
        if isWorkday {
            return Color.gray.opacity(0.7)
        }
        
        // 周末：红色
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
        
        return Color(red: 0.2, green: 0.2, blue: 0.2)
    }
    
    // 背景颜色 - 百度日历风格
    private var backgroundColor: Color {
        // 节假日：浅红色背景 #FFEBEE（更深的粉色）
        if isHoliday {
            return Color(red: 1, green: 0.92, blue: 0.93)
        }
        
        // 调休上班日：浅红色背景（与节假日相同）
        if isWorkday {
            return Color(red: 1, green: 0.92, blue: 0.93)
        }
        
        // 选中：浅蓝色背景（今天不叠加选中背景，避免亮蓝色外框）
        if isSelected && !isToday {
            return Color(red: 0.9, green: 0.95, blue: 1)
        }

        return Color.white
    }
    
    // 农历/节日颜色
    private var festivalColor: Color {
        let calendar = Calendar.current
        let isCurrentMonth = calendar.component(.month, from: date) == calendar.component(.month, from: currentMonth)
        
        // 非当前月份：浅灰色
        if !isCurrentMonth {
            return Color.gray.opacity(0.35)
        }
        
        // 节假日名称：红色
        if cellData.holidayName != nil {
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
        
        // 农历节日：红色
        if cellData.lunarFestival != nil {
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
        
        // 节气：绿色（百度日历风格）
        if cellData.solarTerm != nil {
            return Color(red: 0.2, green: 0.6, blue: 0.3)
        }
        
        // 普通农历：灰色
        return Color.gray.opacity(0.55)
    }
}

// MARK: - Preview

struct CalendarGridView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarGridView(viewModel: CalendarViewModel())
            .frame(width: 300, height: 300)
            .padding()
    }
}
