import Foundation
import SwiftUI
import CoreGraphics
import AppKit

// MARK: - World Map Data Service

/// 世界地图数据服务 - 管理地图数据加载和坐标转换
/// @Observable：世界时钟打开时惰性加载（ensureLoaded），数据就绪后自动刷新视图
@MainActor
@Observable
class WorldMapDataService {
    static let shared = WorldMapDataService()
    
    /// 共享 JSON 解码器（无状态线程安全，nonisolated 供后台解码线程访问）
    nonisolated(unsafe) private static let jsonDecoder = JSONDecoder()
    
    // MARK: - Properties
    
    /// 地图数据（加载后释放）
    private var mapData: WorldMapData?
    
    /// 坐标转换参数
    private(set) var transform: HCTransform?
    
    /// 已处理的国家路径数据（矢量绘制的数据源，保留在内存中约 1-2MB）
    private(set) var countries: [CountryPathData] = []
    
    /// 预构建的整幅地图矢量路径（原始投影坐标，绘制时按目标尺寸变换）。
    /// ⚠️ 替代旧版 36MB 的 NSImage 位图预渲染，内存降 20 倍以上且矢量无损缩放
    private(set) var cachedMapPath: CGPath?
    
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
        
        // 预构建矢量路径（不再渲染位图）
        buildMapPath()
        
        isLoaded = true
    }
    
    /// 释放地图数据（世界时钟关闭时调用）
    func unload() {
        countries = []
        cachedMapPath = nil
        countryTimezones = [:]
        mapBounds = .null
        transform = nil
        yMid = 0
        isLoaded = false
    }
    
    // MARK: - Build Vector Path
    
    /// 预构建整幅地图的 CGPath（约 1-2MB，仅点坐标数据）
    private func buildMapPath() {
        guard !countries.isEmpty, mapBounds != .null else { return }
        
        let path = CGMutablePath()
        for country in countries {
            for polygon in country.pathPoints {
                guard let first = polygon.first else { continue }
                path.move(to: first)
                var iterator = polygon.makeIterator()
                iterator.next() // 跳过 first
                while let point = iterator.next() {
                    path.addLine(to: point)
                }
                path.closeSubpath()
            }
        }
        cachedMapPath = path
        
        CrashLogService.shared.log("Built map vector path (\(countries.count) countries)")
    }
    
    // MARK: - Data Loading
    
    private func loadMapData() async {
        // 从Bundle加载world.json，支持多个搜索路径
        let logger = CrashLogService.shared
        
        // 1. 尝试 Bundle.module
        var url = Bundle.module.url(forResource: "world", withExtension: "json")
        
        // 2. 尝试 Bundle.main
        if url == nil {
            url = Bundle.main.url(forResource: "world", withExtension: "json")
            if url != nil {
                logger.log("WorldMapDataService: Found world.json in Bundle.main")
            }
        } else {
            logger.log("WorldMapDataService: Found world.json in Bundle.module")
        }
        
        // 3. 尝试 SPM 资源 bundle 子目录
        if url == nil, let resourceURL = Bundle.main.resourceURL {
            let spmBundlePath = resourceURL.appendingPathComponent("Hora_Hora")
            if let bundle = Bundle(url: spmBundlePath),
               let bundleURL = bundle.url(forResource: "world", withExtension: "json") {
                url = bundleURL
                logger.log("WorldMapDataService: Found world.json in SPM resource bundle")
            }
        }
        
        guard let fileURL = url else {
            logger.logError("world.json not found in any bundle location")
            return
        }
        
        let loadedMapData = await Task.detached(priority: .userInitiated) { () -> WorldMapData? in
            do {
                let data = try Data(contentsOf: fileURL)
                return try Self.jsonDecoder.decode(WorldMapData.self, from: data)
            } catch {
                logger.logError("Error loading world.json: \(error)")
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
        
        logger.log("Loaded \(countries.count) countries from world.json")
    }
    
    private func loadCountryTimezones() async {
        let logger = CrashLogService.shared
        
        // 尝试多个路径搜索 countryTimezones.json
        var url = Bundle.module.url(forResource: "countryTimezones", withExtension: "json")
        if url == nil {
            url = Bundle.main.url(forResource: "countryTimezones", withExtension: "json")
        }
        if url == nil, let resourceURL = Bundle.main.resourceURL {
            let spmBundlePath = resourceURL.appendingPathComponent("Hora_Hora")
            if let bundle = Bundle(url: spmBundlePath) {
                url = bundle.url(forResource: "countryTimezones", withExtension: "json")
            }
        }
        
        guard let fileURL = url else {
            logger.logWarning("countryTimezones.json not found, using default mapping")
            generateDefaultTimezoneMapping()
            return
        }
        
        let timezoneInfos = await Task.detached(priority: .userInitiated) { () -> [CountryTimezoneInfo]? in
            do {
                let data = try Data(contentsOf: fileURL)
                return try Self.jsonDecoder.decode([CountryTimezoneInfo].self, from: data)
            } catch {
                logger.logError("Error loading countryTimezones.json: \(error)")
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
        
        logger.log("Loaded timezone info for \(countryTimezones.count) countries")
    }
    
    /// 生成默认的时区映射（基于cities24tz.json）
    private func generateDefaultTimezoneMapping() {
        // 从cities24tz.json构建国家->时区映射
        let logger = CrashLogService.shared
        
        // 尝试多个路径搜索 cities24tz.json
        var url = Bundle.module.url(forResource: "cities24tz", withExtension: "json")
        if url == nil {
            url = Bundle.main.url(forResource: "cities24tz", withExtension: "json")
        }
        if url == nil, let resourceURL = Bundle.main.resourceURL {
            let spmBundlePath = resourceURL.appendingPathComponent("Hora_Hora")
            if let bundle = Bundle(url: spmBundlePath) {
                url = bundle.url(forResource: "cities24tz", withExtension: "json")
            }
        }
        
        guard let fileURL = url else {
            logger.logWarning("cities24tz.json not found for default timezone mapping")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
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
            logger.logError("Error generating default timezone mapping: \(error)")
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

// MARK: - Country Hit Data

/// 轻量级国家命中测试数据（用于交互，不用于渲染）
struct CountryHitData: Identifiable {
    let id: String
    let name: String
    let boundingBox: CGRect
    let pathPoints: [[CGPoint]]
}
