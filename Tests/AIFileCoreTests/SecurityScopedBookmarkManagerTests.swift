import XCTest
@testable import AIFileCore

final class SecurityScopedBookmarkManagerTests: XCTestCase {
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testSecurityScopedBookmarkManagerProperties() {
        let manager = SecurityScopedBookmarkManager.shared
        XCTAssertNotNil(manager)
        // 验证沙箱状态探测返回值类型
        _ = manager.isSandboxActive
    }
    
    func testSaveAndRevokeBookmarkFlow() {
        let manager = SecurityScopedBookmarkManager.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            manager.revokeBookmark(for: tempDir.path)
        }
        
        // 保存临时目录书签
        let saved = manager.saveBookmark(for: tempDir)
        XCTAssertTrue(saved, "应该能够成功为可访问的本地目录生成安全书签")
        
        // 验证已授权路径判断
        XCTAssertTrue(manager.isAuthorized(path: tempDir.path))
        XCTAssertTrue(manager.isAuthorized(path: tempDir.appendingPathComponent("subfile.txt").path))
        
        // 验证在授权范围内查找可执行文件
        let testBin = tempDir.appendingPathComponent("test_cli_tool")
        FileManager.default.createFile(atPath: testBin.path, contents: "#!/bin/sh\necho 1".data(using: .utf8), attributes: [.posixPermissions: 0o755])
        
        let foundPath = manager.findExecutableInAuthorizedScopes(executableNames: ["test_cli_tool"])
        XCTAssertEqual(foundPath, testBin.path)
        
        // 撤销书签
        manager.revokeBookmark(for: tempDir.path)
        XCTAssertFalse(manager.isAuthorized(path: tempDir.path))
    }
    
    func testRestoreAndAccessAllReturnsArray() {
        let manager = SecurityScopedBookmarkManager.shared
        let urls = manager.restoreAndAccessAll()
        XCTAssertNotNil(urls)
    }
}
