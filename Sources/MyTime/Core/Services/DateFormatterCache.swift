import Foundation

/// DateFormatter 全局缓存 - 避免每次渲染重新创建
/// DateFormatter 初始化代价高，缓存后按 format+timezone 复用
@MainActor
enum DateFormatterCache {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    private static let maxSize = 50
    
    static func formatter(format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "\(format)_\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        if cache.count >= maxSize { cache.removeAll() }
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = timeZone
        cache[key] = f
        return f
    }
    
    static func formatter(format: String, timeZone: TimeZone = .current, locale: Locale) -> DateFormatter {
        let key = "\(format)_\(timeZone.identifier)_\(locale.identifier)"
        if let cached = cache[key] { return cached }
        if cache.count >= maxSize { cache.removeAll() }
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = timeZone
        f.locale = locale
        cache[key] = f
        return f
    }
    
    static func clearCache() {
        cache.removeAll()
    }
}
