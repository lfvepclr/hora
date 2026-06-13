import SwiftUI
import MapKit

// MARK: - MapKit World Clock View

struct WorldClockMapView: View {
    @ObservedObject var viewModel: WorldClockViewModel
    @State private var selectedCity: WorldCity?
    @State private var hoveredCity: WorldCity?
    @State private var cameraPosition: MapCameraPosition
    
    init(viewModel: WorldClockViewModel) {
        self.viewModel = viewModel
        
        // 获取默认城市作为地图中心
        let defaultCity = CityDataService.shared.defaultCity
        let centerCoordinate = defaultCity.map { 
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        
        // 以默认城市为中心，设置合适的缩放级别
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
        )))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // MapKit 地图
                Map(position: $cameraPosition) {
                    ForEach(viewModel.cities) { city in
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)) {
                            CityMarkerAnnotation(
                                city: city,
                                currentTime: viewModel.currentTime,
                                isCurrentCity: city.id == viewModel.currentCity.id,
                                isHovered: hoveredCity?.id == city.id,
                                onHover: { isHovered in
                                    hoveredCity = isHovered ? city : nil
                                },
                                onTap: {
                                    selectedCity = city
                                }
                            )
                        }
                    }
                }
                .allowsHitTesting(true)
                
                // 左下角当前时区面板
                CurrentTimePanel(
                    city: hoveredCity ?? viewModel.currentCity,
                    currentTime: viewModel.currentTime,
                    isHovered: hoveredCity != nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(16)
            }
        }
    }
}

// MARK: - 城市标记注解

struct CityMarkerAnnotation: View {
    let city: WorldCity
    let currentTime: Date
    let isCurrentCity: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: currentTime)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // 标签 - 热门城市或当前城市始终显示
            if city.isMajor || isCurrentCity || isHovered {
                HStack(spacing: 4) {
                    Text(city.localizedName)
                    Text(timeString)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isCurrentCity || isHovered ? 
                              Color(red: 0.902, green: 0.494, blue: 0.133) : 
                              Color(red: 0.2, green: 0.2, blue: 0.2, opacity: 0.85))
                )
                .offset(y: -12)
            }
            
            // 定位点
            Circle()
                .fill(isCurrentCity ? Color(red: 0.902, green: 0.494, blue: 0.133) : Color.white)
                .frame(width: isCurrentCity ? 8 : 5, height: isCurrentCity ? 8 : 5)
                .shadow(color: isCurrentCity ? Color.orange.opacity(0.6) : Color.white.opacity(0.4), radius: 2)
        }
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onTap()
        }
    }
}
