import XCTest
@testable import AIFileCore

final class SmartSkillSuggesterTests: XCTestCase {
    /// 测试用技能池（架构一致版：推荐由已安装技能动态生成）
    private let testSkills: [SkillMetadata] = [
        SkillMetadata(id: "image_resize", name: "批量调整图片尺寸", icon: "photo", category: .image,
                      summary: "调整图片分辨率", supportedExtensions: ["png", "jpg"],
                      parametersDescription: [:], examplePrompts: ["将所有图片统一修改为 1920x1080 分辨率"],
                      isEnabled: true),
        SkillMetadata(id: "pdf_merge_split", name: "PDF合并与拆分", icon: "doc", category: .document,
                      summary: "PDF 合并拆分", supportedExtensions: ["pdf"],
                      parametersDescription: [:], examplePrompts: ["将选中的所有 PDF 合并为一个新 PDF 文件"],
                      isEnabled: true),
        SkillMetadata(id: "doc_to_pdf", name: "文档/演示/图片转PDF", icon: "doc.richtext", category: .document,
                      summary: "转 PDF", supportedExtensions: ["xlsx", "docx", "pptx"],
                      parametersDescription: [:], examplePrompts: ["将选中的 Excel 表格转换为标准 PDF 文档"],
                      isEnabled: true),
        // 未启用技能：不应出现在推荐中
        SkillMetadata(id: "disabled_skill", name: "禁用技能", icon: "xmark", category: .custom,
                      summary: "-", supportedExtensions: ["png"], parametersDescription: [:],
                      examplePrompts: ["禁用"], isEnabled: false)
    ]

    func testSuggestsImageSkillsWhenImagesPresent() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/path/img1.png"), isDirectory: false, imageWidth: 100, imageHeight: 100),
            FileItem(url: URL(fileURLWithPath: "/path/img2.jpg"), isDirectory: false, imageWidth: 200, imageHeight: 200)
        ]
        
        let suggestions = SmartSkillSuggester().suggestSkills(for: items, installedSkills: testSkills)
        
        XCTAssertFalse(suggestions.isEmpty)
        let titles = suggestions.map { $0.title }
        // 图像技能（扩展名 png/jpg 匹配）被推荐，指令取自其示例
        XCTAssertTrue(titles.contains(where: { $0.contains("图片") }))
        // PDF 技能（仅 pdf 匹配）不出现
        XCTAssertFalse(titles.contains(where: { $0.contains("PDF合并") }))
        // 禁用技能不出现
        XCTAssertFalse(titles.contains(where: { $0.contains("禁用") }))
    }
    
    func testSuggestsPDFMergeWhenMultiplePDFsPresent() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/path/doc1.pdf"), isDirectory: false, pdfPageCount: 3),
            FileItem(url: URL(fileURLWithPath: "/path/doc2.pdf"), isDirectory: false, pdfPageCount: 5)
        ]
        
        let suggestions = SmartSkillSuggester().suggestSkills(for: items, installedSkills: testSkills)
        
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("PDF合并") }))
    }
    
    func testSuggestsFilePickerWhenEmpty() {
        let suggester = SmartSkillSuggester()
        let suggestions = suggester.suggestSkills(for: [], installedSkills: testSkills)
        
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("选取文件") }))
    }
    
    func testSuggestsSpreadsheetToPDFWhenSpreadsheetsPresent() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/path/清单.xlsx"), isDirectory: false)
        ]
        
        let suggestions = SmartSkillSuggester().suggestSkills(for: items, installedSkills: testSkills)
        
        let titles = suggestions.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("转PDF") }))
    }
}
