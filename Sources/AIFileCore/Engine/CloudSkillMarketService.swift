import Foundation
import Compression

/// skills.sh 生态云端技能市场服务
/// 说明：skills.sh 官方 REST API 需要 Vercel OIDC 鉴权（Native App 无法使用），
/// 因此采用与其同源的 GitHub 开放数据实现完整能力。
/// 限额策略（未认证 GitHub API 为 60 次/小时/IP）：
/// 1. 列举走 git trees API（每仓库仅 1-2 次 API 调用）
/// 2. API 限流时自动降级为 codeload tarball（CDN 通道，不受 API 限额约束）
/// 3. SKILL.md 内容一律走 raw CDN 通道
/// 4. 结果落地磁盘缓存（24 小时），重复访问零 API 消耗
/// 5. 若进程环境携带 GITHUB_TOKEN/GH_TOKEN，自动附加认证（限额提升至 5000/小时）
public final class CloudSkillMarketService: @unchecked Sendable {

    public static let shared = CloudSkillMarketService()

    /// 云端技能条目（对应 skills.sh 目录项）
    public struct CloudSkill: Identifiable, Hashable, Sendable, Codable {
        public let id: String            // "owner/repo/skill"
        public let slug: String          // 技能目录名
        public let source: String        // "owner/repo"
        public let name: String          // 展示名
        public let summary: String       // 来自 SKILL.md description
        public let installsDesc: String  // 热度描述（star 数）
        public let installURL: String    // GitHub 仓库地址
        public init(id: String, slug: String, source: String, name: String, summary: String, installsDesc: String, installURL: String) {
            self.id = id; self.slug = slug; self.source = source
            self.name = name; self.summary = summary; self.installsDesc = installsDesc; self.installURL = installURL
        }
    }

    /// 精选官方技能源（与 skills.sh/official 页面同源的头部厂商）
    public static let curatedSources: [(source: String, display: String)] = [
        ("anthropics/skills", "Anthropic 官方"),
        ("larksuite/cli", "飞书官方"),
        ("vercel-labs/agent-skills", "Vercel 官方"),
        ("microsoft/azure-skills", "Microsoft 官方"),
        ("obra/superpowers", "Superpowers"),
    ]

    private let session: URLSession
    private var memCache: [String: (date: Date, skills: [CloudSkill])] = [:]
    private let memTTL: TimeInterval = 300
    private let diskTTL: TimeInterval = 24 * 3600

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "AIFileAssistant"
        ]
        self.session = URLSession(configuration: config)
    }

    private var githubToken: String? {
        let env = CLIEnvironmentHelper.makeHostEnvironment()
        return env["GITHUB_TOKEN"] ?? env["GH_TOKEN"] ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"]
    }

    private func authedRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        if let token = githubToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - 公开能力

    /// 拉取某个 GitHub 技能仓库内的全部技能
    public func fetchSkills(from source: String) async throws -> [CloudSkill] {
        if let hit = memCache[source], Date().timeIntervalSince(hit.date) < memTTL {
            return hit.skills
        }
        if let disk = loadDiskCache(source: source), Date().timeIntervalSince(disk.date) < diskTTL {
            memCache[source] = disk
            return disk.skills
        }

        let paths = try await listSkillPaths(repo: source)
        let installsDesc = (try? await fetchStars(repo: source)).map { "★ \($0)" } ?? source
        var results: [CloudSkill] = []
        for entry in paths.prefix(60) {
            if let md = await fetchSkillMarkdown(repo: source, path: entry.path),
               let parsed = parseSKILLMd(md, slug: entry.slug, source: source, installsDesc: installsDesc) {
                results.append(parsed)
            }
        }
        if !results.isEmpty {
            memCache[source] = (Date(), results)
            writeDiskCache(source: source, skills: results)
        }
        return results
    }

    /// 在 GitHub 全站搜索技能仓库（搜索 API 未认证限 10 次/分钟）
    public func searchRepos(query: String) async throws -> [String] {
        let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://api.github.com/search/repositories?q=\(enc)+in:name+skill&sort=stars&per_page=12")!
        let (data, resp) = try await session.data(for: authedRequest(url: url))
        guard let http = resp as? HTTPURLResponse else { return [] }
        if http.statusCode == 403 || http.statusCode == 429 {
            throw NSError(domain: "CloudSkillMarket", code: 403, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("GitHub 搜索限流，请稍后重试或直接输入完整 owner/repo")
            ])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { $0["full_name"] as? String }
    }

    /// 抓取单个技能的完整 SKILL.md 原文（安装用；走 raw CDN，不受 API 限额）
    public func fetchSkillMarkdown(repo: String, slug: String) async -> String? {
        for rawPath in ["skills/\(slug)/SKILL.md", "\(slug)/SKILL.md", "SKILL.md"] {
            if let text = await fetchRaw(repo: repo, path: rawPath) { return text }
        }
        return nil
    }

    private func fetchSkillMarkdown(repo: String, path: String) async -> String? {
        await fetchRaw(repo: repo, path: path.isEmpty ? "SKILL.md" : "\(path)/SKILL.md")
    }

    private func fetchRaw(repo: String, path: String) async -> String? {
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/HEAD/\(path)") else { return nil }
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    // MARK: - 目录列举（trees API → tarball 降级）

    /// 返回仓库内全部 SKILL.md 的 (path, slug)
    private func listSkillPaths(repo: String) async throws -> [(path: String, slug: String)] {
        // 主通道：repo 信息（拿默认分支）+ git trees（1 次拿全库树）
        if let viaAPI = await listViaTreesAPI(repo: repo) {
            return viaAPI
        }
        // 降级通道：codeload tarball（CDN，无限额）
        if let viaTar = await listViaTarball(repo: repo) {
            return viaTar
        }
        throw NSError(domain: "CloudSkillMarket", code: 503, userInfo: [
            NSLocalizedDescriptionKey: L10n.t("GitHub API 限流且降级通道失败，请稍后重试")
        ])
    }

    private func listViaTreesAPI(repo: String) async -> [(path: String, slug: String)]? {
        // 1) 仓库信息：默认分支
        guard let infoURL = URL(string: "https://api.github.com/repos/\(repo)") else { return nil }
        guard let (infoData, infoResp) = try? await session.data(for: authedRequest(url: infoURL)),
              let infoHttp = infoResp as? HTTPURLResponse, infoHttp.statusCode == 200,
              let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
              let branch = info["default_branch"] as? String else { return nil }
        // 2) 全库树（recursive）
        guard let treeURL = URL(string: "https://api.github.com/repos/\(repo)/git/trees/\(branch)?recursive=1") else { return nil }
        guard let (treeData, treeResp) = try? await session.data(for: authedRequest(url: treeURL)),
              let treeHttp = treeResp as? HTTPURLResponse, treeHttp.statusCode == 200,
              let tree = try? JSONSerialization.jsonObject(with: treeData) as? [String: Any],
              let entries = tree["tree"] as? [[String: Any]] else { return nil }
        var results: [(path: String, slug: String)] = []
        for e in entries {
            guard let p = e["path"] as? String, p.hasSuffix("SKILL.md") else { continue }
            results.append(pathAndSlug(repo: repo, skillMdPath: p))
        }
        return results.isEmpty ? nil : results
    }

    /// 从 tarball（codeload CDN，不走 API 限额）解析全部 SKILL.md 路径
    private func listViaTarball(repo: String) async -> [(path: String, slug: String)]? {
        guard let url = URL(string: "https://codeload.github.com/\(repo)/tar.gz/HEAD") else { return nil }
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return nil }
        guard let tar = gunzip(data) else { return nil }
        let names = tarEntryNames(tar)
        let skillPaths = names.filter { $0.hasSuffix("SKILL.md") && !$0.contains("node_modules") }
        var results: [(path: String, slug: String)] = []
        for p in skillPaths {
            // tar 条目形如 "repo-branch/skills/pdf/SKILL.md"，剥掉首段
            let comps = p.split(separator: "/")
            guard comps.count >= 2 else { continue }
            let rel = comps.dropFirst().joined(separator: "/")
            results.append(pathAndSlug(repo: repo, skillMdPath: rel))
        }
        return results.isEmpty ? nil : results
    }

    /// "skills/pdf/SKILL.md" → (path: "skills/pdf", slug: "pdf")；根 "SKILL.md" → (path: "", slug: repo 末段)
    private func pathAndSlug(repo: String, skillMdPath: String) -> (path: String, slug: String) {
        let parts = skillMdPath.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            return (path: "", slug: repo.split(separator: "/").last.map(String.init) ?? repo)
        }
        let path = parts.dropLast().joined(separator: "/")
        let slug = parts[parts.count - 2]
        return (path: path, slug: slug == "skills" ? parts.last ?? slug : slug)
    }

    private func fetchStars(repo: String) async throws -> Int {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)") else { throw URLError(.badURL) }
        let (data, _) = try await session.data(for: authedRequest(url: url))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stars = json["stargazers_count"] as? Int else { throw URLError(.badServerResponse) }
        return stars
    }

    // MARK: - 磁盘缓存

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("CloudSkillMarketCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadDiskCache(source: String) -> (date: Date, skills: [CloudSkill])? {
        let file = cacheDir.appendingPathComponent(source.replacingOccurrences(of: "/", with: "_") + ".json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        struct Wrapper: Codable { let date: Date; let skills: [CloudSkill] }
        guard let w = try? JSONDecoder().decode(Wrapper.self, from: data) else { return nil }
        return (w.date, w.skills)
    }

    private func writeDiskCache(source: String, skills: [CloudSkill]) {
        let file = cacheDir.appendingPathComponent(source.replacingOccurrences(of: "/", with: "_") + ".json")
        struct Wrapper: Codable { let date: Date; let skills: [CloudSkill] }
        let w = Wrapper(date: Date(), skills: skills)
        if let data = try? JSONEncoder().encode(w) {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: - Gzip / Tar 解析

    private func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var idx = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard idx + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while idx < bytes.count && bytes[idx] != 0 { idx += 1 }
            idx += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while idx < bytes.count && bytes[idx] != 0 { idx += 1 }
            idx += 1
        }
        if flags & 0x02 != 0 { idx += 2 } // FHCRC
        guard idx < bytes.count - 8 else { return nil }
        let deflated = data.subdata(in: idx..<(bytes.count - 8))
        return inflateRaw(deflated)
    }

    /// 纯 deflate（RFC 1951）流式解压，用于剥壳后的 gzip body
    private func inflateRaw(_ input: Data) -> Data? {
        let dstCapacity = 1 << 20
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dst.deallocate() }
        let src = UnsafeMutablePointer<UInt8>.allocate(capacity: input.count)
        defer { src.deallocate() }
        input.copyBytes(to: src, count: input.count)
        var stream = compression_stream(dst_ptr: dst, dst_size: dstCapacity, src_ptr: src, src_size: input.count, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }
        var output = Data()
        var status: compression_status = COMPRESSION_STATUS_OK
        repeat {
            status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            let produced = stream.dst_ptr - dst
            if produced > 0 { output.append(dst, count: produced) }
            stream.dst_ptr = dst
            stream.dst_size = dstCapacity
        } while status == COMPRESSION_STATUS_OK
        return status == COMPRESSION_STATUS_END ? output : nil
    }

    private func tarEntryNames(_ tar: Data) -> [String] {
        var names: [String] = []
        var offset = 0
        let bytes = [UInt8](tar)
        while offset + 512 <= bytes.count {
            let header = bytes[offset..<(offset + 512)]
            if header.allSatisfy({ $0 == 0 }) { break }
            // name: 0..100 (null-terminated)
            var nameBytes: [UInt8] = []
            for b in header.prefix(100) {
                if b == 0 { break }
                nameBytes.append(b)
            }
            // typeflag: offset 156
            let typeflag = header.count > 156 ? header[156] : UInt8(ascii: "0")
            // size: offset 124, 12 bytes octal
            var sizeOct = ""
            for i in 124..<136 {
                let b = header[i]
                if b == 0 || b == 32 { continue }
                sizeOct += String(UnicodeScalar(b))
            }
            let size = Int(sizeOct, radix: 8) ?? 0
            // 仅常规文件参与
            if typeflag == UInt8(ascii: "0") || typeflag == 0, let name = String(bytes: nameBytes, encoding: .utf8), !name.isEmpty {
                names.append(name)
            }
            let blocks = (size + 511) / 512
            offset += 512 + blocks * 512
        }
        return names
    }

    // MARK: - SKILL.md 解析

    /// 解析 SKILL.md（YAML frontmatter: name/description）为云端条目
    private func parseSKILLMd(_ md: String, slug: String, source: String, installsDesc: String) -> CloudSkill? {
        var name = slug
        var summary = ""
        if md.hasPrefix("---") {
            let parts = md.components(separatedBy: "---")
            if parts.count >= 3 {
                for line in parts[1].components(separatedBy: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("name:"), name == slug {
                        name = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    } else if t.hasPrefix("description:") {
                        summary = t.dropFirst(12).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        if summary.isEmpty {
            summary = String(md.replacingOccurrences(of: "\n", with: " ").prefix(120))
        }
        return CloudSkill(
            id: "\(source)/\(slug)",
            slug: slug,
            source: source,
            name: name.isEmpty ? slug : name,
            summary: summary,
            installsDesc: installsDesc,
            installURL: "https://github.com/\(source)"
        )
    }
}
