import XCTest
@testable import AIFileCore
@testable import AIFileUI

final class TaskBoardRerunTests: XCTestCase {
    
    @MainActor
    func testRerunTaskCallbackRestoresOriginalTargetFilesAndPrompt() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("hardware_list.xlsx")
        try? "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        let viewModel = PanelViewModel()
        let prompt = "转成 PDF 文件"
        let plan = ExecutionPlan(summary: "转成 PDF", actions: [
            FileActionItem(operationType: .convertToPDF, sourceURL: testFile, targetURL: tempDir.appendingPathComponent("hardware_list.pdf"), detailDescription: "转为 PDF")
        ])
        
        let record = TaskExecutionRecord(
            prompt: prompt,
            status: .completed,
            plan: plan,
            targetFilePaths: [testFile.path]
        )
        
        // 初始设置 viewModel 为不相关的文件
        let dummyFile = tempDir.appendingPathComponent("dummy.png")
        try? "dummy".write(to: dummyFile, atomically: true, encoding: .utf8)
        viewModel.setTargetURLs([dummyFile])
        XCTAssertEqual(viewModel.fileItems.first?.name, "dummy.png")
        
        // 触发再次执行
        viewModel.rerunTask(record)
        
        // 验证：目标文件已成功切回硬件清单 xlsx，且 inputText 已填入 prompt
        XCTAssertEqual(viewModel.inputText, prompt)
        XCTAssertEqual(viewModel.fileItems.first?.name, "hardware_list.xlsx")
    }
}
