import SwiftUI
import MapKit

// MARK: - 世界时钟弹窗视图

struct WorldClockPopupView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var viewModel = WorldClockViewModel.shared
    @State private var selectedCity: WorldCity?
    @State private var hoveredCity: WorldCity?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 纯Swift实现的世界时钟视图
                NativeWorldClockView(viewModel: viewModel)
                
                // 顶部控制栏
                TopControlBar(isPresented: $isPresented)
            }
        }
        .onAppear {
            viewModel.startTimer()
            // 打开时确保地图数据就绪（幂等；启动时不再预加载，降低静置内存）
            Task { await WorldMapDataService.shared.ensureLoaded() }
        }
        .onDisappear {
            viewModel.stopTimer()
        }
    }
}

// MARK: - 当前时间面板

struct CurrentTimePanel: View {
    let city: WorldCity
    let currentTime: Date
    let isHovered: Bool
    
    private var timeString: String {
        DateFormatterCache.formatter(format: "HH:mm:ss", timeZone: city.timeZone).string(from: currentTime)
    }
    
    private var dateString: String {
        DateFormatterCache.formatter(format: "yyyy-MM-dd", timeZone: city.timeZone).string(from: currentTime)
    }
    
    private var utcOffsetString: String {
        let timeZone = city.timeZone
        let offset = timeZone.secondsFromGMT(for: currentTime)
        let hours = offset / 3600
        let minutes = abs(offset % 3600) / 60
        
        if minutes == 0 {
            return "UTC\(hours >= 0 ? "+" : "")\(hours)"
        } else {
            return "UTC\(hours >= 0 ? "+" : "")\(hours):\(String(format: "%02d", minutes))"
        }
    }
    
    private var dstString: String {
        let timeZone = city.timeZone
        let isDST = timeZone.isDaylightSavingTime(for: currentTime)
        return isDST ? "夏令时" : "冬令时"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeString)
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(isHovered ? Color(red: 0.902, green: 0.494, blue: 0.133) : .white)
            
            Text("\(city.localizedName), \(city.country)")
                .font(.system(size: 13))
                .opacity(0.9)
            
            HStack(spacing: 8) {
                Text(utcOffsetString)
                Text("·")
                Text(dstString)
            }
            .font(.system(size: 12))
            .opacity(0.8)
            
            Text(dateString)
                .font(.system(size: 11))
                .opacity(0.7)
        }
        .foregroundColor(.white)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.118, green: 0.341, blue: 0.600))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - 顶部控制栏

struct TopControlBar: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // 返回按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPresented = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                
                Spacer()
            }
            .padding(.vertical, 10)
            
            Spacer()
        }
    }
}

// MARK: - ViewModel

@MainActor
class WorldClockViewModel: ObservableObject {
    static let shared = WorldClockViewModel()
    
    @Published var currentTime = Date()
    @Published var currentCity: WorldCity
    
    let cities: [WorldCity]
    
    nonisolated(unsafe) private var timer: Timer?
    
    private init() {
        // 使用 CityDataService 获取城市数据
        let cityService = CityDataService.shared
        self.cities = cityService.cities
        self.currentCity = cityService.getCurrentCity()
    }
    
    func startTimer() {
        guard timer == nil else { return }
        currentTime = Date()
        // 计算到下一个整分钟的延迟
        let seconds = Calendar.current.component(.second, from: Date())
        let delay = max(1, TimeInterval(60 - seconds))
        // 先等到整分钟，再每60秒更新（地图/昼夜等组件不需要秒级刷新）
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = Date()
                self?.timer?.invalidate()
                self?.timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.currentTime = Date()
                    }
                }
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        timer?.invalidate()
    }
}
