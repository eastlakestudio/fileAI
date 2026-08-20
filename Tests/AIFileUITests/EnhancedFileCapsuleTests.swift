import XCTest
@testable import AIFileCore
@testable import AIFileSkills
@testable import AIFileAgent
@testable import AIFileUI

@MainActor
final class EnhancedFileCapsuleTests: XCTestCase {
    
    func testFileItemPrettyPathConversion() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/Downloads/ProjectDocs/sample.pdf")
        let item = FileItem(url: url, isDirectory: false)
        
        XCTAssertEqual(item.prettyPath, "~/Downloads/ProjectDocs/sample.pdf")
    }
    
    func testDirectoryMetadataRecursivelyCountsChildren() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 创建 1 个子目录和 2 个子文件
        let subDir = tempDir.appendingPathComponent("SubFolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let file1 = tempDir.appendingPathComponent("file1.txt")
        let file2 = subDir.appendingPathComponent("file2.jpg")
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)
        
        let item = FileMetadataEngine.shared.createFileItem(url: tempDir, isDirectory: true)
        
        XCTAssertTrue(item.isDirectory)
        XCTAssertEqual(item.childFileCount, 2)
        XCTAssertEqual(item.childDirectoryCount, 1)
        XCTAssertTrue(item.fileSize > 0)
    }
}
