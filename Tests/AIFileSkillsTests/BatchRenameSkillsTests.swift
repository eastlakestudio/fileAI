import XCTest
@testable import AIFileCore
@testable import AIFileSkills

final class BatchRenameSkillsTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testBatchRenameWithPrefixAndSuffix() throws {
        let f1 = tempDirectory.appendingPathComponent("document.docx")
        try "dummy".write(to: f1, atomically: true, encoding: .utf8)
        
        let item = FileMetadataEngine.shared.createFileItem(url: f1, isDirectory: false)
        let skill = BatchRenameSkill()
        
        let plan = try skill.generatePlan(from: [item], parameters: ["prefix": "2024_", "suffix": "_final"])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.targetURL?.lastPathComponent, "2024_document_final.docx")
        
        let renamedURL = try skill.execute(action: plan.actions.first!)
        XCTAssertNotNil(renamedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL!.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f1.path))
    }
    
    func testBatchRenameWithDirectMapping() throws {
        let f1 = tempDirectory.appendingPathComponent("raw_001.png")
        try "dummy".write(to: f1, atomically: true, encoding: .utf8)
        
        let item = FileMetadataEngine.shared.createFileItem(url: f1, isDirectory: false)
        let skill = BatchRenameSkill()
        
        let plan = try skill.generatePlan(from: [item], parameters: ["mapping": ["raw_001.png": "产品封面.png"]])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.targetURL?.lastPathComponent, "产品封面.png")
    }
}
