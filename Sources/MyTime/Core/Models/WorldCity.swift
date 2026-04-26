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
    
    private enum CodingKeys: String, CodingKey {
        case name, localizedName, country, latitude, longitude, isMajor
        case timezoneIdentifier = "timezone"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.localizedName = try container.decode(String.self, forKey: .localizedName)
        self.country = try container.decode(String.self, forKey: .country)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.timezoneIdentifier = try container.decode(String.self, forKey: .timezoneIdentifier)
        self.isMajor = try container.decodeIfPresent(Bool.self, forKey: .isMajor) ?? false
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
