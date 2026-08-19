import XCTest
@testable import AIFileCore
@testable import AIFileUI

final class OutputFileLocatorTests: XCTestCase {
    
    @MainActor
    func testPanelViewModelLatestOutputURLsManagement() {
        let viewModel = PanelViewModel()
        let sampleURL = URL(fileURLWithPath: "/tmp/sample_output.pdf")
        
        XCTAssertTrue(viewModel.latestOutputURLs.isEmpty)
        
        viewModel.latestOutputURLs = [sampleURL]
        XCTAssertEqual(viewModel.latestOutputURLs.count, 1)
        XCTAssertEqual(viewModel.latestOutputURLs.first?.lastPathComponent, "sample_output.pdf")
    }
    
    func testOutputURLsExtractionFromTaskPlan() {
        let sourceURL = URL(fileURLWithPath: "/tmp/input.docx")
        let targetURL = URL(fileURLWithPath: "/tmp/input.pdf")
        
        let action = FileActionItem(
            operationType: .convertToPDF,
            sourceURL: sourceURL,
            targetURL: targetURL,
            detailDescription: "DOCX 转 PDF"
        )
        
        let plan = ExecutionPlan(summary: "转换完成", actions: [action])
        let record = TaskExecutionRecord(
            prompt: "转为 PDF",
            status: .completed,
            plan: plan
        )
        
        let outputURLs = record.plan.actions.compactMap { $0.targetURL ?? $0.sourceURL }
        XCTAssertEqual(outputURLs.count, 1)
        XCTAssertEqual(outputURLs.first, targetURL)
    }
}
