import XCTest
@testable import AIFileCore

final class AppAndCLIScannerTests: XCTestCase {
    
    func testScanProductivityCLIs() async {
        let clis = await AppAndCLIScanner.shared.scanProductivityCLIs()
        // 系统中至少能检测出 zip, tar 等内置 CLI 工具
        XCTAssertFalse(clis.isEmpty, "扫描器应至少发现系统中内置的基础 CLI 生产力工具")
        
        let hasZipOrTar = clis.contains(where: { $0.id == "zip" || $0.id == "tar" })
        XCTAssertTrue(hasZipOrTar, "应成功扫描出 zip 或 tar 工具")
    }
    
    func testScanApplications() async {
        let apps = await AppAndCLIScanner.shared.scanApplications()
        XCTAssertFalse(apps.isEmpty, "扫描器应能探测出系统 /Applications 或用户目录下的已安装应用")
        
        // 验证应用元数据完整性
        if let first = apps.first {
            XCTAssertFalse(first.name.isEmpty)
            XCTAssertFalse(first.bundleId.isEmpty)
        }
    }
}
