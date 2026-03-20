import SwiftUI
import MapKit

// MARK: - 世界时钟弹窗视图

struct WorldClockPopupView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = WorldClockViewModel()
    @State private var selectedCity: WorldCity?
    @State private var hoveredCity: WorldCity?
    @State private var isFullscreen = false
    @State private var fullscreenWindow: NSWindow?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 渐变背景 - 24timezones.com 风格
                LinearGradient(
                    colors: [
                        Color(red: 0.102, green: 0.290, blue: 0.478),
                        Color(red: 0.051, green: 0.165, blue: 0.290)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // MapKit 视图
                WorldClockMapView(viewModel: viewModel)
                
                // 顶部控制栏
                TopControlBar(
                    isPresented: $isPresented,
                    isFullscreen: $isFullscreen,
                    fullscreenWindow: $fullscreenWindow,
                    viewModel: viewModel
                )
            }
        }
    }
}

// MARK: - 当前时间面板

struct CurrentTimePanel: View {
    let city: WorldCity
    let currentTime: Date
    let isHovered: Bool
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: currentTime)
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
    @Binding var isFullscreen: Bool
    @Binding var fullscreenWindow: NSWindow?
    @ObservedObject var viewModel: WorldClockViewModel
    
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
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                
                Spacer()
                
                // 全屏按钮
                Button(action: toggleFullscreen) {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(isFullscreen ? "退出全屏" : "全屏显示")
                .padding(.trailing, 16)
            }
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.3))
            
            Spacer()
        }
    }
    
    private func toggleFullscreen() {
        if isFullscreen {
            fullscreenWindow?.close()
            fullscreenWindow = nil
            isFullscreen = false
        } else {
            let contentView = NSHostingView(rootView: FullscreenWorldClockView(
                viewModel: viewModel,
                onClose: {
                    fullscreenWindow?.close()
                    fullscreenWindow = nil
                    isFullscreen = false
                }
            ))
            
            let window = NSWindow(
                contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "世界时钟"
            window.contentView = contentView
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
            
            fullscreenWindow = window
            isFullscreen = true
        }
    }
}

// MARK: - 全屏视图

struct FullscreenWorldClockView: View {
    @ObservedObject var viewModel: WorldClockViewModel
    let onClose: () -> Void
    @State private var selectedCity: WorldCity?
    @State private var hoveredCity: WorldCity?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.102, green: 0.290, blue: 0.478),
                        Color(red: 0.051, green: 0.165, blue: 0.290)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                WorldClockMapView(viewModel: viewModel)
                
                // 关闭按钮
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                    }
                    Spacer()
                }
            }
        }
        .background(Color.black)
    }
}

// MARK: - ViewModel

@MainActor
class WorldClockViewModel: ObservableObject {
    @Published var currentTime = Date()
    @Published var currentCity: WorldCity
    
    let cities: [WorldCity]
    
    nonisolated(unsafe) private var timer: Timer?
    
    init() {
        // 使用 CityDataService 获取城市数据
        let cityService = CityDataService.shared
        self.cities = cityService.cities
        self.currentCity = cityService.getCurrentCity()
        
        // 启动定时器 - 每秒更新
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = Date()
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
