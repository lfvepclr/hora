import Foundation

/// DateFormatter 全局缓存 - 避免每次渲染重新创建
/// DateFormatter 初始化代价高，缓存后按 format+timezone 复用
@MainActor
enum DateFormatterCache {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var order: [String] = []
    private static let maxSize = 30
    
    private static func evictIfNeeded() {
        if cache.count >= maxSize {
            let removeCount = cache.count / 2
            let keysToRemove = Array(order.prefix(removeCount))
            keysToRemove.forEach { cache.removeValue(forKey: $0) }
            order.removeFirst(removeCount)
        }
    }
    
    static func formatter(format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "\(format)_\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        evictIfNeeded()
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = timeZone
        cache[key] = f
        order.append(key)
        return f
    }
    
    static func formatter(format: String, timeZone: TimeZone = .current, locale: Locale) -> DateFormatter {
        let key = "\(format)_\(timeZone.identifier)_\(locale.identifier)"
        if let cached = cache[key] { return cached }
        evictIfNeeded()
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = timeZone
        f.locale = locale
        cache[key] = f
        order.append(key)
        return f
    }
    
    static func clearCache() {
        cache.removeAll()
        order.removeAll()
    }
}
