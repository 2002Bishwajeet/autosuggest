import XCTest
@testable import AutoSuggestApp

final class ModelCompatibilityAdvisorTests: XCTestCase {
    func test8GBDeviceRecommendsSmallModels() {
        let advisor = ModelCompatibilityAdvisor()
        let report = advisor.buildReport(
            totalMemoryGB: 8.0,
            availableMemoryGB: 6.0,
            runtimeOrder: ["coreml", "ollama", "llama.cpp"],
            installedModels: []
        )

        XCTAssertEqual(report.recommendedMaxParamsB, 3.0)
        XCTAssertEqual(report.hardMaxParamsB, 4.0)
    }

    func testLowAvailableMemoryDownshiftsRecommendation() {
        let advisor = ModelCompatibilityAdvisor()
        let report = advisor.buildReport(
            totalMemoryGB: 24.0,
            availableMemoryGB: 1.5,
            runtimeOrder: ["coreml"],
            installedModels: []
        )

        XCTAssertEqual(report.recommendedMaxParamsB, 1.5)
        XCTAssertEqual(report.hardMaxParamsB, 3.0)
    }

    func testInstalledModelAssessmentFlagsLargeModel() {
        let advisor = ModelCompatibilityAdvisor()
        let report = advisor.buildReport(
            totalMemoryGB: 8.0,
            availableMemoryGB: 6.0,
            runtimeOrder: ["coreml"],
            installedModels: [
                InstalledModel(
                    id: "qwen2.5-7b",
                    version: "1.0.0",
                    path: URL(fileURLWithPath: "/tmp/qwen2.5-7b-1.0.0")
                ),
            ]
        )

        XCTAssertEqual(report.installedAssessments.count, 1)
        XCTAssertEqual(report.installedAssessments[0].verdict, "Not Recommended")
    }
}
