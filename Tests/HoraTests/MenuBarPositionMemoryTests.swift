import XCTest
@testable import Hora

@MainActor
final class MenuBarPositionMemoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var current: [String: [String: Double]] = [:]
    private var writes: [(bundleID: String, positions: [String: Double])] = []

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "com.hora.tests.position-memory.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        current = [:]
        writes = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    func testCaptureKeepsOnlyStatusItemPositionKeys() {
        current["com.example.visible"] = [
            "NSStatusItem Preferred Position statusItem": 351,
            "NSStatusItem Visible statusItem": 1,
            "UnrelatedPreference": 99,
        ]
        let memory = makeMemory()

        memory.capture(bundleID: "com.example.visible")

        XCTAssertEqual(
            memory.savedPositions(for: "com.example.visible"),
            ["NSStatusItem Preferred Position statusItem": 351]
        )
    }

    func testRestoreWritesBackPositionsDeletedByTheAppOnQuit() {
        current["com.example.visible"] = ["NSStatusItem Preferred Position statusItem": 351]
        let memory = makeMemory()
        memory.capture(bundleID: "com.example.visible")

        current["com.example.visible"] = [:]
        memory.restore(bundleID: "com.example.visible")

        XCTAssertEqual(
            current["com.example.visible"]?["NSStatusItem Preferred Position statusItem"],
            351
        )
    }

    func testSnapshotSurvivesMemoryRecreation() {
        current["com.example.visible"] = ["NSStatusItem Preferred Position statusItem": 351]
        let first = makeMemory()
        first.capture(bundleID: "com.example.visible")
        first.persistNow()

        current["com.example.visible"] = [:]
        let second = makeMemory()
        second.restore(bundleID: "com.example.visible")

        XCTAssertEqual(
            current["com.example.visible"]?["NSStatusItem Preferred Position statusItem"],
            351
        )
    }

    func testRestoreWithoutSnapshotDoesNotWrite() {
        let memory = makeMemory()

        memory.restore(bundleID: "com.example.visible")

        XCTAssertTrue(writes.isEmpty)
    }

    func testCaptureAllSkipsSystemAndOwnApps() {
        current["com.example.visible"] = ["NSStatusItem Preferred Position Item-0": 351]
        current["com.apple.controlcenter"] = ["NSStatusItem Preferred Position Clock": 73]
        let memory = makeMemory(
            runningBundleIDs: { ["com.example.visible", "com.apple.controlcenter", "com.hora.app"] },
            ownBundleID: "com.hora.app"
        )

        memory.captureAll()

        XCTAssertNotNil(memory.savedPositions(for: "com.example.visible"))
        XCTAssertNil(memory.savedPositions(for: "com.apple.controlcenter"))
        XCTAssertNil(memory.savedPositions(for: "com.hora.app"))
    }

    func testTickRestoresPositionsWhenRunningAppDisappears() {
        var running = ["com.example.visible"]
        current["com.example.visible"] = ["NSStatusItem Preferred Position statusItem": 351]
        let memory = makeMemory(runningBundleIDs: { running })
        memory.captureAll()

        running = []
        memory.tick()

        XCTAssertEqual(
            current["com.example.visible"]?["NSStatusItem Preferred Position statusItem"],
            351
        )
    }

    func testRestoreKeepsAPositionTheAppStillHas() {
        current["com.example.visible"] = ["NSStatusItem Preferred Position statusItem": 351]
        let memory = makeMemory()
        memory.capture(bundleID: "com.example.visible")

        current["com.example.visible"]?["NSStatusItem Preferred Position statusItem"] = 200
        memory.restore(bundleID: "com.example.visible")

        XCTAssertEqual(
            current["com.example.visible"]?["NSStatusItem Preferred Position statusItem"],
            200
        )
    }

    private func makeMemory(
        runningBundleIDs: @escaping () -> [String] = { [] },
        ownBundleID: String = "com.hora.app"
    ) -> MenuBarPositionMemory {
        MenuBarPositionMemory(
            defaults: defaults,
            ownBundleID: ownBundleID,
            runningBundleIDs: runningBundleIDs,
            readPositions: { [unowned self] bundleID in current[bundleID] ?? [:] },
            writePositions: { [unowned self] bundleID, positions in
                writes.append((bundleID, positions))
                current[bundleID] = positions
            }
        )
    }
}
