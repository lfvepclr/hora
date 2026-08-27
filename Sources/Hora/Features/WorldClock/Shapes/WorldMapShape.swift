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

/// 世界地图视图 - Canvas 绘制预构建的矢量路径（内存友好的矢量渲染，无损缩放）
struct WorldMapView: View {
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    
    var body: some View {
        if let mapPath = mapService.cachedMapPath {
            Canvas { context, _ in
                // 视图坐标 = 地图坐标 × scale + offset
                let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                                  tx: offset.width, ty: offset.height)
                let viewPath = Path(mapPath).applying(transform)
                context.fill(viewPath, with: .color(Color(red: 0.56, green: 0.77, blue: 0.97)))
                context.stroke(viewPath, with: .color(Color(red: 0.35, green: 0.55, blue: 0.78)),
                               lineWidth: 0.5 / scale)
            }
        } else if !mapService.countries.isEmpty {
            // 回退：路径还未构建时使用 Shape
            WorldMapShape(countries: mapService.countries, scale: scale, offset: offset)
                .fill(Color(red: 0.56, green: 0.77, blue: 0.97))
                .overlay(
                    WorldMapShape(countries: mapService.countries, scale: scale, offset: offset)
                        .stroke(Color(red: 0.35, green: 0.55, blue: 0.78), lineWidth: 0.5)
                )
                .clipped()
        }
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
