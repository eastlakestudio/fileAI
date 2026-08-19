import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent

final class SkillValidationFeedbackTests: XCTestCase {
    
    func testDocToPDFThrowsDescriptiveErrorForUnsupportedFormats() {
        let zipItem = FileItem(url: URL(fileURLWithPath: "/tmp/archive.zip"), isDirectory: false)
        let skill = DocToPDFSkill()
        
        XCTAssertThrowsError(try skill.generatePlan(from: [zipItem], parameters: [:])) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains(".zip"))
            XCTAssertTrue(desc.contains("无法转为 PDF"))
            XCTAssertTrue(desc.contains(".xlsx") || desc.contains("Excel"))
        }
    }
    
    func testImageResizeThrowsDescriptiveErrorForNonImageFiles() {
        let docItem = FileItem(url: URL(fileURLWithPath: "/tmp/report.docx"), isDirectory: false)
        let skill = ImageResizeSkill()
        
        XCTAssertThrowsError(try skill.generatePlan(from: [docItem], parameters: [:])) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains(".docx"))
            XCTAssertTrue(desc.contains("不是支持的图片格式"))
        }
    }
    
    func testPDFMergeSplitThrowsDescriptiveErrorWhenNoPDFFilesPresent() {
        let pngItem = FileItem(url: URL(fileURLWithPath: "/tmp/photo.png"), isDirectory: false)
        let skill = PDFMergeSplitSkill()
        
        XCTAssertThrowsError(try skill.generatePlan(from: [pngItem], parameters: ["actionType": "merge"])) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains(".png"))
            XCTAssertTrue(desc.contains("未包含 PDF 文件") || desc.contains("没有 PDF 文件"))
        }
    }
    
    func testAgentDispatcherFastPathPropagatesValidationErrorInstantly() async {
        let registry = SkillRegistry()
        registry.register(DocToPDFSkill())
        let dispatcher = AgentDispatcher(provider: MockLLMClient(), registry: registry)
        
        let dmgItem = FileItem(url: URL(fileURLWithPath: "/tmp/installer.dmg"), isDirectory: false)
        
        do {
            _ = try await dispatcher.generatePlan(userPrompt: "转成 PDF 文件", fileItems: [dmgItem])
            XCTFail("应当直接抛出格式不支持的友好错误提示")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains(".dmg"))
            XCTAssertTrue(error.localizedDescription.contains("无法转为 PDF"))
        }
    }
}
