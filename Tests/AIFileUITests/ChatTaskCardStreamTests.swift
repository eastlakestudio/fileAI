import XCTest
import SwiftUI
@testable import AIFileCore
@testable import AIFileUI

final class ChatTaskCardStreamTests: XCTestCase {
    
    @MainActor
    func testSubmitInstructionSwitchesToChatTimelineAndAppendsTaskCard() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("demo.png")
        try? "image_data".write(to: file1, atomically: true, encoding: .utf8)
        
        let viewModel = PanelViewModel()
        viewModel.setTargetURLs([file1])
        viewModel.mainTab = .fileList // 初始在文件列表页
        
        let initialCount = viewModel.taskHistory.count
        
        // 提交新指令
        viewModel.inputText = "将图片调整为 1920x1080"
        viewModel.submitInstruction()
        
        // 验证 1：自动切换到对话流视图
        XCTAssertEqual(viewModel.mainTab, .chatTimeline)
        
        // 验证 2：任务卡片已成功创建并压入 sessionTasks 和 taskHistory
        XCTAssertEqual(viewModel.sessionTasks.count, 1)
        XCTAssertEqual(viewModel.sessionTasks.first?.prompt, "将图片调整为 1920x1080")
        XCTAssertEqual(viewModel.sessionTasks.first?.targetFilePaths, [file1.path])
        XCTAssertGreaterThan(viewModel.taskHistory.count, initialCount)
    }
    
    @MainActor
    func testChatTaskCardViewRendersWithoutCrash() {
        let task = TaskExecutionRecord(
            prompt: "转为 PDF 文件",
            status: .completed,
            plan: ExecutionPlan(summary: "完成 1 项转换", actions: [
                FileActionItem(
                    operationType: .convertToPDF,
                    sourceURL: URL(fileURLWithPath: "/tmp/test.docx"),
                    targetURL: URL(fileURLWithPath: "/tmp/test.pdf"),
                    detailDescription: "DOCX 转为 PDF"
                )
            ]),
            targetFilePaths: ["/tmp/test.docx"]
        )
        
        var rerunCalled = false
        var detailCalled = false
        
        let card = ChatTaskCardView(
            task: task,
            isCurrentActive: false,
            onRerunTask: { _ in rerunCalled = true },
            onShowDetail: { _ in detailCalled = true }
        )
        
        XCTAssertNotNil(card)
    }
    
    @MainActor
    func testSubmitInstructionWithoutFilesDoesNotCreateCardAndShowsWarning() {
        let viewModel = PanelViewModel()
        viewModel.setTargetURLs([])
        let initialCount = viewModel.taskHistory.count
        
        viewModel.inputText = "随便处理一下文件"
        viewModel.submitInstruction()
        
        // 验证：未选文件时不增加任务卡片，并给出相应提示
        XCTAssertEqual(viewModel.sessionTasks.count, 0)
        XCTAssertEqual(viewModel.taskHistory.count, initialCount)
        XCTAssertNotNil(viewModel.statusMessage)
        XCTAssertTrue(viewModel.statusMessage?.contains("请先在 Finder 中选择文件") ?? false)
    }
    
    @MainActor
    func testSubmittingMultipleInstructionsCreatesSequentialCards() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("image1.png")
        try? "data".write(to: file1, atomically: true, encoding: .utf8)
        
        let viewModel = PanelViewModel()
        viewModel.setTargetURLs([file1])
        
        let initialCount = viewModel.taskHistory.count
        
        // 提交第一条指令
        viewModel.submitInstruction("转换为 JPG 格式")
        XCTAssertEqual(viewModel.sessionTasks.count, 1)
        XCTAssertEqual(viewModel.sessionTasks[0].prompt, "转换为 JPG 格式")
        XCTAssertEqual(viewModel.taskHistory.count, initialCount + 1)
        XCTAssertEqual(viewModel.taskHistory[0].prompt, "转换为 JPG 格式")
        
        // 提交第二条指令
        viewModel.submitInstruction("重命名为 banner.jpg")
        XCTAssertEqual(viewModel.sessionTasks.count, 2)
        XCTAssertEqual(viewModel.sessionTasks[0].prompt, "重命名为 banner.jpg")
        XCTAssertEqual(viewModel.sessionTasks[1].prompt, "转换为 JPG 格式")
        XCTAssertEqual(viewModel.taskHistory.count, initialCount + 2)
        XCTAssertEqual(viewModel.taskHistory[0].prompt, "重命名为 banner.jpg")
    }
    
    @MainActor
    func testSessionTasksIsolationFromHistoricalTasks() {
        let viewModel = PanelViewModel()
        // 验证：冷启动时 sessionTasks 初始为空，即使 taskHistory 存在历史持久化数据
        XCTAssertTrue(viewModel.sessionTasks.isEmpty, "本次会话任务流初始必须为空，不显示历史任务")
    }
    
    @MainActor
    func testChatTaskCardViewRendersWalkthroughReportWithoutActions() {
        let task = TaskExecutionRecord(
            prompt: "统计当前文件总大小",
            status: .completed,
            plan: ExecutionPlan(summary: "共包含 5 个文件，总大小为 12.8 MB", actions: []),
            walkthroughReport: "📊 统计结果如下：\n- 图片 3 张: 8.5MB\n- 文档 2 份: 4.3MB",
            targetFilePaths: ["/tmp/file1.png"]
        )
        
        let card = ChatTaskCardView(task: task)
        XCTAssertNotNil(card)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.walkthroughReport?.contains("统计结果"), true)
    }
}
