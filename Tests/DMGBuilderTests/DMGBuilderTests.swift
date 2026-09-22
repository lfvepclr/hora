import XCTest
@testable import DMGBuilderExec

final class DMGBuilderTests: XCTestCase {
    func testSuccessfulCommandReturnsZero() throws {
        XCTAssertEqual(try DMGBuilder.shell("/usr/bin/true", arguments: []), 0)
    }

    func testFailedCommandThrowsInsteadOfReportingSuccess() {
        XCTAssertThrowsError(try DMGBuilder.shell("/usr/bin/false", arguments: [])) { error in
            XCTAssertEqual((error as NSError).code, 1)
        }
    }
}
