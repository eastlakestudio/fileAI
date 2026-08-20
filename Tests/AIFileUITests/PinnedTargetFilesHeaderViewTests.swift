import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent
@testable import AIFileUI

@MainActor
final class PinnedTargetFilesHeaderViewTests: XCTestCase {
    
    func testPinnedHeaderHandlesMultipleFilesAndDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let subFolder = tempDir.appendingPathComponent("DocumentsFolder")
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        
        let file1 = tempDir.appendingPathComponent("Report.pdf")
        let file2 = tempDir.appendingPathComponent("Diagram.png")
        try "PDF Data".write(to: file1, atomically: true, encoding: .utf8)
        try "PNG Data".write(to: file2, atomically: true, encoding: .utf8)
        
        let vm = PanelViewModel(dispatcher: AgentDispatcher(provider: MockLLMClient(), registry: SkillRegistry()))
        vm.setTargetURLs([subFolder, file1, file2])
        
        XCTAssertEqual(vm.fileItems.count, 3)
        
        let dirItem = vm.fileItems.first(where: { $0.isDirectory })
        XCTAssertNotNil(dirItem)
        XCTAssertEqual(dirItem?.name, "DocumentsFolder")
        
        let pdfItem = vm.fileItems.first(where: { $0.fileExtension == "pdf" })
        XCTAssertNotNil(pdfItem)
        XCTAssertEqual(pdfItem?.name, "Report.pdf")
        
        let view = PinnedTargetFilesHeaderView(viewModel: vm)
        XCTAssertNotNil(view)
    }
}
