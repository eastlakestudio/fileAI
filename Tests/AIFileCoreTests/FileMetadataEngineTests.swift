import XCTest
@testable import AIFileCore

final class FileMetadataEngineTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testMetadataExtractionAndPrivacySafety() throws {
        // 创建临时测试文件
        let testFile1 = tempDirectory.appendingPathComponent("test1.txt")
        let testFile2 = tempDirectory.appendingPathComponent("image.png")
        try "Secret Content That Should Never Be Leaked".write(to: testFile1, atomically: true, encoding: .utf8)
        try Data(repeating: 0, count: 100).write(to: testFile2)
        
        let engine = FileMetadataEngine()
        let items = engine.collectMetadata(from: [tempDirectory], recursive: true)
        
        XCTAssertEqual(items.count, 2)
        
        // 验证元数据提取
        let txtItem = items.first { $0.name == "test1.txt" }
        XCTAssertNotNil(txtItem)
        XCTAssertEqual(txtItem?.fileExtension, "txt")
        XCTAssertFalse(txtItem?.isDirectory ?? true)
        
        // 验证隐私安全：生成的 JSON 上下文绝对不包含文本正文 "Secret Content"
        let jsonContext = engine.generateLLMContextJSON(items: items)
        XCTAssertFalse(jsonContext.contains("Secret Content"))
        XCTAssertTrue(jsonContext.contains("test1.txt"))
        XCTAssertTrue(jsonContext.contains("image.png"))
    }
    
    func testExtensionFiltering() throws {
        let testFile1 = tempDirectory.appendingPathComponent("a.png")
        let testFile2 = tempDirectory.appendingPathComponent("b.pdf")
        let testFile3 = tempDirectory.appendingPathComponent("c.txt")
        try Data().write(to: testFile1)
        try Data().write(to: testFile2)
        try Data().write(to: testFile3)
        
        let engine = FileMetadataEngine()
        let items = engine.collectMetadata(from: [tempDirectory], recursive: true, allowedExtensions: ["png", "pdf"])
        
        XCTAssertEqual(items.count, 2)
        let names = Set(items.map { $0.name })
        XCTAssertTrue(names.contains("a.png"))
        XCTAssertTrue(names.contains("b.pdf"))
        XCTAssertFalse(names.contains("c.txt"))
    }
}
