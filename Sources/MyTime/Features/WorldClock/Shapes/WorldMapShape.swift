import SwiftUI

// MARK: - World Map Shape

/// 世界地图Shape - 渲染所有国家多边形
struct WorldMapShape: Shape {
    let countries: [CountryPathData]
    let scale: CGFloat
    let offset: CGSize
    
    init(countries: [CountryPathData], scale: CGFloat = 1.0, offset: CGSize = .zero) {
        self.countries = countries
        self.scale = scale
        self.offset = offset
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        for country in countries {
            let countryPath = country.toScaledPath(scale: scale, offset: offset)
            path.addPath(countryPath)
        }
        
        return path
    }
}

// MARK: - Country Shape

/// 单个国家Shape - 支持独立渲染和交互
struct CountryShape: Shape {
    let country: CountryPathData
    let scale: CGFloat
    let offset: CGSize
    
    init(country: CountryPathData, scale: CGFloat = 1.0, offset: CGSize = .zero) {
        self.country = country
        self.scale = scale
        self.offset = offset
    }
    
    func path(in rect: CGRect) -> Path {
        return country.toScaledPath(scale: scale, offset: offset)
    }
}

// MARK: - World Map View

/// 世界地图视图 - 渲染所有国家并支持hover交互
struct WorldMapView: View {
    let mapService: WorldMapDataService
    let hoveredCountryId: String?
    let selectedCountryId: String?
    let scale: CGFloat
    let offset: CGSize
    let onCountryHover: (String?, CGPoint) -> Void
    let onCountryTap: (String) -> Void
    
    var body: some View {
        ZStack {
            // 渲染所有国家
            ForEach(mapService.countries) { country in
                CountryShape(country: country, scale: scale, offset: offset)
                    .fill(fillColor(for: country.id))
                    .overlay(
                        CountryShape(country: country, scale: scale, offset: offset)
                            .stroke(strokeColor(for: country.id), lineWidth: strokeWidth(for: country.id))
                    )
                    .onHover { isHovered in
                        if isHovered {
                            // 计算hover位置（使用国家中心点）
                            let center = centerPoint(for: country)
                            onCountryHover(country.id, center)
                        } else {
                            onCountryHover(nil, .zero)
                        }
                    }
                    .onTapGesture {
                        onCountryTap(country.id)
                    }
            }
        }
        .clipped() // 裁剪超出视图的部分
    }
    
    // MARK: - Styling Helpers
    
    private func fillColor(for countryId: String) -> Color {
        if countryId == selectedCountryId {
            return Color(red: 0.85, green: 0.55, blue: 0.35) // 橙色选中
        } else if countryId == hoveredCountryId {
            return Color(red: 0.75, green: 0.83, blue: 0.92) // 浅蓝高亮（更亮的灰色调）
        } else {
            return Color(red: 0.56, green: 0.77, blue: 0.97) // 默认浅蓝
        }
    }
    
    private func strokeColor(for countryId: String) -> Color {
        // 统一使用浅色边界，参考SVGMap-master: stroke: white
        return Color(red: 0.66, green: 0.82, blue: 0.98)
    }
    
    private func strokeWidth(for countryId: String) -> CGFloat {
        // 统一使用细边界，参考SVGMap-master
        return 0.5
    }
    
    private func centerPoint(for country: CountryPathData) -> CGPoint {
        let bbox = country.boundingBox
        let center = CGPoint(
            x: bbox.midX * scale + offset.width,
            y: bbox.midY * scale + offset.height
        )
        return center
    }
}

// MARK: - Map Coordinate Transform View

/// 地图坐标转换辅助视图
struct MapCoordinateTransform {
    let mapBounds: CGRect
    let viewSize: CGSize
    let scale: CGFloat
    let offset: CGSize
    
    /// 视图坐标转地图坐标
    func viewToMap(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }
    
    /// 地图坐标转视图坐标
    func mapToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.width,
            y: point.y * scale + offset.height
        )
    }
}
