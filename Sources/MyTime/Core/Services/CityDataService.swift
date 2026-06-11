import Foundation

private struct CitiesConfig: Codable {
    let defaultCity: WorldCity
    let almanacTimezones: [String]?
}

private struct CitiesData: Codable {
    let config: CitiesConfig
    let cities: [WorldCity]
}

/// 城市数据服务 - 统一管理城市数据加载和查询
@MainActor
class CityDataService {
    static let shared = CityDataService()
    
    private(set) var cities: [WorldCity] = []
    
    /// 配置项
    private(set) var defaultCity: WorldCity?
    private var almanacTimezones: Set<String> = []
    
    /// 数据是否加载成功
    private(set) var isLoaded: Bool = false
    
    /// 时区标识符到城市的映射（用于快速查找时区对应的城市）
    private var timezoneToCity: [String: WorldCity] = [:]
    
    private init() {
        loadCities()
    }
    
    /// 查找资源文件 URL - 按优先级搜索多个 bundle 位置
    private func findResourceURL(resource name: String, extension ext: String) -> URL? {
        let logger = CrashLogService.shared
        
        // 1. Bundle.main（.app 包中的 Resources/）
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            logger.log("Found \(name).\(ext) in Bundle.main: \(url.path)")
            return url
        }
        logger.log("\(name).\(ext) NOT found in Bundle.main (\(Bundle.main.bundlePath))")
        
        // 2. Bundle.module（SPM 自动生成的资源 bundle）
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            logger.log("Found \(name).\(ext) in Bundle.module: \(url.path)")
            return url
        }
        logger.log("\(name).\(ext) NOT found in Bundle.module (\(Bundle.module.bundlePath))")
        
        // 3. 在 .app 的 Resources 子目录中查找 SPM 资源 bundle
        let resourceURL = Bundle.main.resourceURL
        let candidates = [
            "MyTime_MyTime",
            "MyTime_MyTime.bundle/MyTime_MyTime",
        ]
        for candidate in candidates {
            if let resourceURL = resourceURL {
                let bundlePath = resourceURL.appendingPathComponent(candidate)
                if let bundle = Bundle(url: bundlePath),
                   let url = bundle.url(forResource: name, withExtension: ext) {
                    logger.log("Found \(name).\(ext) in SPM resource bundle at \(bundlePath.path)")
                    return url
                }
            }
        }
        logger.log("\(name).\(ext) NOT found in SPM resource bundle candidates")
        
        // 4. 在可执行文件旁边查找（swift run 模式）
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent()
            let spmBundlePath = execDir.appendingPathComponent("MyTime_MyTime.bundle")
            if let bundle = Bundle(url: spmBundlePath),
               let url = bundle.url(forResource: name, withExtension: ext) {
                logger.log("Found \(name).\(ext) next to executable: \(spmBundlePath.path)")
                return url
            }
        }
        
        logger.logError("\(name).\(ext) NOT found in any bundle location")
        return nil
    }
    
    private func loadCities() {
        let logger = CrashLogService.shared
        logger.log("CityDataService: Starting to load Cities.json")
        
        guard let fileURL = findResourceURL(resource: "Cities", extension: "json") else {
            logger.logError("Cities.json not found in any bundle - city data will be unavailable")
            return
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            logger.logError("Failed to read Cities.json: \(error)")
            return
        }
        
        let decoder = JSONDecoder()
        let citiesData: CitiesData
        do {
            citiesData = try decoder.decode(CitiesData.self, from: data)
        } catch {
            logger.logError("Failed to decode Cities.json: \(error)")
            return
        }
        
        defaultCity = citiesData.config.defaultCity
        
        // almanacTimezones is optional
        if let tzList = citiesData.config.almanacTimezones {
            almanacTimezones = Set(tzList)
        }
        
        cities = citiesData.cities
        if cities.isEmpty {
            logger.logWarning("Cities.json contains no valid city data")
            return
        }
        
        buildTimezoneMap()
        isLoaded = true
        logger.log("CityDataService: Loaded \(cities.count) cities successfully")
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
        if let defaultDefaultCity = defaultCity {
            return defaultDefaultCity
        }
        // 最终回退：基于当前时区构造一个 fallback 城市
        CrashLogService.shared.logWarning("No default city configured, using fallback for timezone: \(currentTZ)")
        return WorldCity.fallbackCity(for: TimeZone.current)
    }
    
    /// 根据时区标识符获取城市
    func getCity(forTimezone identifier: String) -> WorldCity? {
        return timezoneToCity[identifier]
    }
    
    /// 判断当前时区是否应显示黄历摘要
    func shouldShowAlmanacSummary() -> Bool {
        guard isLoaded else { return false }
        let currentTZ = TimeZone.current.identifier
        return almanacTimezones.contains(currentTZ)
    }
}
