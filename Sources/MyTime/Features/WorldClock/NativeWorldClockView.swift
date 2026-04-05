import SwiftUI

// MARK: - Native World Clock View

/// 纯Swift实现的世界时钟视图 - 不使用WebView
struct NativeWorldClockView: View {
    @ObservedObject var viewModel: WorldClockViewModel
    
    // 地图服务
    private let mapService: WorldMapDataService = WorldMapDataService.shared
    
    // 交互状态
    @State private var hoveredCountryId: String?
    @State private var hoveredCountryPosition: CGPoint = .zero
    @State private var hoveredCityId: UUID?
    @State private var viewSize: CGSize = .zero
    
    // 计算属性
    private var scale: CGFloat {
        guard viewSize.width > 0, viewSize.height > 0 else { return 1.0 }
        let mapBounds = mapService.mapBounds
        
        let scaleX = viewSize.width / mapBounds.width
        let scaleY = viewSize.height / mapBounds.height
        return min(scaleX, scaleY) * 1.0
    }
    
    private var offset: CGSize {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let mapBounds = mapService.mapBounds
        
        let scaledWidth = mapBounds.width * scale
        let scaledHeight = mapBounds.height * scale
        
        let offsetX = (viewSize.width - scaledWidth) / 2 - mapBounds.minX * scale
        let offsetY = (viewSize.height - scaledHeight) / 2 - mapBounds.minY * scale
        
        // 向左移动10%，向上移动10%
        return CGSize(
            width: offsetX - viewSize.width * 0.00,
            height: offsetY - viewSize.height * 0.00
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景渐变 - 以#2a68b7为中心值上下渐变
                LinearGradient(
                    colors: [
                        Color(red: 0.65, green: 0.75, blue: 0.90),
                        Color(red: 0.45, green: 0.60, blue: 0.80),
                        Color(red: 0.30, green: 0.48, blue: 0.72),
                        Color(red: 42/255, green: 104/255, blue: 183/255),
                        Color(red: 0.30, green: 0.48, blue: 0.72),
                        Color(red: 0.45, green: 0.60, blue: 0.80),
                        Color(red: 0.65, green: 0.75, blue: 0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // 地图层
                WorldMapView(
                    mapService: mapService,
                    hoveredCountryId: hoveredCountryId,
                    selectedCountryId: nil,
                    scale: scale,
                    offset: offset,
                    onCountryHover: { countryId, position in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredCountryId = countryId
                            hoveredCountryPosition = position
                        }
                    },
                    onCountryTap: { countryId in
                        // 可以添加国家点击逻辑
                    }
                )
                
                // 昼夜分界线层（允许事件穿透）
                NightOverlayView(
                    date: viewModel.currentTime,
                    mapService: mapService,
                    scale: scale,
                    offset: offset,
                    viewSize: viewSize
                )
                .allowsHitTesting(false)
                
                // 时区高亮带（允许事件穿透）
                if let city = viewModel.cities.first(where: { $0.id == viewModel.currentCity.id }) {
                    TimezoneHighlightBand(
                        city: city,
                        currentTime: viewModel.currentTime,
                        mapService: mapService,
                        viewBounds: CGRect(origin: .zero, size: viewSize)
                    )
                    .allowsHitTesting(false)
                }
                
                // 城市标记层（zIndex确保在城市标记层在地图层之上）
                CityMarkersLayer(
                    cities: viewModel.cities,
                    currentTime: viewModel.currentTime,
                    mapService: mapService,
                    scale: scale,
                    offset: offset,
                    hoveredCityId: hoveredCityId,
                    selectedCityId: viewModel.currentCity.id,
                    onCityHover: { cityId, isHovered in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            hoveredCityId = isHovered ? cityId : nil
                        }
                    },
                    onCityTap: { cityId in
                        if let city = viewModel.cities.first(where: { $0.id == cityId }) {
                            viewModel.currentCity = city
                        }
                    }
                )
                .zIndex(10) // 确保城市标记层在地图层之上接收hover事件
                
                // 国家hover弹窗（当城市hover生效时或无时区信息时不显示）
                if let countryId = hoveredCountryId, hoveredCityId == nil {
                    if let country = mapService.countries.first(where: { $0.id == countryId }) {
                        let tzInfo = mapService.getTimezoneInfo(for: countryId)
                        // 只有存在时区信息时才显示弹窗
                        if tzInfo != nil {
                            CountryTimezonePopup(
                                countryName: country.name,
                                timezoneInfo: tzInfo,
                                currentTime: viewModel.currentTime,
                                position: calculatePopupPosition(for: hoveredCountryPosition)
                            )
                            .transition(.opacity)
                            .zIndex(100)
                        }
                    }
                }
                
                // 左下角时间面板（允许事件穿透到下层地图）
                let displayCity = hoveredCityId.flatMap { id in
                    viewModel.cities.first(where: { $0.id == id })
                } ?? viewModel.currentCity
                
                VStack {
                    Spacer()
                    HStack {
                        CurrentTimePanelView(
                            city: displayCity,
                            currentTime: viewModel.currentTime,
                            isHovered: hoveredCityId != nil
                        )
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                viewSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculatePopupPosition(for position: CGPoint) -> CGPoint {
        // 确保弹窗在视图内
        var x = position.x + 15
        var y = position.y - 50
        
        // 边界检查
        if x + 200 > viewSize.width {
            x = position.x - 215
        }
        if y < 10 {
            y = 10
        }
        if y + 150 > viewSize.height {
            y = viewSize.height - 160
        }
        
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Preview

#Preview {
    NativeWorldClockView(viewModel: WorldClockViewModel())
        .frame(width: 1000, height: 600)
}
