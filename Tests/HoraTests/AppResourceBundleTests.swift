import XCTest
@testable import Hora

final class AppResourceBundleTests: XCTestCase {
    func testDevelopmentResourcesAreAvailable() throws {
        let resources = AppInfo.resourceBundle()
        for (name, ext) in [("Cities", "json"), ("world", "json"), ("countryTimezones", "json"),
                            ("cities24tz", "json"), ("worldclock", "html"), ("Localizable", "xcstrings")] {
            XCTAssertNotNil(resources.url(forResource: name, withExtension: ext), "\(name).\(ext)")
        }
    }

    func testInstalledResourcesAreResolvedWithoutWritingToAppRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Hora.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources/Hora_Hora.bundle")
        try FileManager.default.createDirectory(at: resources.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.hora.resource-test",
            "CFBundlePackageType": "APPL",
            "CFBundleName": "Hora"
        ], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.copyItem(at: AppInfo.resourceBundle().bundleURL, to: resources)
        let bundle = try XCTUnwrap(Bundle(url: app))

        let resolved = AppInfo.resourceBundle(in: bundle)

        XCTAssertEqual(resolved.bundleURL.standardizedFileURL, resources.standardizedFileURL)
        XCTAssertNotNil(resolved.url(forResource: "Cities", withExtension: "json"))
        XCTAssertNotNil(resolved.url(forResource: "worldclock", withExtension: "html"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: app.path), ["Contents"])
    }
}
