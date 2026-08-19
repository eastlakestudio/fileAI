import XCTest
@testable import AIFileCore

final class SkillMarkdownTests: XCTestCase {
    
    func testSkillMarkdownParsingWithFullFrontmatter() {
        let sampleMarkdown = """
        ---
        id: test_crop_skill
        name: 图片智能裁剪
        icon: crop
        category: image
        summary: 按比例或坐标智能裁剪图片
        extensions: [png, jpg, webp]
        parameters:
          aspectRatio: 16:9
          cropCenter: true
        examples:
          - 将图片裁剪为 16:9 比例
          - 居中裁剪为正方形
        ---

        # 详细说明
        这里是 Markdown 正文详细操作指南。
        """
        
        guard let skill = SkillMarkdownParser.parse(markdown: sampleMarkdown) else {
            XCTFail("应当成功解析 Markdown Skill")
            return
        }
        
        XCTAssertEqual(skill.id, "test_crop_skill")
        XCTAssertEqual(skill.name, "图片智能裁剪")
        XCTAssertEqual(skill.category, .image)
        XCTAssertEqual(skill.supportedExtensions, ["png", "jpg", "webp"])
        XCTAssertEqual(skill.parametersDescription["aspectRatio"], "16:9")
        XCTAssertEqual(skill.examplePrompts.count, 2)
        XCTAssertTrue(skill.markdownContent?.contains("这里是 Markdown 正文") == true)
    }
    
    func testSkillMarkdownSerializationAndRoundtrip() {
        let original = SkillMetadata(
            id: "watermark_cleaner",
            name: "水印擦除",
            icon: "wand.and.stars",
            category: .image,
            summary: "无痕擦除边角水印",
            supportedExtensions: ["png", "jpg"],
            parametersDescription: ["cleanRegion": "bottom-right"],
            examplePrompts: ["擦除右下角水印"],
            markdownContent: "# 水印擦除正文"
        )
        
        let serialized = SkillMarkdownParser.serialize(metadata: original)
        XCTAssertTrue(serialized.hasPrefix("---"))
        XCTAssertTrue(serialized.contains("id: watermark_cleaner"))
        XCTAssertTrue(serialized.contains("cleanRegion: bottom-right"))
        
        guard let parsed = SkillMarkdownParser.parse(markdown: serialized) else {
            XCTFail("反序列化应当成功")
            return
        }
        
        XCTAssertEqual(parsed.id, original.id)
        XCTAssertEqual(parsed.name, original.name)
        XCTAssertEqual(parsed.category, original.category)
        XCTAssertEqual(parsed.supportedExtensions, original.supportedExtensions)
    }
    
    func testInstallSkillAndUninstallCreatesAndRemovesMarkdownFile() {
        let manager = SkillManager.shared
        let testSkill = SkillMetadata(
            id: "unit_test_skill_temp",
            name: "单元测试临时技能",
            icon: "star",
            category: .custom,
            summary: "用于测试安装与卸载",
            supportedExtensions: ["txt"]
        )
        
        let installOk = manager.installSkill(testSkill)
        XCTAssertTrue(installOk)
        
        let fileURL = manager.skillsDirectoryURL.appendingPathComponent("unit_test_skill_temp.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "应生成独立的 .md 文件")
        
        let uninstallOk = manager.uninstallSkill(id: "unit_test_skill_temp")
        XCTAssertTrue(uninstallOk)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "卸载后 .md 文件应被清理")
    }
}
