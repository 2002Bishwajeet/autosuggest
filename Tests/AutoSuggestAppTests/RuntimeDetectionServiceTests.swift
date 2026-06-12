import XCTest
@testable import AutoSuggestApp

final class RuntimeDetectionServiceTests: XCTestCase {
    func testNotInstalledWhenNoBinary() async {
        let service = RuntimeDetectionService(
            binaryExists: { _ in false },
            processRunning: { _ in true }
        )
        let status = await service.status(for: .ollama)
        XCTAssertEqual(status, .notInstalled)
    }

    func testInstalledNotRunning() async {
        let service = RuntimeDetectionService(
            binaryExists: { _ in true },
            processRunning: { _ in false }
        )
        let status = await service.status(for: .ollama)
        XCTAssertEqual(status, .installedNotRunning)
    }

    func testRunning() async {
        let service = RuntimeDetectionService(
            binaryExists: { _ in true },
            processRunning: { _ in true }
        )
        let status = await service.status(for: .llamaServer)
        XCTAssertEqual(status, .running)
    }
}
