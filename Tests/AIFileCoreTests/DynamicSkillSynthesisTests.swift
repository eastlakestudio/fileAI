import XCTest
@testable import AIFileCore

final class DynamicSkillSynthesisTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        SkillManager.shared.reloadLocalSkills()
    }
    
    func testDynamicCategoryCreationAndIconInference() {
        // 1. 测试创新全新分类「音视频处理」
        let videoSkill = SkillMetadata(
            id: "test_ffmpeg_video",
            name: "视频智能压缩",
            icon: "film.stack.fill",
            category: .custom,
            customCategory: "音视频处理",
            summary: "自动压缩视频体积",
            supportedExtensions: ["mp4", "mov"],
            executableScript: "ffmpeg -i $INPUT_FILE -crf 28 output.mp4"
        )
        
        XCTAssertEqual(videoSkill.categoryDisplayName, "音视频处理")
        XCTAssertEqual(videoSkill.categoryIcon, "film.stack.fill")
        XCTAssertEqual(videoSkill.executableScript, "ffmpeg -i $INPUT_FILE -crf 28 output.mp4")
        
        // 2. 测试创新全新分类「数据分析」
        let dataSkill = SkillMetadata(
            id: "test_csv_converter",
            name: "Excel转CSV",
            icon: "tablecells.badge.ellipsis",
            category: .custom,
            customCategory: "数据分析",
            summary: "表格转换为CSV",
            supportedExtensions: ["xlsx", "xls"]
        )
        
        XCTAssertEqual(dataSkill.categoryDisplayName, "数据分析")
        XCTAssertEqual(dataSkill.categoryIcon, "tablecells.badge.ellipsis")
    }
    
    func testMarkdownParserWithCustomCategoryAndScript() {
        let md = """
---
id: audio_extractor_test
name: 快速音频提取
icon: waveform
category: 音视频处理
summary: 从视频中提取音频
extensions: [mp4, mkv, mov]
script: ffmpeg -i "$INPUT_FILE" -vn -acodec copy output.mp3
examples:
  - 从视频提取音频
---

# 快速音频提取使用说明
这里是自主编写的完整 Markdown 操作文档。
"""
        
        guard let parsed = SkillMarkdownParser.parse(markdown: md) else {
            XCTFail("应当成功解析包含自定义分类与脚本的 Markdown")
            return
        }
        
        XCTAssertEqual(parsed.id, "audio_extractor_test")
        XCTAssertEqual(parsed.name, "快速音频提取")
        XCTAssertEqual(parsed.categoryDisplayName, "音视频处理")
        XCTAssertEqual(parsed.executableScript, "ffmpeg -i \"$INPUT_FILE\" -vn -acodec copy output.mp3")
        XCTAssertTrue(parsed.supportedExtensions.contains("mp4"))
        
        // 序列化回 Markdown 并验证
        let serialized = SkillMarkdownParser.serialize(metadata: parsed)
        XCTAssertTrue(serialized.contains("category: 音视频处理"))
        XCTAssertTrue(serialized.contains("script: ffmpeg -i \"$INPUT_FILE\" -vn -acodec copy output.mp3"))
        
        guard let roundtrip = SkillMarkdownParser.parse(markdown: serialized) else {
            XCTFail("往返解析应当成功")
            return
        }
        XCTAssertEqual(roundtrip.categoryDisplayName, "音视频处理")
        XCTAssertEqual(roundtrip.executableScript, "ffmpeg -i \"$INPUT_FILE\" -vn -acodec copy output.mp3")
    }
    
    func testSkillManagerSynthesizeAndInstall() {
        let testId = "temp_auto_skill_\(UUID().uuidString.prefix(6))"
        defer {
            SkillManager.shared.uninstallSkill(id: testId)
        }
        
        let created = SkillManager.shared.synthesizeAndInstallSkill(
            id: testId,
            name: "AI代码检测器",
            category: "代码开发与审计",
            summary: "检测代码中的潜在安全缺陷",
            supportedExtensions: ["swift", "py", "ts"],
            script: "echo 'auditing $INPUT_FILE'",
            markdown: "# AI代码检测器\n\n自动生成的文档。"
        )
        
        XCTAssertEqual(created.id, testId)
        XCTAssertEqual(created.categoryDisplayName, "代码开发与审计")
        
        // 验证已安装到本地并加载
        let found = SkillManager.shared.allSkills.first(where: { $0.id == testId })
        XCTAssertNotNil(found, "新技能应当已写入磁盘并由 SkillManager 成功加载")
        XCTAssertEqual(found?.categoryDisplayName, "代码开发与审计")
        
        // 验证 allCategories 包含新分类
        let categories = SkillManager.shared.allCategories
        XCTAssertTrue(categories.contains("代码开发与审计"), "所有分类列表中应当包含动态新创的「代码开发与审计」")
    }
}
