import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent
@testable import AIFileUI

@MainActor
final class ModernChatInputCardViewTests: XCTestCase {
    
    func testPanelViewModelFileCapsuleRemovalAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let url1 = tempDir.appendingPathComponent("doc1.pdf")
        let url2 = tempDir.appendingPathComponent("photo2.png")
        try "PDF Data".write(to: url1, atomically: true, encoding: .utf8)
        try "PNG Data".write(to: url2, atomically: true, encoding: .utf8)
        
        let vm = PanelViewModel(dispatcher: AgentDispatcher(provider: MockLLMClient(), registry: SkillRegistry()))
        vm.setTargetURLs([url1, url2])
        
        XCTAssertEqual(vm.fileItems.count, 2)
        
        if let firstId = vm.fileItems.first?.id {
            vm.removeFileItem(id: firstId)
            XCTAssertEqual(vm.fileItems.count, 1)
            XCTAssertEqual(vm.fileItems.first?.name, "photo2.png")
        }
        
        vm.clearSelectedFiles()
        XCTAssertTrue(vm.fileItems.isEmpty)
    }
    
    func testPanelViewModelExecutionModeAndReasoningEffort() {
        let vm = PanelViewModel(dispatcher: AgentDispatcher(provider: MockLLMClient(), registry: SkillRegistry()))
        
        XCTAssertEqual(vm.executionMode, "Agent 模式")
        XCTAssertEqual(vm.reasoningEffort, "High")
        
        vm.executionMode = "极速模式"
        vm.reasoningEffort = "Low"
        
        XCTAssertEqual(vm.executionMode, "极速模式")
        XCTAssertEqual(vm.reasoningEffort, "Low")
    }
}
