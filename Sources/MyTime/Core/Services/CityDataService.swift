import Foundation

/// 城市数据服务 - 统一管理城市数据加载和查询
@MainActor
class CityDataService {
    static let shared = CityDataService()
    
    private(set) var cities: [WorldCity] = []
    
    /// 配置项
    private(set) var defaultCity: WorldCity?
    private var almanacTimezones: Set<String> = []
    
    /// 时区标识符到城市的映射（用于快速查找时区对应的城市）
    private var timezoneToCity: [String: WorldCity] = [:]
    
    private init() {
        loadCities()
    }
    
    private func loadCities() {
        // 尝试从主 bundle 加载，如果失败则尝试从模块 bundle 加载
        let bundle = Bundle.main
        var url = bundle.url(forResource: "Cities", withExtension: "json")
        
        // 如果主 bundle 找不到，尝试从当前模块的 bundle 查找
        if url == nil {
            url = Bundle.module.url(forResource: "Cities", withExtension: "json")
        }
        
        guard let fileURL = url,
              let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to load Cities.json - city data is required. Searched in: \(Bundle.main.bundlePath), module: \(Bundle.module.bundlePath)")
        }
        
        // 加载配置
        guard let config = json["config"] as? [String: Any] else {
            fatalError("Cities.json missing 'config' section")
        }
        
        guard let defaultCityDict = config["defaultCity"] as? [String: Any],
              let city = WorldCity(from: defaultCityDict) else {
            fatalError("Cities.json config missing valid 'defaultCity' object")
        }
        defaultCity = city
        
        // almanacTimezones is optional
        if let tzList = config["almanacTimezones"] as? [String] {
            almanacTimezones = Set(tzList)
        }
        
        // 加载城市数据
        guard let citiesArray = json["cities"] as? [[String: Any]] else {
            fatalError("Cities.json contains no cities array")
        }
        
        cities = citiesArray.compactMap { WorldCity(from: $0) }
        guard !cities.isEmpty else {
            fatalError("Cities.json contains no valid city data")
        }
        buildTimezoneMap()
    }
    
    private func buildTimezoneMap() {
        timezoneToCity = [:]
        for city in cities {
            // 优先保留 isMajor 的城市
            if timezoneToCity[city.timezoneIdentifier] == nil || city.isMajor {
                timezoneToCity[city.timezoneIdentifier] = city
            }
        }
    }
    
    /// 根据时区标识符获取城市名称（本地化）
    func getLocalizedName(forTimezone identifier: String) -> String {
        if let city = timezoneToCity[identifier] {
            return city.localizedName
        }
        // 回退到系统本地化名称
        if let tz = TimeZone(identifier: identifier),
           let name = tz.localizedName(for: .standard, locale: Locale(identifier: "zh_Hans")) {
            return name
        }
        return identifier
    }
    
    /// 获取当前时区对应的城市
    func getCurrentCity() -> WorldCity {
        let currentTZ = TimeZone.current.identifier
        if let city = timezoneToCity[currentTZ] {
            return city
        }
        // 回退到配置中的默认城市
        guard let defaultDefaultCity = defaultCity else {
            fatalError("Default city not configured in Cities.json")
        }
        return defaultDefaultCity
    }
    
    /// 根据时区标识符获取城市
    func getCity(forTimezone identifier: String) -> WorldCity? {
        return timezoneToCity[identifier]
    }
    
    /// 判断当前时区是否应显示黄历摘要
    func shouldShowAlmanacSummary() -> Bool {
        let currentTZ = TimeZone.current.identifier
        return almanacTimezones.contains(currentTZ)
    }
}
