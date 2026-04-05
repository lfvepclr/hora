import SwiftUI

// MARK: - Night Overlay Shape

/// 昼夜分界线Shape - 基于天文算法计算夜晚区域
struct NightOverlayShape: Shape {
    let date: Date
    let mapBounds: CGRect
    let transform: HCTransform?
    let yMid: CGFloat
    let viewHeight: CGFloat
    
    /// 地球半径（米）- Miller投影使用等面积半径
    private let R_A: Double = 6371007.2
    
    func path(in rect: CGRect) -> Path {
        guard transform != nil else { return Path() }
        
        // 获取UTC时间
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        let hour = Double(utcCalendar.component(.hour, from: date))
        let minute = Double(utcCalendar.component(.minute, from: date))
        let utcHours = hour + minute / 60.0
        
        // 计算一年中的第几天
        let dayOfYear = getDayOfYear(date, calendar: utcCalendar)
        
        // 计算太阳赤纬
        let declination = -23.45 * cos(2 * Double.pi / 365.0 * Double(dayOfYear + 10))
        
        // 计算太阳正午经度（太阳直射点）
        let solarNoonLon = -(utcHours - 12.0) * 15.0
        
        // 收集terminator曲线上的点
        // 日出线（白天开始，在太阳正午西侧）和日落线（白天结束，在太阳正午东侧）
        var sunrisePoints: [CGPoint] = []  // 日出线上的点
        var sunsetPoints: [CGPoint] = []   // 日落线上的点
        
        for lat in stride(from: -85.0, through: 85.0, by: 1.0) {
            let latRad = lat * Double.pi / 180.0
            let decRad = declination * Double.pi / 180.0
            
            var cosHA = -tan(latRad) * tan(decRad)
            cosHA = max(-1.0, min(1.0, cosHA))
            let ha = acos(cosHA) * 180.0 / Double.pi
            
            // 日出经度（在太阳正午经度西侧）- 不归一化，保持连续性
            let sunriseLon = solarNoonLon - ha
            // 日落经度（在太阳正午经度东侧）- 不归一化，保持连续性
            let sunsetLon = solarNoonLon + ha
            
            if let pt = latLonToMapPointRaw(latitude: lat, longitude: sunriseLon) {
                sunrisePoints.append(pt)
            }
            if let pt = latLonToMapPointRaw(latitude: lat, longitude: sunsetLon) {
                sunsetPoints.append(pt)
            }
        }
        
        guard sunrisePoints.count >= 3 && sunsetPoints.count >= 3 else { return Path() }

        // 构建白天区域路径（用于从夜晚区域中挖掉）
        // 白天区域在日出线和日落线之间（正午经度方向）
        var dayPath = Path()

        // 从日落线北端开始，向南沿日落线画
        dayPath.move(to: sunsetPoints[sunsetPoints.count - 1])
        for i in stride(from: sunsetPoints.count - 2, through: 0, by: -1) {
            dayPath.addLine(to: sunsetPoints[i])
        }

        // 从日落线南端，沿日出线向北回到起点（形成白天区域闭环）
        for i in 1..<sunrisePoints.count {
            dayPath.addLine(to: sunrisePoints[i])
        }

        dayPath.closeSubpath()

        // 构建夜晚路径：整个地图矩形减去白天区域
        // 使用Even-odd fill rule实现布尔减法
        var nightPath = Path()
        nightPath.addRect(mapBounds)
        nightPath.addPath(dayPath)

        return nightPath
    }
    
    /// 将经纬度转换为地图坐标（不归一化经度，保持连续性）
    private func latLonToMapPointRaw(latitude: Double, longitude: Double) -> CGPoint? {
        guard let transform = transform else { return nil }
        
        // 对经度进行归一化，限制在 [-180°, 180°] 范围内
        let normalizedLon = normalizeLongitude(longitude)
        
        // Miller投影
        let lonRad = normalizedLon * .pi / 180
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
    
    /// 将经纬度转换为地图坐标（Miller投影 -> Highcharts JSON坐标）
    private func latLonToMapPoint(latitude: Double, longitude: Double) -> CGPoint? {
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
}

// MARK: - Night Overlay View

/// 昼夜分界线视图
struct NightOverlayView: View {
    let date: Date
    let mapService: WorldMapDataService
    let scale: CGFloat
    let offset: CGSize
    let viewSize: CGSize
    
    var body: some View {
        // 计算覆盖整个视图的边界框
        let overlayBounds = CGRect(
            x: -offset.width / scale,
            y: -offset.height / scale,
            width: viewSize.width / scale,
            height: viewSize.height / scale
        )
        
        return NightOverlayShape(
            date: date,
            mapBounds: overlayBounds,
            transform: mapService.transform,
            yMid: mapService.yMid,
            viewHeight: viewSize.height > 0 ? viewSize.height : mapService.mapBounds.height
        )
        .fill(Color(red: 11/255, green: 31/255, blue: 70/255, opacity: 0.65), style: FillStyle(eoFill: true))
        .scaleEffect(scale, anchor: .topLeading)
        .offset(offset)
        .allowsHitTesting(false) // 不拦截交互事件
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
