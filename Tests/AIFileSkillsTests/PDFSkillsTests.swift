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
}
