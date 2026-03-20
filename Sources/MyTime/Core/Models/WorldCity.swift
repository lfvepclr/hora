import Foundation
import MapKit

/// 城市数据模型 - 统一从 Cities.json 加载
struct WorldCity: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let localizedName: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezoneIdentifier: String
    let isMajor: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var timeZone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? TimeZone.current
    }
    
    /// 从 JSON 字典创建
    init?(from dict: [String: Any]) {
        guard let name = dict["name"] as? String,
              let localizedName = dict["localizedName"] as? String,
              let country = dict["country"] as? String,
              let latitude = dict["latitude"] as? Double,
              let longitude = dict["longitude"] as? Double,
              let timezone = dict["timezone"] as? String else {
            return nil
        }
        
        self.id = UUID()
        self.name = name
        self.localizedName = localizedName
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timezoneIdentifier = timezone
        self.isMajor = dict["isMajor"] as? Bool ?? false
    }
    
    static func == (lhs: WorldCity, rhs: WorldCity) -> Bool {
        lhs.id == rhs.id
    }
}
