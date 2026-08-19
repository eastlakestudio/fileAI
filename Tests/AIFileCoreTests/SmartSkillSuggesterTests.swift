import XCTest
@testable import AIFileCore

final class SmartSkillSuggesterTests: XCTestCase {
    func testSuggestsImageSkillsWhenImagesPresent() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/path/img1.png"), isDirectory: false, imageWidth: 100, imageHeight: 100),
            FileItem(url: URL(fileURLWithPath: "/path/img2.jpg"), isDirectory: false, imageWidth: 200, imageHeight: 200)
        ]
        
        let suggester = SmartSkillSuggester()
        let suggestions = suggester.suggestSkills(for: items)
        
        XCTAssertFalse(suggestions.isEmpty)
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("分辨率") }))
        XCTAssertTrue(titles.contains(where: { $0.contains("PNG") }))
        // 不应优先推荐 PDF 合并（因无 PDF）
        XCTAssertFalse(titles.contains(where: { $0.contains("合并") && $0.contains("PDF") }))
    }
    
    func testSuggestsPDFMergeWhenMultiplePDFsPresent() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/path/doc1.pdf"), isDirectory: false, pdfPageCount: 3),
            FileItem(url: URL(fileURLWithPath: "/path/doc2.pdf"), isDirectory: false, pdfPageCount: 5)
        ]
        
        let suggester = SmartSkillSuggester()
        let suggestions = suggester.suggestSkills(for: items)
        
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("合并 2 个 PDF") }))
    }
    
    func testSuggestsFilePickerWhenEmpty() {
        let suggester = SmartSkillSuggester()
        let suggestions = suggester.suggestSkills(for: [])
        
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("选取文件") }))
    }
    
    func testSuggestsSpreadsheetToPDFWhenSpreadsheetsPresent() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/path/清单.xlsx"), isDirectory: false)
        ]
        
        let suggester = SmartSkillSuggester()
        let suggestions = suggester.suggestSkills(for: items)
        
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("电子表格转为 PDF") }))
    }
}
