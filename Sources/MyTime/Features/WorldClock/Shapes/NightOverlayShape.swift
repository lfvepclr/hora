import SwiftUI

// MARK: - Night Overlay Shape

/// 昼夜分界线Shape - 基于天文算法计算夜晚区域
/// 参考 world-daylight-map 项目的实现
struct NightOverlayShape: Shape {
    let date: Date
    let mapBounds: CGRect
    let transform: HCTransform?
    let yMid: CGFloat
    let viewHeight: CGFloat
    
    /// 地球半径（米）- Miller投影使用等面积半径
    private let R_A: Double = 6371007.2
    
    /// 经度采样步长（度）- 3度步长足够平滑且性能优异
    private let precisionLng: Double = 3.0
    
    func path(in rect: CGRect) -> Path {
        guard transform != nil else { return Path() }
        
        // 预计算太阳常量（一次性计算，避免每个经度重复）
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        let hour = Double(utcCalendar.component(.hour, from: date))
        let minute = Double(utcCalendar.component(.minute, from: date))
        let utcHours = hour + minute / 60.0
        
        let dayOfYear = getDayOfYear(date, calendar: utcCalendar)
        
        // 太阳赤纬
        let declination = 23.45 * sin(2 * Double.pi / 365.0 * Double(dayOfYear - 81))
        let decRad = declination * Double.pi / 180.0
        
        // 太阳正午经度
        let solarNoonLon = -(utcHours - 12.0) * 15.0
        
        // 判断北极是否为白天
        let northSun = declination > 0
        
        // 用解析公式直接计算昼夜分界线纬度（替代二分法，性能提升100倍+）
        var terminatorCoords: [(lat: Double, lon: Double)] = []
        
        for lon in stride(from: -180.0, through: 180.0, by: precisionLng) {
            let lat = terminatorLatitude(longitude: lon, decRad: decRad, solarNoonLon: solarNoonLon)
            terminatorCoords.append((lat: lat, lon: lon))
        }
        
        guard terminatorCoords.count >= 3 else { return Path() }
        
        // 将坐标转换为地图点
        var terminatorPoints = terminatorCoords.compactMap { coord -> CGPoint? in
            return latLonToMapPoint(latitude: coord.lat, longitude: coord.lon)
        }
        
        guard terminatorPoints.count >= 3 else { return Path() }
        
        // 构建夜晚区域路径
        return buildNightPathSmooth(terminatorPoints: &terminatorPoints, northSun: northSun)
    }
    
    // MARK: - Solar Position Calculation
    
    /// 解析计算昼夜分界线纬度（替代二分法，性能提升100倍+）
    /// 当 sinAlt = 0 时：sin(lat)*sin(dec) + cos(lat)*cos(dec)*cos(ha) = 0
    /// => tan(lat) = -cos(ha) / tan(dec) 当 dec != 0
    private func terminatorLatitude(longitude: Double, decRad: Double, solarNoonLon: Double) -> Double {
        let hourAngle = (longitude - solarNoonLon) * Double.pi / 180.0
        
        // 处理赤纬接近0的情况（春秋分点附近）
        guard abs(decRad) > 0.001 else {
            return 0
        }
        
        let tanLat = -cos(hourAngle) / tan(decRad)
        let lat = atan(max(-100, min(100, tanLat))) * 180.0 / Double.pi
        return lat
    }
    
    /// 构建平滑的夜晚区域路径（参考 world-daylight-map 的实现）
    private func buildNightPathSmooth(terminatorPoints: inout [CGPoint], northSun: Bool) -> Path {
        var path = Path()
        
        guard terminatorPoints.count >= 3 else {
            return buildNightPathSimple(terminatorPoints: terminatorPoints, northSun: northSun)
        }
        
        // world-daylight-map 的逻辑：
        // 路径从边缘开始 -> 沿昼夜分界线（使用basis曲线）-> 回到边缘 -> 封闭
        
        if northSun {
            // 北极是白天，夜晚区域在南半球
            // 路径：从左下角 -> 沿昼夜分界线（从左到右）-> 右下角 -> 回到左下角
            
            let startY = mapBounds.maxY
            let endY = mapBounds.maxY
            
            // 开始点：地图左边缘，对应第一个昼夜分界线点的Y坐标
            let firstPoint = terminatorPoints.first!
            path.move(to: CGPoint(x: mapBounds.minX, y: startY))
            path.addLine(to: CGPoint(x: mapBounds.minX, y: firstPoint.y))
            
            // 使用 Catmull-Rom 样条曲线绘制平滑的昼夜分界线
            // Catmull-Rom 曲线通过控制点自然平滑通过
            path.addLine(to: terminatorPoints[0])
            
            // 添加中间点形成平滑曲线
            for i in 1..<terminatorPoints.count {
                let prev = terminatorPoints[max(0, i - 1)]
                let curr = terminatorPoints[i]
                let next = terminatorPoints[min(terminatorPoints.count - 1, i + 1)]
                
                // 使用三次贝塞尔曲线的控制点计算
                // cp1 = prev + (curr - next) / 6
                // cp2 = curr + (next - prev) / 6
                // 这模拟了 Catmull-Rom 到 cubic Bezier 的转换
                let tension: CGFloat = 0.3  // 控制曲线紧绷程度
                
                let cp1x = curr.x + (prev.x - curr.x) * tension
                let cp1y = curr.y + (prev.y - curr.y) * tension
                let cp2x = curr.x + (next.x - curr.x) * tension
                let cp2y = curr.y + (next.y - curr.y) * tension
                
                path.addCurve(
                    to: curr,
                    control1: CGPoint(x: cp1x, y: cp1y),
                    control2: CGPoint(x: cp2x, y: cp2y)
                )
            }
            
            // 最后一个点到右边缘
            let lastPoint = terminatorPoints.last!
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: lastPoint.y))
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: endY))
            path.closeSubpath()
            
        } else {
            // 北极是夜晚，夜晚区域在北半球
            // 路径：从左上角 -> 沿昼夜分界线（从左到右）-> 右上角 -> 回到左上角
            
            let startY = mapBounds.minY
            let endY = mapBounds.minY
            
            let firstPoint = terminatorPoints.first!
            path.move(to: CGPoint(x: mapBounds.minX, y: startY))
            path.addLine(to: CGPoint(x: mapBounds.minX, y: firstPoint.y))
            
            path.addLine(to: terminatorPoints[0])
            
            for i in 1..<terminatorPoints.count {
                let prev = terminatorPoints[max(0, i - 1)]
                let curr = terminatorPoints[i]
                let next = terminatorPoints[min(terminatorPoints.count - 1, i + 1)]
                
                let tension: CGFloat = 0.3
                
                let cp1x = curr.x + (prev.x - curr.x) * tension
                let cp1y = curr.y + (prev.y - curr.y) * tension
                let cp2x = curr.x + (next.x - curr.x) * tension
                let cp2y = curr.y + (next.y - curr.y) * tension
                
                path.addCurve(
                    to: curr,
                    control1: CGPoint(x: cp1x, y: cp1y),
                    control2: CGPoint(x: cp2x, y: cp2y)
                )
            }
            
            let lastPoint = terminatorPoints.last!
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: lastPoint.y))
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: endY))
            path.closeSubpath()
        }
        
        return path
    }
    
    /// 简化的夜晚区域路径（备用）
    private func buildNightPathSimple(terminatorPoints: [CGPoint], northSun: Bool) -> Path {
        var path = Path()
        
        if northSun {
            path.move(to: CGPoint(x: mapBounds.minX, y: mapBounds.maxY))
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: mapBounds.maxY))
            path.addLine(to: mapBounds.maxX > mapBounds.minX ?
                CGPoint(x: mapBounds.maxX, y: terminatorPoints.last?.y ?? mapBounds.midY) :
                CGPoint(x: mapBounds.minX, y: terminatorPoints.last?.y ?? mapBounds.midY))
            for point in terminatorPoints.reversed() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: mapBounds.minX, y: terminatorPoints.first?.y ?? mapBounds.midY))
        } else {
            path.move(to: CGPoint(x: mapBounds.minX, y: mapBounds.minY))
            for point in terminatorPoints {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: terminatorPoints.last?.y ?? mapBounds.midY))
            path.addLine(to: CGPoint(x: mapBounds.maxX, y: mapBounds.minY))
        }
        
        path.closeSubpath()
        return path
    }
    
    // MARK: - Coordinate Conversion
    
    /// 将经纬度转换为地图坐标（Miller投影 -> Highcharts JSON坐标）
    private func latLonToMapPoint(latitude: Double, longitude: Double) -> CGPoint? {
        guard let transform = transform else { return nil }
        
        let normalizedLon = normalizeLongitude(longitude)
        
        let lonRad = normalizedLon * .pi / 180
        let latRad = latitude * .pi / 180
        
        let xProj = R_A * lonRad
        let yProj = R_A * 1.25 * log(tan(.pi / 4 + 0.4 * latRad))
        
        let s = transform.scale
        let jr = transform.jsonres
        let mx = transform.jsonmarginX
        let my = transform.jsonmarginY
        let xoff = transform.xoffset
        let yoff = transform.yoffset
        
        let jx = (xProj - xoff) * s * jr + mx
        let jy = my - (yoff - yProj) * s * jr
        
        let flippedY = 2 * yMid - CGFloat(jy)
        
        return CGPoint(x: CGFloat(jx), y: flippedY)
    }
    
    // MARK: - Helper Methods
    
    private func getDayOfYear(_ date: Date, calendar: Calendar) -> Int {
        let year = calendar.component(.year, from: date)
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return 1
        }
        return calendar.dateComponents([.day], from: startOfYear, to: date).day ?? 1
    }
    
    private func normalizeLongitude(_ lon: Double) -> Double {
        var result = lon
        while result > 180 { result -= 360 }
        while result < -180 { result += 360 }
        return result
    }
}

// MARK: - Night Overlay View

/// 昼夜分界线视图 - 只在分钟变化时重绘
struct NightOverlayView: View {
    let date: Date
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    let viewSize: CGSize
    
    /// 截取到分钟级别，避免每秒重绘
    private var minuteDate: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }
    
    var body: some View {
        // 计算覆盖整个视图的边界框
        let overlayBounds = CGRect(
            x: -offset.width / scale,
            y: -offset.height / scale,
            width: viewSize.width / scale,
            height: viewSize.height / scale
        )
        
        return NightOverlayShape(
            date: minuteDate,
            mapBounds: overlayBounds,
            transform: mapService.transform,
            yMid: mapService.yMid,
            viewHeight: viewSize.height > 0 ? viewSize.height : mapService.mapBounds.height
        )
        .fill(Color(red: 11/255, green: 31/255, blue: 70/255, opacity: 0.65), style: FillStyle(eoFill: true))
        .scaleEffect(scale, anchor: .topLeading)
        .offset(offset)
        .allowsHitTesting(false)
    }
}

// MARK: - Simplified Night Overlay

/// 简化版昼夜分界线 - 直接基于时间计算
struct SimpleNightOverlay: Shape {
    let date: Date
    let mapBounds: CGRect
    let transform: HCTransform?
    let yMid: CGFloat
    
    /// 地球半径（米）- Miller投影使用等面积半径
    private let R_A: Double = 6371007.2
    
    func path(in rect: CGRect) -> Path {
        // 计算当前UTC时间对应的太阳位置
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        let hour = Double(utcCalendar.component(.hour, from: date))
        let minute = Double(utcCalendar.component(.minute, from: date))
        let utcHours = hour + minute / 60.0
        
        // 太阳直射点经度（正午经度）
        let solarNoonLon = -(utcHours - 12.0) * 15.0
        
        // 午夜经度（夜晚中心）
        let midnightLon = solarNoonLon + 180.0
        
        // 转换为地图坐标
        guard let centerPoint = latLonToMapPoint(latitude: 0, longitude: normalizeLongitude(midnightLon)) else {
            return Path()
        }
        
        // 创建一个简单的半透明遮罩
        // 夜晚区域大约跨越经度180度（12小时）
        var path = Path()
        
        // 计算夜晚区域的宽度（大约一半地图宽度）
        let nightWidth = mapBounds.width / 2
        let nightHeight = mapBounds.height
        
        // 构建矩形夜晚区域
        let nightRect = CGRect(
            x: centerPoint.x - nightWidth / 2,
            y: mapBounds.minY,
            width: nightWidth,
            height: nightHeight
        )
        
        path.addRect(nightRect)
        
        return path
    }
    
    /// 将经纬度转换为地图坐标（Miller投影 -> Highcharts JSON坐标）
    private func latLonToMapPoint(latitude: Double, longitude: Double) -> CGPoint? {
        guard let transform = transform else { return nil }
        
        // Miller投影
        let lonRad = longitude * .pi / 180
        let latRad = latitude * .pi / 180
        
        let xProj = R_A * lonRad
        let yProj = R_A * 1.25 * log(tan(.pi / 4 + 0.4 * latRad))
        
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
    
    private func normalizeLongitude(_ lon: Double) -> Double {
        var result = lon
        while result > 180 { result -= 360 }
        while result < -180 { result += 360 }
        return result
    }
}
