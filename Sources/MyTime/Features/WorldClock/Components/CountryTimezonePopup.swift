import SwiftUI

// MARK: - Country Timezone Popup

/// 国家时区弹窗 - hover国家时显示时区信息
struct CountryTimezonePopup: View {
    let countryName: String
    let timezoneInfo: CountryTimezoneInfo?
    let currentTime: Date
    let position: CGPoint
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 国家名称
            Text(countryName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            if let info = timezoneInfo {
                if info.hasMultipleTimezones {
                    // 多时区国家：显示所有时区
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(info.timezones, id: \.timezone) { tzCity in
                            TimezoneRow(
                                city: tzCity,
                                currentTime: currentTime,
                                isMultiTimezone: true
                            )
                        }
                    }
                } else if let city = info.timezones.first {
                    // 单时区国家：显示首都/代表城市
                    TimezoneRow(
                        city: city,
                        currentTime: currentTime,
                        isMultiTimezone: false
                    )
                }
            } else {
                // 无时区信息时显示提示
                Text("时区信息不可用")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 13/255, green: 46/255, blue: 107/255)) // 与CurrentTimePanelView一致
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .position(position)
        .zIndex(1000) // 确保在最顶层显示
    }
}

// MARK: - Timezone Row

/// 时区行 - 显示单个时区的时间和城市
struct TimezoneRow: View {
    let city: CountryTimezoneInfo.TimezoneCity
    let currentTime: Date
    let isMultiTimezone: Bool
    
    private var timeString: String {
        let tz = TimeZone(identifier: city.timezone) ?? .current
        return DateFormatterCache.formatter(format: "HH:mm", timeZone: tz).string(from: currentTime)
    }
    
    private var fullTimeString: String {
        let tz = TimeZone(identifier: city.timezone) ?? .current
        return DateFormatterCache.formatter(format: "HH:mm:ss", timeZone: tz).string(from: currentTime)
    }
    
    private var utcOffsetString: String {
        guard let tz = TimeZone(identifier: city.timezone) else { return "" }
        let offset = tz.secondsFromGMT(for: currentTime)
        let hours = offset / 3600
        let minutes = abs(offset % 3600) / 60
        
        if minutes == 0 {
            return "UTC\(hours >= 0 ? "+" : "")\(hours)"
        } else {
            return "UTC\(hours >= 0 ? "+" : "")\(hours):\(String(format: "%02d", minutes))"
        }
    }
    
    private var dstStatus: String? {
        guard let tz = TimeZone(identifier: city.timezone) else { return nil }
        let isDST = tz.isDaylightSavingTime(for: currentTime)
        return isDST ? "夏令时" : nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isMultiTimezone {
                // 多时区：显示城市名和时区
                HStack(spacing: 6) {
                    Text(city.cityLocalizedName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(timeString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.4))
                }
                
                HStack(spacing: 4) {
                    Text(utcOffsetString)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                    
                    if let dst = dstStatus {
                        Text("·")
                            .foregroundColor(.white.opacity(0.5))
                        Text(dst)
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                    }
                }
            } else {
                // 单时区：简洁显示
                HStack(spacing: 8) {
                    Text(fullTimeString)
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.4))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(city.cityLocalizedName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            Text(utcOffsetString)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                            
                            if let dst = dstStatus {
                                Text("·")
                                    .foregroundColor(.white.opacity(0.5))
                                Text(dst)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Time Label Bubble

/// 时间标签气泡 - 城市标记上方的悬浮标签
struct TimeLabelBubble: View {
    let cityName: String
    let timeString: String
    let isMajor: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Text(cityName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Text(timeString)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .lineLimit(1)
        }
        .fixedSize() // 确保内容不被压缩，完整显示
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(bubbleColor)
        )
    }
    
    private var bubbleColor: Color {
        if isSelected {
            return Color(red: 0.902, green: 0.494, blue: 0.133) // 橙色选中
        } else if isMajor {
            return Color(red: 0.85, green: 0.44, blue: 0.4) // 红色热门城市
        } else {
            return Color(red: 0.2, green: 0.2, blue: 0.2, opacity: 0.85) // 深灰普通城市
        }
    }
}

// MARK: - Current Time Panel View

/// 左下角当前时间面板
struct CurrentTimePanelView: View {
    let city: WorldCity
    let currentTime: Date
    let isHovered: Bool
    
    private var timeString: String {
        DateFormatterCache.formatter(format: "HH:mm:ss", timeZone: city.timeZone).string(from: currentTime)
    }
    
    private var ampmString: String {
        DateFormatterCache.formatter(format: "a", timeZone: city.timeZone).string(from: currentTime)
    }
    
    private var dateString: String {
        DateFormatterCache.formatter(format: "yyyy年M月d日", timeZone: city.timeZone).string(from: currentTime)
    }
    
    private var weekdayString: String {
        DateFormatterCache.formatter(format: "EEEE", timeZone: city.timeZone, locale: Locale(identifier: "zh_Hans")).string(from: currentTime)
    }
    
    private var utcOffsetString: String {
        let timeZone = city.timeZone
        let offset = timeZone.secondsFromGMT(for: currentTime)
        let hours = offset / 3600
        let minutes = abs(offset % 3600) / 60
        
        if minutes == 0 {
            return "UTC\(hours >= 0 ? "+" : "")\(hours)"
        } else {
            return "UTC\(hours >= 0 ? "+" : "")\(hours):\(String(format: "%02d", minutes))"
        }
    }
    
    private var dstString: String {
        let timeZone = city.timeZone
        let isDST = timeZone.isDaylightSavingTime(for: currentTime)
        return isDST ? "夏令时" : "冬令时"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 城市名
            Text("\(city.localizedName), \(city.country)")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .opacity(0.9)
                .lineLimit(1)
            
            // 时区和夏令时
            HStack(spacing: 6) {
                Text(utcOffsetString)
                Text("·")
                Text(dstString)
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(.white)
            .opacity(0.8)
            
            // 日期
            HStack(spacing: 4) {
                Text(weekdayString)
                Text(dateString)
            }
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(.white)
            .opacity(0.7)
            
            // 时间 - 粗体（放在最下面）
            Text(timeString)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 13/255, green: 46/255, blue: 107/255))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 3)
        )
    }
}
