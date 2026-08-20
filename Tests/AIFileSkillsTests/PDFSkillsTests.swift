import XCTest
import PDFKit
@testable import AIFileCore
@testable import AIFileSkills

final class PDFSkillsTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testDocToPDFSkillPlanAndExecution() throws {
        let txtURL = tempDirectory.appendingPathComponent("note.txt")
        try "Hello World PDF Content".write(to: txtURL, atomically: true, encoding: .utf8)
        
        let fileItem = FileMetadataEngine.shared.createFileItem(url: txtURL, isDirectory: false)
        let skill = DocToPDFSkill()
        
        let plan = try skill.generatePlan(from: [fileItem], parameters: [:])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.targetURL?.pathExtension, "pdf")
        
        let outputPDF = try skill.execute(action: plan.actions.first!)
        XCTAssertNotNil(outputPDF)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPDF!.path))
        
        // 验证 PDF 有效性
        let doc = PDFDocument(url: outputPDF!)
        XCTAssertNotNil(doc)
        XCTAssertGreaterThanOrEqual(doc!.pageCount, 1)
    }
    
    func testPPTAndPPTXToPDFPlanGeneration() throws {
        let pptURL = tempDirectory.appendingPathComponent("presentation.pptx")
        try "fake pptx content".write(to: pptURL, atomically: true, encoding: .utf8)
        
        let fileItem = FileMetadataEngine.shared.createFileItem(url: pptURL, isDirectory: false)
        let skill = DocToPDFSkill()
        
        let plan = try skill.generatePlan(from: [fileItem], parameters: [:])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.targetURL?.lastPathComponent, "presentation.pdf")
        XCTAssertEqual(plan.actions.first?.operationType, .convertToPDF)
    }
    
    func testDocToPDFMultiPagePagination() throws {
        let longDocURL = tempDirectory.appendingPathComponent("long_document.md")
        // 生成多页长文本内容（300 行段落）
        var longText = "# 长文档多页转 PDF 测试报告\n\n"
        for i in 1...300 {
            longText += "第 \(i) 行：这是自动生成的长文档测试段落内容，用于验证多页矢量 CoreText 分页排版引擎是否能够逐页正确推进，彻底解决单页截断问题。\n\n"
        }
        try longText.write(to: longDocURL, atomically: true, encoding: .utf8)
        
        let fileItem = FileMetadataEngine.shared.createFileItem(url: longDocURL, isDirectory: false)
        let skill = DocToPDFSkill()
        
        let plan = try skill.generatePlan(from: [fileItem], parameters: [:])
        XCTAssertEqual(plan.actions.count, 1)
        
        let outputPDF = try skill.execute(action: plan.actions.first!)
        XCTAssertNotNil(outputPDF)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPDF!.path))
        
        let doc = PDFDocument(url: outputPDF!)
        XCTAssertNotNil(doc)
        // 验证多页有效分页，页数应大于 1（通常应为 5~10 页）
        XCTAssertGreaterThan(doc!.pageCount, 1, "长文档转 PDF 必须正确分页，页数不能被截断为 1 页")
    }
}
