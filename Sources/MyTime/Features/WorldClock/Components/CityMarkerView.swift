import SwiftUI

// MARK: - City Marker View

/// 城市标记视图 - 显示城市圆点和时间标签
struct CityMarkerView: View {
    let city: WorldCity
    let currentTime: Date
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    let isHovered: Bool
    let isSelected: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    
    private var mapPosition: CGPoint? {
        mapService.latLonToMapPoint(latitude: city.latitude, longitude: city.longitude)
    }
    
    private var viewPosition: CGPoint? {
        guard let pos = mapPosition else { return nil }
        return CGPoint(
            x: pos.x * scale + offset.width,
            y: pos.y * scale + offset.height
        )
    }
    
    private var timeString: String {
        let formatter = DateFormatterCache.formatter(format: "HH:mm", timeZone: city.timeZone)
        return formatter.string(from: currentTime)
    }
    
    var body: some View {
        if let position = viewPosition {
            // 使用offset定位，确保hover检测区域能正确工作
            ZStack {
                // Hover检测区域（透明的大圆形）
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 14, height: 14)
                    .contentShape(Circle())
                    .onHover { hovering in
                        onHover(hovering)
                    }
                    .onTapGesture {
                        onTap()
                    }
                
                // 城市内容
                ZStack {
                    // 时间标签（显示在圆点上方）
                    if city.isMajor || isSelected || isHovered {
                        TimeLabelBubble(
                            cityName: city.localizedName,
                            timeString: timeString,
                            isMajor: city.isMajor,
                            isSelected: isSelected
                        )
                        .offset(y: -16)
                        .transition(.opacity)
                    }
                    
                    // 城市圆点
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isSelected ? 1 : 0.6), lineWidth: isSelected ? 1.5 : 0.5)
                        )
                        .shadow(
                            color: isSelected ? Color.orange.opacity(0.6) : Color.white.opacity(0.4),
                            radius: isSelected ? 4 : 2
                        )
                }
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .allowsHitTesting(false) // 让内容层不拦截事件
            }
            .position(position)
            .zIndex(isSelected ? 2 : (isHovered ? 1 : 0))
        }
    }
    
    private var dotColor: Color {
        if isSelected {
            return Color(red: 0.902, green: 0.494, blue: 0.133) // 橙色选中
        } else if isHovered {
            return Color(red: 1.0, green: 0.7, blue: 0.4) // 浅橙hover
        } else {
            return .white
        }
    }
    
    private var dotSize: CGFloat {
        if isSelected {
            return 8
        } else if isHovered {
            return 7
        } else {
            return 5
        }
    }
}

// MARK: - City Markers Layer

/// 城市标记层 - 渲染所有城市标记
struct CityMarkersLayer: View {
    let cities: [WorldCity]
    let currentTime: Date
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    let hoveredCityId: UUID?
    let selectedCityId: UUID?
    let onCityHover: (UUID?, Bool) -> Void
    let onCityTap: (UUID) -> Void
    
    var body: some View {
        ZStack {
            ForEach(cities) { city in
                CityMarkerView(
                    city: city,
                    currentTime: currentTime,
                    mapService: mapService,
                    scale: scale,
                    offset: offset,
                    isHovered: hoveredCityId == city.id,
                    isSelected: selectedCityId == city.id,
                    onHover: { isHovered in
                        onCityHover(city.id, isHovered)
                    },
                    onTap: {
                        onCityTap(city.id)
                    }
                )
            }
        }
    }
}

// MARK: - Major Cities Layer

/// 热门城市层 - 始终显示标签的城市
struct MajorCitiesLayer: View {
    let cities: [WorldCity]
    let currentTime: Date
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    let selectedCityId: UUID?
    
    private var majorCities: [WorldCity] {
        cities.filter { $0.isMajor }
    }
    
    var body: some View {
        ZStack {
            ForEach(majorCities) { city in
                MajorCityMarker(
                    city: city,
                    currentTime: currentTime,
                    mapService: mapService,
                    scale: scale,
                    offset: offset,
                    isSelected: selectedCityId == city.id
                )
            }
        }
    }
}

/// 热门城市标记（带城市名）
struct MajorCityMarker: View {
    let city: WorldCity
    let currentTime: Date
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    let isSelected: Bool
    
    private var mapPosition: CGPoint? {
        mapService.latLonToMapPoint(latitude: city.latitude, longitude: city.longitude)
    }
    
    private var viewPosition: CGPoint? {
        guard let pos = mapPosition else { return nil }
        return CGPoint(
            x: pos.x * scale + offset.width,
            y: pos.y * scale + offset.height
        )
    }
    
    private var timeString: String {
        let formatter = DateFormatterCache.formatter(format: "HH:mm", timeZone: city.timeZone)
        return formatter.string(from: currentTime)
    }
    
    var body: some View {
        if let position = viewPosition {
            ZStack {
                // 城市名和时间标签（一行显示）
                TimeLabelBubble(
                    cityName: city.localizedName,
                    timeString: timeString,
                    isMajor: true,
                    isSelected: isSelected
                )
                .offset(y: -16)
                
                // 城市圆点
                Circle()
                    .fill(isSelected ? Color(red: 0.902, green: 0.494, blue: 0.133) : .white)
                    .frame(width: isSelected ? 8 : 5, height: isSelected ? 8 : 5)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
                    )
                    .shadow(color: isSelected ? Color.orange.opacity(0.6) : Color.white.opacity(0.5), radius: 2)
            }
            .position(position)
        }
    }
}

// MARK: - Timezone Highlight Band

/// 时区高亮带 - 显示当前时区的垂直光带
struct TimezoneHighlightBand: View {
    let city: WorldCity
    let currentTime: Date
    let mapService: WorldMapDataService
    let viewBounds: CGRect
    
    private var longitude: Double {
        city.longitude
    }
    
    private var bandX: CGFloat? {
        guard let pos = mapService.latLonToMapPoint(latitude: 0, longitude: longitude) else {
            return nil
        }
        return pos.x
    }
    
    var body: some View {
        if let x = bandX {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.15),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 80)
                .frame(maxHeight: .infinity)
                .position(x: x, y: viewBounds.midY)
                .allowsHitTesting(false)
        }
    }
}
