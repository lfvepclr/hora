import SwiftUI

struct CalendarContainerView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showAlmanacDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            CalendarHeaderView(viewModel: viewModel)
            
            if viewModel.isYearView {
                YearView(viewModel: viewModel)
            } else {
                MonthView(viewModel: viewModel, onDateDoubleTap: { date in
                    viewModel.selectedDate = date
                    if viewModel.shouldShowAlmanacSummary {
                        showAlmanacDetail = true
                    }
                })
            }
            
            if viewModel.shouldShowAlmanacSummary {
                AlmanacSummaryView(date: viewModel.selectedDate)
                    .frame(height: 80)
                    .background(Color.secondary.opacity(0.1))
                    .onTapGesture {
                        showAlmanacDetail = true
                    }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .sheet(isPresented: $showAlmanacDetail) {
            AlmanacDetailView(date: viewModel.selectedDate)
                .frame(minWidth: 700, minHeight: 600)
        }
    }
}

struct CalendarHeaderView: View {
    @ObservedObject var viewModel: CalendarViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: { viewModel.goToToday() }) {
                Text("Today")
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 8) {
                Button(action: { viewModel.previousMonth() }) {
                    Image(systemName: "chevron.left")
                }
                
                Text(viewModel.headerTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(minWidth: 150)
                
                Button(action: { viewModel.nextMonth() }) {
                    Image(systemName: "chevron.right")
                }
            }
            
            Spacer()
            
            Picker("View", selection: $viewModel.isYearView) {
                Image(systemName: "calendar").tag(false)
                Image(systemName: "square.grid.2x2").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding()
    }
}

class CalendarViewModel: ObservableObject {
    @Published var currentDate = Date()
    @Published var selectedDate = Date()
    @Published var isYearView = false
    
    var headerTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = isYearView ? "yyyy" : "MMMM yyyy"
        return formatter.string(from: currentDate)
    }
    
    var navigationTitle: String {
        isYearView ? "Year View" : "Calendar"
    }
    
    var shouldShowAlmanacSummary: Bool {
        // 仅在中国时区显示黄历摘要
        let timezone = TimeZone.current.identifier
        return timezone.contains("Shanghai") || timezone.contains("Beijing") || timezone.contains("Hong_Kong")
    }
    
    func goToToday() {
        currentDate = Date()
        selectedDate = Date()
    }
    
    func previousMonth() {
        currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
    }
    
    func nextMonth() {
        currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
    }
}

struct MonthView: View {
    @ObservedObject var viewModel: CalendarViewModel
    var onDateDoubleTap: ((Date) -> Void)?
    
    let columns = Array(repeating: GridItem(.flexible()), count: 7)
    let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            HStack {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth(), id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                        isToday: Calendar.current.isDateInToday(date)
                    )
                    .onTapGesture {
                        viewModel.selectedDate = date
                    }
                }
            }
        }
        .padding()
    }
    
    private func daysInMonth() -> [Date] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: viewModel.currentDate) else {
            return []
        }
        
        var dates: [Date] = []
        var date = monthInterval.start
        
        // Add leading days from previous month
        let weekday = Calendar.current.component(.weekday, from: date)
        for i in 1..<weekday {
            if let prevDate = Calendar.current.date(byAdding: .day, value: -i, to: date) {
                dates.insert(prevDate, at: 0)
            }
        }
        
        // Add days in current month
        while date < monthInterval.end {
            dates.append(date)
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        // Add trailing days to fill grid
        while dates.count % 7 != 0 {
            dates.append(date)
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        return dates
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    
    private var lunarInfo: LunarInfo {
        LunarCalendarService.shared.getLunarInfo(for: date)
    }
    
    private var holidayType: HolidayType? {
        HolidayService.shared.getHolidayType(for: date)
    }
    
    private var displayText: String {
        // 优先显示农历节日
        if let festival = LunarCalendarService.shared.getLunarFestival(for: date) {
            return festival
        }
        // 然后显示节气
        if let solarTerm = LunarCalendarService.shared.getSolarTerm(for: date) {
            return solarTerm
        }
        return lunarInfo.lunarDay
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(textColor)
                
                Text(displayText)
                    .font(.system(size: 9))
                    .foregroundStyle(festivalColor)
                    .lineLimit(1)
            }
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
            
            // 节假日/调休标记
            if let type = holidayType {
                HolidayBadge(type: type)
                    .offset(x: -4, y: 4)
            }
        }
    }
    
    private var textColor: Color {
        let weekday = Calendar.current.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { // 周日或周六
            return .red
        }
        return .primary
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        }
        if holidayType == .holiday {
            return Color.red.opacity(0.1)
        }
        return Color.clear
    }
    
    private var festivalColor: Color {
        if holidayType == .holiday {
            return .red
        }
        if LunarCalendarService.shared.getLunarFestival(for: date) != nil {
            return .red
        }
        if LunarCalendarService.shared.getSolarTerm(for: date) != nil {
            return .green
        }
        return .secondary
    }
}

struct HolidayBadge: View {
    let type: HolidayType
    
    var body: some View {
        Text(type == .holiday ? "休" : "班")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 15, height: 15)
            .background(type == .holiday ? Color(red: 0.95, green: 0.25, blue: 0.25) : Color(red: 0.55, green: 0.55, blue: 0.55))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

struct YearView: View {
    @ObservedObject var viewModel: CalendarViewModel
    
    let columns = Array(repeating: GridItem(.flexible()), count: 4)
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12) { month in
                    MonthThumbnailView(
                        year: Calendar.current.component(.year, from: viewModel.currentDate),
                        month: month + 1
                    )
                    .onTapGesture {
                        viewModel.currentDate = Calendar.current.date(
                            from: DateComponents(year: Calendar.current.component(.year, from: viewModel.currentDate), month: month + 1)
                        ) ?? viewModel.currentDate
                        viewModel.isYearView = false
                    }
                }
            }
            .padding()
        }
    }
}

struct MonthThumbnailView: View {
    let year: Int
    let month: Int
    
    var body: some View {
        VStack {
            Text(Calendar.current.monthSymbols[month - 1])
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 2) {
                ForEach(1..<32) { day in
                    Text("\(day)")
                        .font(.caption2)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct AlmanacSummaryView: View {
    let date: Date
    
    private var almanac: AlmanacData {
        LunarCalendarService.shared.getAlmanacInfo(for: date)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("宜:")
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                    Text(almanac.yiDisplay)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("忌:")
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                    Text(almanac.jiDisplay)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .font(.callout)
            
            Spacer()
            
            Button("查看黄历") {
                // Navigate to almanac detail
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal)
    }
}
