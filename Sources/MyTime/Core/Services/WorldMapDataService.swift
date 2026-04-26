import Foundation
import SwiftUI
import CoreGraphics

// MARK: - World Map Data Service

/// 世界地图数据服务 - 管理地图数据加载和坐标转换
@MainActor
class WorldMapDataService {
    static let shared = WorldMapDataService()
    
    // MARK: - Properties
    
    /// 地图数据（加载后释放）
    private var mapData: WorldMapData?
    
    /// 坐标转换参数
    private(set) var transform: HCTransform?
    
    /// 已处理的国家路径数据（包含Path坐标）
    private(set) var countries: [CountryPathData] = []
    
    /// 国家时区映射
    private(set) var countryTimezones: [String: CountryTimezoneInfo] = [:]
    
    /// 地图边界（所有国家的union）
    private(set) var mapBounds: CGRect = .null
    
    /// Y坐标翻转中点（用于坐标系转换）
    private(set) var yMid: CGFloat = 0
    
    /// 地球半径（米）- Miller投影使用等面积半径
    private let R_A: Double = 6371007.2
    
    /// 数据是否已加载
    private var isLoaded = false
    
    /// 是否正在加载（防止重复加载）
    private var isLoading = false
    
    // MARK: - Initialization
    
    private init() {
        // 延迟加载：不在init中加载数据
    }
    
    // MARK: - Lifecycle
    
    /// 确保数据已加载（世界时钟打开时调用）
    func ensureLoaded() async {
        guard !isLoaded && !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        await loadMapData()
        await loadCountryTimezones()
        isLoaded = true
    }
    
    /// 释放地图数据（世界时钟关闭时调用）
    func unload() {
        countries = []
        countryTimezones = [:]
        mapBounds = .null
        transform = nil
        yMid = 0
        isLoaded = false
    }
    
    // MARK: - Data Loading
    
    private func loadMapData() async {
        // 从Bundle.module加载world.json
        guard let url = Bundle.module.url(forResource: "world", withExtension: "json") else {
            print("ERROR: world.json not found in bundle")
            return
        }
        
        let loadedMapData = await Task.detached(priority: .userInitiated) { () -> WorldMapData? in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                return try decoder.decode(WorldMapData.self, from: data)
            } catch {
                print("ERROR loading world.json: \(error)")
                return nil
            }
        }.value
        
        guard let mapData = loadedMapData else { return }
        self.mapData = mapData
        self.transform = mapData.defaultTransform
        
        // 处理国家数据，转换为Path坐标
        processCountries()
        
        // 释放原始解码数据，只保留处理后的countries
        self.mapData = nil
        
        print("Loaded \(countries.count) countries from world.json")
    }
    
    private func loadCountryTimezones() async {
        guard let url = Bundle.module.url(forResource: "countryTimezones", withExtension: "json") else {
            print("WARN: countryTimezones.json not found, using default mapping")
            generateDefaultTimezoneMapping()
            return
        }
        
        let timezoneInfos = await Task.detached(priority: .userInitiated) { () -> [CountryTimezoneInfo]? in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                return try decoder.decode([CountryTimezoneInfo].self, from: data)
            } catch {
                print("ERROR loading countryTimezones.json: \(error)")
                return nil
            }
        }.value
        
        guard let infos = timezoneInfos else {
            generateDefaultTimezoneMapping()
            return
        }
        
        for info in infos {
            countryTimezones[info.countryCode] = info
        }
        
        print("Loaded timezone info for \(countryTimezones.count) countries")
    }
    
    /// 生成默认的时区映射（基于cities24tz.json）
    private func generateDefaultTimezoneMapping() {
        // 从cities24tz.json构建国家->时区映射
        guard let url = Bundle.module.url(forResource: "cities24tz", withExtension: "json") else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            if let cities = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var mapping: [String: [String: Set<String>]] = [:] // countryCode -> [timezone -> cities]
                
                for city in cities {
                    guard let name = city["name"] as? String,
                          let tz = city["tz"] as? String else { continue }
                    
                    // 解析国家名称（格式："City, Country"）
                    let parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count >= 2 {
                        let countryName = parts[1]
                        // 简单映射：使用国家名首字母作为key（后续可以改进）
                        let key = String(countryName.prefix(2)).uppercased()
                        if mapping[key] == nil {
                            mapping[key] = [:]
                        }
                        if mapping[key]?[tz] == nil {
                            mapping[key]?[tz] = []
                        }
                    }
                }
            }
        } catch {
            print("ERROR generating default timezone mapping: \(error)")
        }
    }
    
    // MARK: - Country Processing
    
    private func processCountries() {
        guard let features = mapData?.features else { return }
        
        countries = []
        var allBounds: CGRect = .null
        
        // 第一遍：找到Y的范围（内联计算，无额外函数调用）
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        for feature in features {
            let polygons = feature.geometry.coordinates.allPolygons()
            for polygon in polygons {
                for coord in polygon {
                    if coord.count >= 2 {
                        let y = CGFloat(coord[1])
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
            }
        }
        
        // 计算Y翻转的中点
        yMid = (minY + maxY) / 2
        
        // 第二遍：处理并翻转Y坐标（内联，减少函数调用开销）
        for feature in features {
            var pathPoints: [[CGPoint]] = []
            var allPoints: [CGPoint] = []
            
            let polygons = feature.geometry.coordinates.allPolygons()
            for polygon in polygons {
                var points: [CGPoint] = []
                for coord in polygon {
                    if coord.count >= 2 {
                        let x = CGFloat(coord[0])
                        let y = CGFloat(coord[1])
                        let flippedY = 2 * yMid - y
                        let point = CGPoint(x: x, y: flippedY)
                        points.append(point)
                        allPoints.append(point)
                    }
                }
                if !points.isEmpty {
                    pathPoints.append(points)
                }
            }
            
            let boundingBox = allPoints.reduce(CGRect.null) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }
            
            let pathData = CountryPathData(
                id: feature.id,
                name: feature.name,
                pathPoints: pathPoints,
                boundingBox: boundingBox
            )
            countries.append(pathData)
            allBounds = allBounds.union(pathData.boundingBox)
        }
        
        mapBounds = allBounds
    }
    
    // MARK: - Coordinate Conversion
    
    /// 将经纬度转换为地图坐标（Miller投影 -> Highcharts JSON坐标）
    func latLonToMapPoint(latitude: Double, longitude: Double) -> CGPoint? {
        guard let transform = transform else { return nil }
        
        // Miller投影
        let lonRad = longitude * .pi / 180
        let latRad = latitude * .pi / 180
        
        // Miller投影公式
        let xProj = R_A * lonRad
        let yProj = R_A * 1.25 * log(tan(.pi / 4 + 0.4 * latRad))
        
        // 转换为Highcharts JSON坐标
        let s = transform.scale
        let jr = transform.jsonres
        let mx = transform.jsonmarginX
        let my = transform.jsonmarginY
        let xoff = transform.xoffset
        let yoff = transform.yoffset
        
        let jx = (xProj - xoff) * s * jr + mx
        let jy = my - (yoff - yProj) * s * jr
        
        // 翻转Y坐标以匹配SwiftUI坐标系
        let flippedY = 2 * yMid - CGFloat(jy)
        
        return CGPoint(x: CGFloat(jx), y: flippedY)
    }
    
    /// 将地图坐标转换为经纬度
    func mapPointToLatLon(point: CGPoint) -> (lat: Double, lon: Double)? {
        guard let transform = transform else { return nil }
        
        let s = transform.scale
        let jr = transform.jsonres
        let mx = transform.jsonmarginX
        let my = transform.jsonmarginY
        let xoff = transform.xoffset
        let yoff = transform.yoffset
        
        // 逆转换Highcharts JSON坐标到投影坐标
        let xProj = (Double(point.x) - mx) / (s * jr) + xoff
        let yProj = yoff - (Double(point.y) - my) / (s * jr)
        
        // 逆Miller投影
        let lonRad = xProj / R_A
        let lon = lonRad * 180 / .pi
        
        // y = R_A * 1.25 * ln(tan(π/4 + 0.4*lat_rad))
        // ln(tan(π/4 + 0.4*lat_rad)) = y / (R_A * 1.25)
        let t = yProj / (R_A * 1.25)
        let latRad = 2.5 * (atan(exp(t)) - .pi / 4)
        let lat = latRad * 180 / .pi
        
        return (lat: lat, lon: lon)
    }
    
    // MARK: - Timezone Helpers
    
    /// 获取国家的时区信息
    func getTimezoneInfo(for countryCode: String) -> CountryTimezoneInfo? {
        return countryTimezones[countryCode]
    }
    
    /// 根据位置查找国家
    func findCountry(at point: CGPoint) -> CountryPathData? {
        // 先用边界框过滤
        let candidates = countries.filter { $0.boundingBox.contains(point) }
        
        // 再用点在多边形检测
        for country in candidates {
            if isPointInCountry(point, country: country) {
                return country
            }
        }
        
        return nil
    }
    
    /// 点是否在国家多边形内
    private func isPointInCountry(_ point: CGPoint, country: CountryPathData) -> Bool {
        for polygon in country.pathPoints {
            if isPointInPolygon(point, polygon: polygon) {
                return true
            }
        }
        return false
    }
    
    /// 射线法判断点是否在多边形内
    private func isPointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            
            if ((pi.y > point.y) != (pj.y > point.y)) &&
               (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
}

// MARK: - Country Path Data

/// 国家路径数据（已处理，可直接用于SwiftUI Path）
struct CountryPathData: Identifiable {
    let id: String
    let name: String
    let pathPoints: [[CGPoint]]
    let boundingBox: CGRect
    
    /// 创建SwiftUI Path
    func toPath() -> Path {
        var path = Path()
        
        for polygon in pathPoints {
            guard let first = polygon.first else { continue }
            path.move(to: first)
            for point in polygon.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        
        return path
    }
    
    /// 创建缩放后的Path
    func toScaledPath(scale: CGFloat, offset: CGSize) -> Path {
        var path = Path()
        
        for polygon in pathPoints {
            guard let first = polygon.first else { continue }
            let scaledFirst = CGPoint(
                x: first.x * scale + offset.width,
                y: first.y * scale + offset.height
            )
            path.move(to: scaledFirst)
            
            for point in polygon.dropFirst() {
                let scaledPoint = CGPoint(
                    x: point.x * scale + offset.width,
                    y: point.y * scale + offset.height
                )
                path.addLine(to: scaledPoint)
            }
            path.closeSubpath()
        }
        
        return path
    }
}
