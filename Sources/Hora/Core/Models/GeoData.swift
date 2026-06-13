import Foundation
import SwiftUI

// MARK: - Highcharts Transform Parameters

/// Highcharts地图坐标转换参数（从world.json的hc-transform解析）
struct HCTransform: Codable {
    let crs: String
    let scale: Double
    let jsonres: Double
    let jsonmarginX: Double
    let jsonmarginY: Double
    let xoffset: Double
    let yoffset: Double
    
    enum CodingKeys: String, CodingKey {
        case crs, scale, jsonres, jsonmarginX, jsonmarginY, xoffset, yoffset
    }
}

// MARK: - Country Feature

/// 国家多边形数据（GeoJSON格式）
struct CountryFeature: Identifiable, Codable {
    let id: String
    let name: String
    let geometry: Geometry
    
    /// GeoJSON properties对象
    struct Properties: Codable {
        let name: String
    }
    
    struct Geometry: Codable {
        let type: String
        let coordinates: JSONCoordinates
    }
    
    /// 多边形路径（已转换为SwiftUI Path坐标）
    var pathPoints: [[CGPoint]] = []
    
    /// 边界框（用于快速碰撞检测）
    var boundingBox: CGRect = .null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // name在properties对象内
        let properties = try container.decode(Properties.self, forKey: .properties)
        name = properties.name
        geometry = try container.decode(Geometry.self, forKey: .geometry)
        pathPoints = []
        boundingBox = .null
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(Properties(name: name), forKey: .properties)
        try container.encode(geometry, forKey: .geometry)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, properties, geometry
    }
}

// MARK: - JSON Coordinates

/// 支持Polygon和MultiPolygon的坐标类型
enum JSONCoordinates: Codable {
    // 存储原始的坐标数据
    // Polygon: [[[Double]]] - 一个数组包含多个环(ring)，每个环是[lon, lat]对的数组
    // MultiPolygon: [[[[Double]]]] - 多个Polygon
    case polygons([[[Double]]])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // 尝试解析为MultiPolygon（四层嵌套）
        if let multiPoly = try? container.decode([[[[Double]]]].self) {
            // 展平为一个多边形数组
            self = .polygons(multiPoly.flatMap { $0 })
            return
        }
        
        // 尝试解析为Polygon（三层嵌套）
        if let poly = try? container.decode([[[Double]]].self) {
            self = .polygons(poly)
            return
        }
        
        // 回退
        self = .polygons([])
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .polygons(let polys):
            try container.encode(polys)
        }
    }
    
    /// 获取所有多边形的坐标点
    func allPolygons() -> [[[Double]]] {
        switch self {
        case .polygons(let polys):
            return polys
        }
    }
}

// MARK: - World Map Data

/// 世界地图数据容器
struct WorldMapData: Codable {
    let title: String
    let version: String
    let type: String
    let copyright: String
    let copyrightShort: String
    let copyrightUrl: String
    
    // hc-transform参数
    let hcTransform: [String: HCTransform]
    
    // 国家多边形数据
    let features: [CountryFeature]
    
    enum CodingKeys: String, CodingKey {
        case title, version, type, copyright, copyrightShort, copyrightUrl, features
        case hcTransform = "hc-transform"
    }
    
    /// 获取默认的坐标转换参数
    var defaultTransform: HCTransform? {
        return hcTransform["default"]
    }
}

// MARK: - Country Timezone Info

/// 国家时区信息
struct CountryTimezoneInfo: Codable {
    let countryCode: String
    let countryName: String
    let timezones: [TimezoneCity]
    
    struct TimezoneCity: Codable {
        let timezone: String
        let cityName: String
        let cityLocalizedName: String
        let latitude: Double
        let longitude: Double
        let isCapital: Bool
    }
    
    /// 是否跨多个时区
    var hasMultipleTimezones: Bool {
        return timezones.count > 1
    }
    
    /// 获取首都（单时区国家）或代表城市（多时区国家）
    var representativeCities: [TimezoneCity] {
        if hasMultipleTimezones {
            return timezones
        } else if let capital = timezones.first(where: { $0.isCapital }) {
            return [capital]
        } else {
            return timezones.isEmpty ? [] : [timezones[0]]
        }
    }
}
