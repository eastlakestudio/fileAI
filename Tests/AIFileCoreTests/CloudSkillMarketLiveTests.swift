import XCTest
@testable import AIFileCore

/// 云端技能市场（GitHub 数据源）联网集成测试
final class CloudSkillMarketLiveTests: XCTestCase {
    func testFetchAnthropicSkillsAndParse() async throws {
        let skills = try await CloudSkillMarketService.shared.fetchSkills(from: "anthropics/skills")
        XCTAssertGreaterThan(skills.count, 3, "anthropics/skills 应包含多个技能")
        let pdf = skills.first { $0.slug == "pdf" }
        XCTAssertNotNil(pdf)
        guard let md = await CloudSkillMarketService.shared.fetchSkillMarkdown(repo: "anthropics/skills", slug: "pdf") else {
            return XCTFail("SKILL.md 下载失败")
        }
        XCTAssertTrue(md.hasPrefix("---"))
        let parsed = SkillMarkdownParser.parse(markdown: md, fallbackId: "pdf")
        XCTAssertNotNil(parsed, "SKILL.md 应可解析为 SkillMetadata")
    }
    
    func testSearchRepos() async throws {
        let repos = try await CloudSkillMarketService.shared.searchRepos(query: "lark")
        XCTAssertFalse(repos.isEmpty, "GitHub 搜索应返回结果")
    }
}
