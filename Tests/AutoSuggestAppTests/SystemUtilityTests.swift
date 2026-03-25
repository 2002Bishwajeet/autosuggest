import XCTest
@testable import AutoSuggestApp

final class SystemUtilityTests: XCTestCase {

    // MARK: - AppDirectories

    func testApplicationSupportURLDoesNotThrow() throws {
        let url = try AppDirectories.applicationSupportURL()
        XCTAssertFalse(url.path.isEmpty)
    }

    func testAppSupportDirectoryIncludesAppName() throws {
        let url = try AppDirectories.appSupportDirectory()
        XCTAssertTrue(url.path.contains("AutoSuggestApp"))
    }

    // MARK: - BatteryMonitor

    func testBatteryAlwaysOnNeverPauses() {
        let monitor = BatteryMonitor()
        XCTAssertFalse(monitor.shouldPauseSuggestions(mode: .alwaysOn))
    }

    // MARK: - MemorySnapshot

    func testMemorySnapshotTotalGB() {
        let snapshot = MemorySnapshot(totalBytes: 8_589_934_592, availableBytes: nil)
        XCTAssertEqual(snapshot.totalGB, 8.0, accuracy: 0.001)
    }

    func testMemorySnapshotAvailableGB() {
        let snapshot = MemorySnapshot(
            totalBytes: 17_179_869_184,
            availableBytes: 4_294_967_296
        )
        XCTAssertEqual(snapshot.availableGB!, 4.0, accuracy: 0.001)
    }

    func testMemorySnapshotNilAvailable() {
        let snapshot = MemorySnapshot(totalBytes: 8_589_934_592, availableBytes: nil)
        XCTAssertNil(snapshot.availableGB)
    }

    // MARK: - SystemResourceMonitor

    func testSystemResourceMonitorReturnsSnapshot() {
        let monitor = SystemResourceMonitor()
        let snapshot = monitor.memorySnapshot()
        XCTAssertGreaterThan(snapshot.totalBytes, 0)
    }
}
