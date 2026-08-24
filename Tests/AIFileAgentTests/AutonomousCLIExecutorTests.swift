import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class AutonomousCLIExecutorTests: XCTestCase {
    
    func testAutonomousExecutionPlanCreationWithNewFileDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sampleFile = tempDir.appendingPathComponent("document.txt")
        try "Test Content".write(to: sampleFile, atomically: true, encoding: .utf8)
        
        // 创建一个模拟的 CLI 脚本（执行时生成 output.zip）
        let scriptPath = tempDir.appendingPathComponent("mock_cli.sh")
        let scriptContent = """
        #!/bin/bash
        touch "\(tempDir.path)/output.zip"
        echo "Successfully created archive"
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        let mockTool = DiscoveredCLITool(
            type: .antigravity,
            executablePath: scriptPath.path,
            isInstalled: true
        )
        
        let fileItem = FileItem(url: sampleFile, isDirectory: false)
        let plan = try await AutonomousCLIExecutor.execute(
            tool: mockTool,
            userPrompt: "打包压缩",
            fileItems: [fileItem]
        )
        
        XCTAssertTrue(plan.summary.contains("已自主完成操作"))
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.targetURL?.lastPathComponent, "output.zip")
    }
    
    func testAutonomousExecutionFailureTriggersSystemHandover() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sampleFile = tempDir.appendingPathComponent("document.txt")
        try "Content".write(to: sampleFile, atomically: true, encoding: .utf8)
        
        // 创建一个模拟失败并输出 unknown command 的脚本
        let scriptPath = tempDir.appendingPathComponent("failing_cli.sh")
        let scriptContent = """
        #!/bin/bash
        echo "Error: unknown command send for lark-cli" >&2
        exit 1
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        let mockTool = DiscoveredCLITool(
            type: .codebuddy,
            executablePath: scriptPath.path,
            isInstalled: true
        )
        
        let fileItem = FileItem(url: sampleFile, isDirectory: false)
        let plan = try await AutonomousCLIExecutor.execute(
            tool: mockTool,
            userPrompt: "飞书发送",
            fileItems: [fileItem]
        )
        
        // 验证自动触发系统接管并输出澄清反问
        XCTAssertTrue(plan.isAwaitingClarification)
        XCTAssertEqual(plan.clarification?.options.first?.id, "retry_safe_pipeline")
    }
}
