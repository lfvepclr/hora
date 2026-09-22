import XCTest
import SwiftUI
@testable import Hora

// MARK: - Solar Position Calculator for Testing

/// 太阳位置计算器 - 用于测试昼夜分界线逻辑
/// 实现与 NightOverlayShape 相同的天文算法
final class SolarPositionCalculator {
    let date: Date
    
    init(date: Date) {
        self.date = date
    }
    
    /// 获取一年中的第几天
    func getDayOfYear() -> Int {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        let year = utcCalendar.component(.year, from: date)
        guard let startOfYear = utcCalendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return 1
        }
        return utcCalendar.dateComponents([.day], from: startOfYear, to: date).day ?? 1
    }
    
    /// 计算太阳赤纬（度）
    func getSolarDeclination() -> Double {
        let dayOfYear = getDayOfYear()
        // 春分大约在第81天（3月21日）
        // 太阳赤纬 = 23.45° * sin(360°/365 * (day - 81))
        return 23.45 * sin(2 * Double.pi / 365.0 * Double(dayOfYear - 81))
    }
    
    /// 计算太阳正午经度（度）
    func getSolarNoonLongitude() -> Double {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        let hour = Double(utcCalendar.component(.hour, from: date))
        let minute = Double(utcCalendar.component(.minute, from: date))
        let utcHours = hour + minute / 60.0
        
        // 太阳正午经度 = -(UTC时间 - 12) * 15度
        return -(utcHours - 12.0) * 15.0
    }
    
    /// 计算指定位置的太阳高度角（度）
    func getSunAltitude(latitude: Double, longitude: Double) -> Double {
        let declination = getSolarDeclination()
        let solarNoonLon = getSolarNoonLongitude()
        let hourAngle = longitude - solarNoonLon
        
        let latRad = latitude * Double.pi / 180.0
        let decRad = declination * Double.pi / 180.0
        let haRad = hourAngle * Double.pi / 180.0
        
        let sinAltitude = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        return asin(max(-1.0, min(1.0, sinAltitude))) * 180.0 / Double.pi
    }
    
    /// 判断指定位置是否为白天
    func isDaylight(latitude: Double, longitude: Double) -> Bool {
        return getSunAltitude(latitude: latitude, longitude: longitude) > 0
    }
    
    /// 判断北极是否为白天
    func isNorthSun() -> Bool {
        return isDaylight(latitude: 90, longitude: 0)
    }
    
    /// 获取昼夜分界线上的坐标点
    func getTerminatorCoordinates(precisionLng: Double = 5, precisionLat: Double = 1) -> [(lat: Double, lon: Double)] {
        let northSun = isNorthSun()
        var coords: [(lat: Double, lon: Double)] = []
        
        for lon in stride(from: -180.0, through: 180.0, by: precisionLng) {
            if let lat = getSunriseSunsetLatitude(lon: lon, northSun: northSun, precisionLat: precisionLat) {
                coords.append((lat: lat, lon: lon))
            }
        }
        
        return coords
    }
    
    private func getSunriseSunsetLatitude(lon: Double, northSun: Bool, precisionLat: Double) -> Double? {
        let startLat: Double
        let endLat: Double
        let delta: Double
        
        if northSun {
            startLat = -90
            endLat = 90
            delta = precisionLat
        } else {
            startLat = 90
            endLat = -90
            delta = -precisionLat
        }
        
        var lat = startLat
        var lastIsDaylight = !northSun
        
        while (delta > 0 && lat <= endLat) || (delta < 0 && lat >= endLat) {
            let daylight = isDaylight(latitude: lat, longitude: lon)
            
            if daylight && !lastIsDaylight {
                return lat
            }
            
            lastIsDaylight = daylight
            lat += delta
        }
        
        return northSun ? -90 : 90
    }
}

// MARK: - Night Overlay Shape Tests

final class NightOverlayShapeTests: XCTestCase {
    func testProductionEquinoxPathCoversNightLongitudesInBothHemispheres() {
        for hour in [0, 6, 12, 18] {
            let date = makeDate(year: 2026, month: 3, day: 23, hour: hour)
            let path = productionShape(date: date).path(in: worldBounds)
            let sun = SolarPositionCalculator(date: date)
            for latitude in [-60.0, -30.0, 30.0, 60.0] {
                for longitude in stride(from: -165.0, through: 165.0, by: 30.0) {
                    let expectedNight = sun.getSunAltitude(latitude: latitude, longitude: longitude) < 0
                    XCTAssertEqual(path.contains(project(latitude, longitude)), expectedNight,
                                   "UTC\(hour), lat=\(latitude), lon=\(longitude)")
                }
            }
        }
    }

    func testProductionPathsEveryDayAndHourOfCommonAndLeapYears() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let latitudes = stride(from: -80.0, through: 80.0, by: 20.0)
        let longitudes = [-179.0] + Array(stride(from: -172.0, through: 173.0, by: 15.0)) + [179.0]
        let samples = latitudes.flatMap { latitude in
            longitudes.map { longitude in
                (latitude, longitude, project(latitude, longitude))
            }
        }
        var checkedDays = 0
        var checkedPaths = 0
        var checkedPoints = 0
        var mismatches = 0
        var examples: [String] = []
        for year in [2026, 2028] {
            let start = makeDate(year: year, month: 1, day: 1, hour: 0)
            let end = makeDate(year: year + 1, month: 1, day: 1, hour: 0)
            var day = start
            while day < end {
                for hour in 0..<24 {
                    let date = day.addingTimeInterval(Double(hour * 3600 + 13 * 60))
                    let path = productionShape(date: date).path(in: worldBounds).cgPath
                    let sun = SolarPositionCalculator(date: date)
                    let dec = sun.getSolarDeclination() * .pi / 180
                    let noon = sun.getSolarNoonLongitude()
                    for (latitude, longitude, point) in samples {
                        let lat = latitude * .pi / 180
                        let ha = (longitude - noon) * .pi / 180
                        let altitude = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)) * 180 / .pi
                        // Avoid numerical ambiguity within half a degree of the geometric horizon.
                        guard abs(altitude) > 0.5 else { continue }
                        checkedPoints += 1
                        if path.contains(point) != (altitude < 0) {
                            mismatches += 1
                            if examples.count < 8 {
                                examples.append("\(date): lat=\(latitude), lon=\(longitude), altitude=\(altitude)")
                            }
                        }
                    }
                    checkedPaths += 1
                }
                checkedDays += 1
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        XCTAssertEqual(checkedDays, 731)
        XCTAssertEqual(checkedPaths, 17_544)
        XCTAssertGreaterThan(checkedPoints, 4_000_000)
        XCTAssertEqual(mismatches, 0, examples.joined(separator: "\n"))
        print("Production night-mask regression: \(checkedDays) days, \(checkedPaths) hourly paths, \(checkedPoints) classified points, \(mismatches) mismatches")
    }

    func testProductionPathAtScreenshotTime() {
        let date = makeDate(year: 2026, month: 9, day: 21, hour: 7, minute: 53)
        let path = productionShape(date: date).path(in: worldBounds)
        for (lat, lon, night) in [(39.9, 116.4, false), (51.5, -0.1, false),
                                   (40.7, -74.0, true), (34.1, -118.2, true)] {
            XCTAssertEqual(path.contains(project(lat, lon)), night)
        }
    }

    func testProductionPathRespectsProjectionAndViewport() {
        let bounds = CGRect(x: -150, y: -110, width: 310, height: 200)
        for month in [3, 6, 12] {
            let date = makeDate(year: 2026, month: month, day: 23, hour: 12)
            let shape = NightOverlayShape(
                date: date, mapBounds: bounds,
                transform: HCTransform(crs: "mill", scale: 180 / (.pi * 6371007.2), jsonres: 1,
                                       jsonmarginX: 17, jsonmarginY: 11, xoffset: 0, yoffset: 0),
                yMid: 19, viewHeight: bounds.height
            )
            let path = shape.path(in: bounds)
            let sun = SolarPositionCalculator(date: date)
            for lat in [-40.0, 40.0] {
                for lon in [-120.0, 0, 120] {
                    let point = project(lat, lon)
                    let shifted = CGPoint(x: point.x + 17, y: point.y + 27)
                    XCTAssertEqual(path.contains(shifted), sun.getSunAltitude(latitude: lat, longitude: lon) < 0)
                }
            }
            let viewTransform = CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 37, ty: 23)
            let transformed = path.applying(viewTransform)
            let point = CGPoint(x: 17, y: 27)
            XCTAssertEqual(path.contains(point), transformed.contains(point.applying(viewTransform)))
        }
    }

    func testProductionEquinoxBoundariesAndAntimeridian() {
        for hour in [0, 6, 12, 18] {
            let date = makeDate(year: 2026, month: 3, day: 23, hour: hour)
            let path = productionShape(date: date).path(in: worldBounds)
            let sun = SolarPositionCalculator(date: date)
            let noon = sun.getSolarNoonLongitude()
            var longitudes = [-179.999, 179.999]
            for boundary in [noon - 90, noon + 90] {
                for side in [-0.01, 0.01] {
                    let longitude = boundary + side
                    longitudes.append((longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
                }
            }
            for latitude in [-60.0, 0, 60] {
                for longitude in longitudes {
                    XCTAssertEqual(path.contains(project(latitude, longitude)),
                                   sun.getSunAltitude(latitude: latitude, longitude: longitude) < 0,
                                   "UTC\(hour) lat=\(latitude), lon=\(longitude)")
                }
            }
        }
    }

    func testProductionEquinoxPathClipsToViewport() {
        let date = makeDate(year: 2026, month: 3, day: 23, hour: 12)
        let viewport = CGRect(x: -130, y: -70, width: 260, height: 140)
        let path = productionShape(date: date, bounds: viewport).path(in: viewport)
        XCTAssertEqual(path.boundingRect, viewport)
        XCTAssertTrue(path.contains(CGPoint(x: 120, y: 60)))
        XCTAssertTrue(path.contains(CGPoint(x: -120, y: -60)))
        XCTAssertFalse(path.contains(CGPoint(x: 140, y: 0)))
        XCTAssertFalse(path.contains(CGPoint(x: -140, y: 0)))
        XCTAssertFalse(path.contains(CGPoint(x: 120, y: 80)))
        XCTAssertFalse(path.contains(CGPoint(x: -120, y: -80)))
        XCTAssertFalse(path.contains(.zero))
    }

    func testProductionPathIsEmptyWithoutProjection() {
        let shape = NightOverlayShape(date: Date(), mapBounds: worldBounds,
                                      transform: nil, yMid: 0, viewHeight: 264)
        XCTAssertTrue(shape.path(in: worldBounds).isEmpty)
    }

    private var worldBounds: CGRect {
        CGRect(x: -180, y: -132, width: 360, height: 264)
    }

    private func productionShape(date: Date, bounds: CGRect? = nil) -> NightOverlayShape {
        NightOverlayShape(
            date: date,
            mapBounds: bounds ?? worldBounds,
            transform: HCTransform(crs: "mill", scale: 180 / (.pi * 6371007.2), jsonres: 1,
                                   jsonmarginX: 0, jsonmarginY: 0, xoffset: 0, yoffset: 0),
            yMid: 0,
            viewHeight: 264
        )
    }

    private func project(_ latitude: Double, _ longitude: Double) -> CGPoint {
        CGPoint(x: longitude, y: -180 / .pi * 1.25 * log(tan(.pi / 4 + 0.4 * latitude * .pi / 180)))
    }

    // MARK: - Helper Methods
    
    /// 创建指定日期时间的 Date
    func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC")
        
        return Calendar(identifier: .gregorian).date(from: components)!
    }
    
    // MARK: - Solar Declination Tests (四季测试)
    
    /// 测试春分日（约3月21日）太阳赤纬应接近0
    func testVernalEquinoxsolarDeclination() {
        // 春分日（3月21日左右）
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        let declination = calculator.getSolarDeclination()
        
        // 春分日太阳赤纬应该接近0度（允许误差±1度）
        XCTAssert(abs(declination) < 1.5, "春分日太阳赤纬应接近0度，实际为: \(declination)度")
    }
    
    /// 测试夏至日（约6月22日）太阳赤纬应接近+23.45度
    func testSummerSolsticeSolarDeclination() {
        // 夏至日（6月22日左右）
        let date = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        let declination = calculator.getSolarDeclination()
        
        // 夏至日太阳赤纬应该接近+23.45度（允许误差±1度）
        XCTAssert(abs(declination - 23.45) < 1.5, "夏至日太阳赤纬应接近+23.45度，实际为: \(declination)度")
    }
    
    /// 测试秋分日（约9月23日）太阳赤纬应接近0度
    func testAutumnalEquinoxsolarDeclination() {
        // 秋分日（9月23日左右）
        let date = makeDate(year: 2026, month: 9, day: 23, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        let declination = calculator.getSolarDeclination()
        
        // 秋分日太阳赤纬应该接近0度（允许误差±1度）
        XCTAssert(abs(declination) < 1.5, "秋分日太阳赤纬应接近0度，实际为: \(declination)度")
    }
    
    /// 测试冬至日（约12月22日）太阳赤纬应接近-23.45度
    func testWinterSolsticeSolarDeclination() {
        // 冬至日（12月22日左右）
        let date = makeDate(year: 2026, month: 12, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        let declination = calculator.getSolarDeclination()
        
        // 冬至日太阳赤纬应该接近-23.45度（允许误差±1度）
        XCTAssert(abs(declination + 23.45) < 1.5, "冬至日太阳赤纬应接近-23.45度，实际为: \(declination)度")
    }
    
    // MARK: - Polar Day/Night Tests (极昼极夜测试)
    
    /// 测试夏至日北极圈内的极昼
    func testArcticPolarDay() {
        // 夏至日UTC 12:00
        let date = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 北极应该是白天
        XCTAssertTrue(calculator.isNorthSun(), "夏至日北极应该是白天（极昼）")
        
        // 北极圈（纬度66.5度）以上应该全天有阳光
        // 在UTC 12:00，太阳直射经度0度
        // 北纬70度、经度0度应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 70, longitude: 0), "夏至日北纬70度应该是白天")
        XCTAssertTrue(calculator.isDaylight(latitude: 80, longitude: 0), "夏至日北纬80度应该是白天")
        
        // 即使在UTC 00:00（太阳直射经度180度），北极仍然是白天
        let dateMidnight = makeDate(year: 2026, month: 6, day: 22, hour: 0)
        let calculatorMidnight = SolarPositionCalculator(date: dateMidnight)
        XCTAssertTrue(calculatorMidnight.isDaylight(latitude: 80, longitude: 180), "夏至日北纬80度即使在午夜也应该是白天")
    }
    
    /// 测试夏至日南极圈内的极夜
    func testAntarcticPolarNight() {
        // 夏至日UTC 12:00
        let date = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 南极应该是夜晚
        XCTAssertFalse(calculator.isDaylight(latitude: -90, longitude: 0), "夏至日南极应该是夜晚（极夜）")
        
        // 南极圈（纬度-66.5度）以下应该全天没有阳光
        XCTAssertFalse(calculator.isDaylight(latitude: -70, longitude: 0), "夏至日南纬70度应该是夜晚")
        XCTAssertFalse(calculator.isDaylight(latitude: -80, longitude: 0), "夏至日南纬80度应该是夜晚")
    }
    
    /// 测试冬至日北极圈内的极夜
    func testArcticPolarNight() {
        // 冬至日UTC 12:00
        let date = makeDate(year: 2026, month: 12, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 北极应该是夜晚
        XCTAssertFalse(calculator.isNorthSun(), "冬至日北极应该是夜晚（极夜）")
        
        // 北极圈以上应该全天没有阳光
        XCTAssertFalse(calculator.isDaylight(latitude: 70, longitude: 0), "冬至日北纬70度应该是夜晚")
    }
    
    /// 测试冬至日南极圈内的极昼
    func testAntarcticPolarDay() {
        // 冬至日UTC 12:00
        let date = makeDate(year: 2026, month: 12, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 南极应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: -90, longitude: 0), "冬至日南极应该是白天（极昼）")
        
        // 南极圈以上应该全天有阳光
        XCTAssertTrue(calculator.isDaylight(latitude: -70, longitude: 0), "冬至日南纬70度应该是白天")
    }
    
    // MARK: - 24 Hours Tests (24小时测试)
    
    /// 测试UTC 00:00时的昼夜分界
    func testMidnightTerminator() {
        // 春分日UTC 00:00
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 0)
        let calculator = SolarPositionCalculator(date: date)
        
        // 太阳正午经度应该接近180度（太阳直射国际日期变更线）
        let solarNoonLon = calculator.getSolarNoonLongitude()
        XCTAssert(abs(solarNoonLon - 180) < 15, "UTC 00:00太阳正午经度应接近180度，实际为: \(solarNoonLon)度")
        
        // 经度0度应该是夜晚
        XCTAssertFalse(calculator.isDaylight(latitude: 0, longitude: 0), "UTC 00:00经度0度应该是夜晚")
        
        // 经度180度应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 0, longitude: 180), "UTC 00:00经度180度应该是白天")
    }
    
    /// 测试UTC 06:00时的昼夜分界
    func testSunriseTerminator() {
        // 春分日UTC 06:00
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 6)
        let calculator = SolarPositionCalculator(date: date)
        
        // 太阳正午经度应该接近90度E
        let solarNoonLon = calculator.getSolarNoonLongitude()
        XCTAssert(abs(solarNoonLon - 90) < 15, "UTC 06:00太阳正午经度应接近90度E，实际为: \(solarNoonLon)度")
        
        // 经度90度E应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 0, longitude: 90), "UTC 06:00经度90度E应该是白天")
    }
    
    /// 测试UTC 12:00时的昼夜分界
    func testNoonTerminator() {
        // 春分日UTC 12:00
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 太阳正午经度应该接近0度
        let solarNoonLon = calculator.getSolarNoonLongitude()
        XCTAssert(abs(solarNoonLon) < 15, "UTC 12:00太阳正午经度应接近0度，实际为: \(solarNoonLon)度")
        
        // 经度0度应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 0, longitude: 0), "UTC 12:00经度0度应该是白天")
        
        // 经度180度应该是夜晚
        XCTAssertFalse(calculator.isDaylight(latitude: 0, longitude: 180), "UTC 12:00经度180度应该是夜晚")
    }
    
    /// 测试UTC 18:00时的昼夜分界
    func testSunsetTerminator() {
        // 春分日UTC 18:00
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 18)
        let calculator = SolarPositionCalculator(date: date)
        
        // 太阳正午经度应该接近-90度（90度W）
        let solarNoonLon = calculator.getSolarNoonLongitude()
        XCTAssert(abs(solarNoonLon + 90) < 15, "UTC 18:00太阳正午经度应接近-90度，实际为: \(solarNoonLon)度")
        
        // 经度-90度应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 0, longitude: -90), "UTC 18:00经度-90度应该是白天")
    }
    
    /// 测试24小时昼夜分界线连续性
    func test24HourTerminatorContinuity() {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        // 春分日测试24小时
        let baseDate = makeDate(year: 2026, month: 3, day: 21, hour: 0)
        
        var previousSolarNoonLon: Double = 0
        
        for hour in 0...23 {
            let date = utcCalendar.date(byAdding: .hour, value: hour, to: baseDate)!
            let calculator = SolarPositionCalculator(date: date)
            
            let solarNoonLon = calculator.getSolarNoonLongitude()
            
            // 太阳正午经度每小时应该向西移动约15度
            if hour > 0 {
                let expectedDiff = -15.0  // 向西移动
                let actualDiff = solarNoonLon - previousSolarNoonLon
                // 处理跨日期变更线的情况
                let normalizedDiff = actualDiff > 180 ? actualDiff - 360 : (actualDiff < -180 ? actualDiff + 360 : actualDiff)
                XCTAssert(abs(normalizedDiff - expectedDiff) < 2, "小时\(hour): 太阳正午经度变化应为约15度/小时，实际变化: \(normalizedDiff)度")
            }
            
            previousSolarNoonLon = solarNoonLon
        }
    }
    
    // MARK: - Terminator Curve Tests (昼夜分界线曲线测试)
    
    /// 测试昼夜分界线坐标范围
    func testTerminatorCoordinatesRange() {
        // 春分日UTC 12:00
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        let coords = calculator.getTerminatorCoordinates()
        
        // 应该有足够的坐标点
        XCTAssertGreaterThan(coords.count, 10, "昼夜分界线应该有足够的坐标点")
        
        // 所有纬度应该在有效范围内
        for coord in coords {
            XCTAssert(coord.lat >= -90 && coord.lat <= 90, "纬度\(coord.lat)应在[-90, 90]范围内")
            XCTAssert(coord.lon >= -180 && coord.lon <= 180, "经度\(coord.lon)应在[-180, 180]范围内")
        }
    }
    
    /// 测试昼夜分界线在赤道附近应该接近经线
    func testTerminatorNearEquator() {
        // 春分日UTC 12:00，太阳直射赤道
        // 昼夜分界线应该大致沿着经线（日出线约在经度-90，日落线约在经度90）
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 检查赤道上的昼夜分界
        // UTC 12:00太阳直射经度0度
        // 日出线应该在经度-90度附近，日落线在经度90度附近
        
        // 赤道、经度0度应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 0, longitude: 0), "春分日UTC 12:00赤道经度0度应该是白天")
        
        // 赤道、经度-90度应该是夜晚边缘
        let alt1 = calculator.getSunAltitude(latitude: 0, longitude: -90)
        XCTAssert(abs(alt1) < 5, "赤道经度-90度太阳高度应接近0，实际为: \(alt1)度")
        
        // 赤道、经度90度应该是夜晚边缘
        let alt2 = calculator.getSunAltitude(latitude: 0, longitude: 90)
        XCTAssert(abs(alt2) < 5, "赤道经度90度太阳高度应接近0，实际为: \(alt2)度")
    }
    
    /// 测试夏至日昼夜分界线形状
    func testTerminatorShapeSummerSolstice() {
        // 夏至日UTC 12:00
        let date = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        let coords = calculator.getTerminatorCoordinates()
        
        // 北极应该是白天
        XCTAssertTrue(calculator.isNorthSun(), "夏至日北极应该是白天")
        
        // 昼夜分界线应该覆盖到北极圈以上
        let maxLat = coords.map { $0.lat }.max() ?? 0
        let minLat = coords.map { $0.lat }.min() ?? 0
        
        // 夏至日，北极圈内全天白昼，所以昼夜分界线最高纬度应该在北极圈附近
        // 注意：由于我们是从南向北找第一个白天点，所以maxLat应该是昼夜分界线最高纬度
        XCTAssertGreaterThan(maxLat, 60, "夏至日昼夜分界线最高纬度应该高于60度")
    }
    
    // MARK: - Integration Tests (集成测试)
    
    /// 测试一年的昼夜变化
    func testYearlyTerminatorVariation() {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        // 每月21日测试
        let months = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        
        for month in months {
            let date = makeDate(year: 2026, month: month, day: 21, hour: 12)
            let calculator = SolarPositionCalculator(date: date)
            
            let declination = calculator.getSolarDeclination()
            let coords = calculator.getTerminatorCoordinates()
            
            // 验证坐标点数量
            XCTAssertGreaterThan(coords.count, 10, "月份\(month): 昼夜分界线应该有足够的坐标点")
            
            // 验证太阳赤纬在合理范围内
            XCTAssert(declination >= -24 && declination <= 24, "月份\(month): 太阳赤纬\(declination)应在[-24, 24]度范围内")
            
            print("月份\(month): 太阳赤纬 = \(String(format: "%.2f", declination))度, 昼夜分界线点数 = \(coords.count)")
        }
    }
    
    /// 测试城市昼夜状态
    func testCityDaylightStatus() {
        // 选取几个主要城市，验证昼夜状态
        
        // 北京: 39.9°N, 116.4°E
        // 纽约: 40.7°N, 74.0°W
        // 伦敦: 51.5°N, 0.1°W
        // 悉尼: 33.9°S, 151.2°E
        
        // 春分日UTC 12:00
        let date = makeDate(year: 2026, month: 3, day: 21, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // UTC 12:00太阳直射经度0度附近
        // 伦敦（经度接近0）应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 51.5, longitude: -0.1), "春分日UTC 12:00伦敦应该是白天")
        
        // 北京（经度116.4E）应该是傍晚
        // UTC 12:00时，北京地方时约为20:00，应该是夜晚
        XCTAssertFalse(calculator.isDaylight(latitude: 39.9, longitude: 116.4), "春分日UTC 12:00北京应该是夜晚")
        
        // 纽约（经度74.0W）应该是凌晨
        // UTC 12:00时，纽约地方时约为07:00，应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 40.7, longitude: -74.0), "春分日UTC 12:00纽约应该是白天")
        
        // 悉尼（经度151.2E）
        // UTC 12:00时，悉尼地方时约为22:00，应该是夜晚
        XCTAssertFalse(calculator.isDaylight(latitude: -33.9, longitude: 151.2), "春分日UTC 12:00悉尼应该是夜晚")
    }
    
    // MARK: - Edge Cases (边界情况测试)
    
    /// 测试极昼极夜边界
    func testPolarCircleBoundary() {
        // 北极圈纬度约66.5度
        // 夏至日，北极圈应该全天白天
        
        let date = makeDate(year: 2026, month: 6, day: 22, hour: 12)
        let calculator = SolarPositionCalculator(date: date)
        
        // 在UTC 12:00（太阳直射经度0度）
        // 北极圈纬度66.5度、经度0度应该是白天
        XCTAssertTrue(calculator.isDaylight(latitude: 66.5, longitude: 0), "夏至日UTC 12:00北极圈应该是白天")
        
        // 测试极昼：在UTC 00:00，太阳直射180度，检查北极圈内是否仍然有阳光
        // 注意：北极圈内是否全天白天取决于纬度是否高于90-23.45=66.55度
        let dateMidnight = makeDate(year: 2026, month: 6, day: 22, hour: 0)
        let calculatorMidnight = SolarPositionCalculator(date: dateMidnight)
        
        // 在纬度70度（北极圈内），经度0度（远离太阳直射点）
        // 夏至日，由于极昼，应该仍然是白天
        XCTAssertTrue(calculatorMidnight.isDaylight(latitude: 70, longitude: 0), "夏至日UTC 00:00北纬70度应该是白天（极昼）")
    }
    
    /// 测试日出日落时间准确性
    func testSunriseSunsetAccuracy() {
        // 春分日，太阳直射赤道
        // 太阳正午经度 = -(UTC - 12) * 15度
        
        // UTC 06:00时，太阳正午经度 = -(6-12)*15 = 90度E
        // 此时经度90E是正午（太阳高度最大）
        // 日出位置在太阳正午经度西侧90度 = 0度经线
        
        let date1 = makeDate(year: 2026, month: 3, day: 21, hour: 6)
        let calculator1 = SolarPositionCalculator(date: date1)
        
        // 经度0度应该是日出（太阳高度接近0）
        let alt1 = calculator1.getSunAltitude(latitude: 0, longitude: 0)
        XCTAssert(abs(alt1) < 2, "春分日UTC 06:00赤道经度0度太阳高度应接近0，实际为: \(alt1)度")
        
        // UTC 18:00时，太阳正午经度 = -(18-12)*15 = -90度（90度W）
        // 此时经度-90度（90W）是正午
        // 日落位置在太阳正午经度东侧90度 = 180度经线（日期变更线）
        
        let date2 = makeDate(year: 2026, month: 3, day: 21, hour: 18)
        let calculator2 = SolarPositionCalculator(date: date2)
        
        // 经度180度应该是日落（太阳高度接近0）
        let alt2 = calculator2.getSunAltitude(latitude: 0, longitude: 180)
        XCTAssert(abs(alt2) < 2, "春分日UTC 18:00赤道经度180度太阳高度应接近0，实际为: \(alt2)度")
    }
}
