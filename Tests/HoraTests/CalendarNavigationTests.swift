import XCTest
import SwiftUI
@testable import Hora

@MainActor
final class CalendarNavigationTests: XCTestCase {
    func testPreviousAndNextMonthWithinYear() {
        let model = CalendarViewModel()
        model.currentDate = date(2026, 6, 15)

        model.previousMonth()
        XCTAssertEqual(model.currentDate, date(2026, 5, 15))

        model.nextMonth()
        XCTAssertEqual(model.currentDate, date(2026, 6, 15))
    }

    func testNavigationAcrossYearBoundary() {
        let model = CalendarViewModel()
        model.currentDate = date(2026, 1, 15)

        model.previousMonth()
        XCTAssertEqual(model.currentDate, date(2025, 12, 15))

        model.nextMonth()
        XCTAssertEqual(model.currentDate, date(2026, 1, 15))
    }

    func testJanuary31NavigatesToFebruaryInCommonYear() {
        let model = CalendarViewModel()
        model.currentDate = date(2026, 1, 31)

        model.nextMonth()

        XCTAssertEqual(model.currentDate, date(2026, 2, 28))
    }

    func testJanuary31NavigatesToFebruaryInLeapYear() {
        let model = CalendarViewModel()
        model.currentDate = date(2024, 1, 31)

        model.nextMonth()

        XCTAssertEqual(model.currentDate, date(2024, 2, 29))
    }

    func testMonthNavigationDoesNotChangeSelectedDate() {
        let model = CalendarViewModel()
        let selectedDate = date(2024, 1, 31)
        model.selectedDate = selectedDate
        model.currentDate = selectedDate

        for _ in 0..<14 {
            model.nextMonth()
            XCTAssertEqual(model.selectedDate, selectedDate)
        }
        for _ in 0..<14 {
            model.previousMonth()
            XCTAssertEqual(model.selectedDate, selectedDate)
        }
    }

    func testSixRowMonthFitsAvailableGridHeight() {
        let model = CalendarViewModel()
        // March 2026 starts on Sunday and needs six Monday-first rows.
        model.currentDate = date(2026, 3, 15)
        let host = NSHostingController(rootView: CalendarGridView(viewModel: model))

        let size = host.sizeThatFits(in: CGSize(width: 324, height: 302))

        XCTAssertEqual(size.width, 324, accuracy: 0.5)
        XCTAssertLessThanOrEqual(size.height, 302.5, "Six rows must not overlap the navigation buttons")
    }

    func testDefaultDayCellKeeps54PointOuterHeight() {
        let day = date(2026, 3, 15)
        let host = NSHostingController(rootView: CompactDayCell(
            date: day,
            isSelected: false,
            isToday: false,
            currentMonth: day,
            onTap: {}
        ))

        let size = host.sizeThatFits(in: CGSize(width: 300.0 / 7, height: 100))

        XCTAssertEqual(size.height, 54, accuracy: 0.5, "The outer cell, not only its background, must have a fixed height")
    }

    func testNativeCalendarRenderingForFourFiveAndSixRows() throws {
        for (year, month, rows) in [(2027, 2, 4), (2026, 9, 5), (2026, 3, 6)] {
            let model = CalendarViewModel()
            model.currentDate = date(year, month, 15)
            model.selectedDate = model.currentDate
            let renderer = ImageRenderer(content: CalendarGridView(viewModel: model)
                .frame(width: 324, height: 302)
                .background(.white))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 648)
            XCTAssertEqual(image.height, 604)
            try saveSnapshot(image, name: "calendar-\(rows)-rows")
        }
    }

    func testNativePopoverRenderingAtFixedSize() throws {
        let renderer = ImageRenderer(content: CalendarPopoverView().frame(width: 500, height: 380))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 1000)
        XCTAssertEqual(image.height, 760)
        try saveSnapshot(image, name: "calendar-popover")
    }

    private func saveSnapshot(_ image: CGImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HORA_UI_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent(name).appendingPathExtension("png"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
