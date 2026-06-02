import SwiftUI

/// 菜单栏弹窗中的日历视图 - 百度日历风格（左侧日历+右侧信息面板）
struct CalendarPopoverView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showAlmanacDetail = false
    @State private var showWorldClock = false
    
    // 主窗口宽度
    private let mainWidth: CGFloat = 500  // 340 + 160
    // 黄历子窗口宽度
    private let almanacWidth: CGFloat = 280
    
    var body: some View {
        ZStack {
            // 世界时钟视图 - 窗口大小与日历+黄历一致 (500+280=780)
            if showWorldClock {
                WorldClockPopupView(isPresented: $showWorldClock)
                    .frame(width: 780, height: 380)
                    .transition(.opacity)
            } else {
                // 日历视图
                HStack(spacing: 0) {
                    // 主窗口
                    HStack(spacing: 0) {
                        // 左侧：日历区域
                        leftCalendarView
                            .frame(width: 340)
                        
                        // 右侧：日期详情面板
                        DateDetailPanel(
                            date: viewModel.selectedDate,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAlmanacDetail = true
                                }
                            },
                            onWorldClockTap: {
                                // 先调整窗口大小，再显示世界时钟
                                NotificationCenter.default.post(
                                    name: .adjustPopoverSize,
                                    object: nil,
                                    userInfo: ["width": 780]
                                )
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showWorldClock = true
                                }
                            }
                        )
                        .frame(width: 160)
                    }
                    .frame(height: 380)
                    .background(Color.white)
                    
                    // 黄历详情子窗口（显示在主窗口右侧）
                    if showAlmanacDetail {
                        AlmanacDetailPopup(
                            date: viewModel.selectedDate,
                            isPresented: $showAlmanacDetail
                        )
                        .frame(width: almanacWidth, height: 380)
                        .transition(.move(edge: .trailing))
                    }
                }
                .onChange(of: viewModel.selectedDate) {
                    // 切换日期时关闭黄历子窗口
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAlmanacDetail = false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetPopoverContent)) { _ in
            showWorldClock = false
            showAlmanacDetail = false
        }
    }
    
    // MARK: - 左侧日历区域
    private var leftCalendarView: some View {
        VStack(spacing: 0) {
            // 星期标题
            weekdayHeaderView
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            // 日历网格
            CalendarGridView(viewModel: viewModel)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 8)
            
            // 底部：今日按钮
            footerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
    
    // MARK: - Weekday Header
    
    private var weekdayHeaderView: some View {
        HStack(spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(weekdayColor(for: index))
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var weekdaySymbols: [String] {
        // 百度日历风格：周一到周日
        return ["一", "二", "三", "四", "五", "六", "日"]
    }
    
    private func weekdayColor(for index: Int) -> Color {
        // 周六(5)和周日(6)显示红色，其他显示深灰色
        if index == 5 || index == 6 {
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
        return Color(red: 0.35, green: 0.35, blue: 0.35)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // 今日按钮
            Button(action: goToToday) {
                Text("今日")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func goToToday() {
        viewModel.currentDate = Date()
    }
}

// MARK: - 右侧日期详情面板

struct DateDetailPanel: View {
    let date: Date
    let onTap: () -> Void
    let onWorldClockTap: () -> Void
    
    init(date: Date, onTap: @escaping () -> Void, onWorldClockTap: @escaping () -> Void) {
        self.date = date
        self.onTap = onTap
        self.onWorldClockTap = onWorldClockTap
    }
    
    private var lunarInfo: LunarInfo {
        LunarCalendarService.shared.getLunarInfo(for: date)
    }
    
    private var almanac: AlmanacData {
        LunarCalendarService.shared.getAlmanacInfo(for: date)
    }
    
    private var holidayName: String? {
        HolidayService.shared.getHolidayName(for: date)
    }
    
    private var isHoliday: Bool {
        HolidayService.shared.getHolidayType(for: date) == .holiday
    }
    
    // 当前时区名称（中文）
    private var timeZoneName: String {
        let tz = TimeZone.current
        return CityDataService.shared.getLocalizedName(forTimezone: tz.identifier)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 上半部分：日期信息区（彩色背景）
            topDateSection
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(headerBackgroundColor)
                .foregroundColor(.white)
            
            // 下半部分：宜忌区（彩色背景）
            VStack(alignment: .leading, spacing: 0) {
                yiJiSection
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(bottomBackgroundColor)
            .foregroundColor(.white)
            .contentShape(Rectangle()) // 确保整个区域可点击
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                onTap()
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // 上半部分背景色（日期信息区）
    private var headerBackgroundColor: Color {
        isHoliday 
            ? Color(red: 235/255, green: 55/255, blue: 56/255)  // 节假日: rgb(235, 55, 56)
            : Color(red: 77/255, green: 111/255, blue: 239/255) // 正常日: #4d6fef
    }
    
    // 下半部分背景色（宜忌区）
    private var bottomBackgroundColor: Color {
        isHoliday
            ? Color(red: 239/255, green: 86/255, blue: 86/255)   // 节假日: rgb(239, 86, 86)
            : Color(red: 106/255, green: 133/255, blue: 245/255) // 正常日: #6a85f5
    }
    
    // MARK: - 顶部日期区域
    private var topDateSection: some View {
        VStack(spacing: 8) {
            // 日期：2022-01-01 格式
            Text(dateString)
                .font(.system(size: 12))
                .opacity(0.9)
            
            // 时间显示（点击可切换到世界时钟）- 使用 TimelineView 替代手动 Timer
            Button(action: {
                onWorldClockTap()
            }) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 4) {
                        // 大号时间数字
                        Text(DateFormatterCache.formatter(format: "HH:mm").string(from: context.date))
                            .font(.system(size: 30, weight: .light))
                        
                        // 地点图标 + 时区名称
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            Text(timeZoneName)
                                .font(.system(size: 10))
                        }
                        .opacity(0.85)
                    }
                }
                .frame(width: 90, height: 75)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .contentShape(Rectangle())
            .cornerRadius(12)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            // 农历日期
            
            HStack(spacing: 6) {
                Text("\(lunarInfo.lunarMonth)\(lunarInfo.lunarDay)")
                    .font(.system(size: 14))
                    .opacity(0.95)
                // 生肖年
                Text("\(lunarInfo.zodiac)年")
                    .font(.system(size: 11))
                    .opacity(0.8)
            }
            
            // 干支五行（年柱 | 月柱 | 日柱）
            HStack(spacing: 6) {
                Text(lunarInfo.ganZhiYear)
                    .font(.system(size: 11, weight: .medium))
                Text("|")
                    .font(.system(size: 10))
                    .opacity(0.5)
                Text(lunarInfo.ganZhiMonth)
                    .font(.system(size: 11, weight: .medium))
                Text("|")
                    .font(.system(size: 10))
                    .opacity(0.5)
                Text(lunarInfo.ganZhiDay)
                    .font(.system(size: 11, weight: .medium))
            }
            .opacity(0.85)
            
    
            
            // 节假日名称（如果有）
            if let holiday = holidayName {
                Text("• \(holiday)")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - 宜忌区域
    private var yiJiSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // 宜
            VStack(alignment: .center, spacing: 6) {
                Text("宜")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                
                // 使用2列网格显示宜事项
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                    ForEach(almanac.yi.prefix(8), id: \.self) { item in
                        Text(item)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // 忌
            VStack(alignment: .center, spacing: 6) {
                Text("忌")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                
                // 使用2列网格显示忌事项
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                    ForEach(almanac.ji.prefix(8), id: \.self) { item in
                        Text(item)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var dateString: String {
        DateFormatterCache.formatter(format: "yyyy-MM-dd").string(from: date)
    }
}

// MARK: - Preview

struct CalendarPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarPopoverView()
            .frame(width: 320, height: 400)
    }
}


