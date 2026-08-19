import Foundation

/// 独立 Markdown Skill 文件 (.md) 的 Frontmatter 解析与序列化引擎
public final class SkillMarkdownParser {
    
    /// 从 Markdown 文本解析为 SkillMetadata
    public static func parse(markdown: String, fallbackId: String = "") -> SkillMetadata? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }
        
        let components = trimmed.components(separatedBy: "---")
        guard components.count >= 3 else { return nil }
        
        let frontmatter = components[1]
        let body = components.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var id = fallbackId
        var name = "未命名技能"
        var icon = "puzzlepiece.extension"
        var categoryRaw = "organization"
        var summary = ""
        var extensions: [String] = []
        var parameters: [String: String] = [:]
        var examples: [String] = []
        
        var currentSection: String? = nil
        
        let lines = frontmatter.components(separatedBy: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }
            
            if trimmedLine.hasPrefix("id:") {
                id = trimmedLine.replacingOccurrences(of: "id:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = nil
            } else if trimmedLine.hasPrefix("name:") {
                name = trimmedLine.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = nil
            } else if trimmedLine.hasPrefix("icon:") {
                icon = trimmedLine.replacingOccurrences(of: "icon:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = nil
            } else if trimmedLine.hasPrefix("category:") {
                categoryRaw = trimmedLine.replacingOccurrences(of: "category:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = nil
            } else if trimmedLine.hasPrefix("summary:") {
                summary = trimmedLine.replacingOccurrences(of: "summary:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = nil
            } else if trimmedLine.hasPrefix("extensions:") {
                let extStr = trimmedLine.replacingOccurrences(of: "extensions:", with: "").trimmingCharacters(in: .whitespaces)
                if extStr.hasPrefix("[") && extStr.hasSuffix("]") {
                    let inner = extStr.dropFirst().dropLast()
                    extensions = inner.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                currentSection = "extensions"
            } else if trimmedLine.hasPrefix("parameters:") {
                currentSection = "parameters"
            } else if trimmedLine.hasPrefix("examples:") {
                currentSection = "examples"
            } else if let sec = currentSection {
                if sec == "parameters" && trimmedLine.contains(":") {
                    let parts = trimmedLine.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let val = parts[1].trimmingCharacters(in: .whitespaces)
                        parameters[key] = val
                    }
                } else if sec == "examples" && trimmedLine.hasPrefix("-") {
                    let item = trimmedLine.dropFirst().trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty {
                        examples.append(item)
                    }
                }
            }
        }
        
        if id.isEmpty { id = "skill_\(UUID().uuidString.prefix(6))" }
        let cat = SkillCategory.from(string: categoryRaw)
        
        return SkillMetadata(
            id: id,
            name: name,
            icon: icon,
            category: cat,
            summary: summary,
            supportedExtensions: extensions,
            parametersDescription: parameters,
            examplePrompts: examples,
            markdownContent: body.isEmpty ? nil : body,
            isEnabled: true
        )
    }
    
    /// 将 SkillMetadata 导出为标准的 Markdown (带 YAML Frontmatter)
    public static func serialize(metadata: SkillMetadata) -> String {
        var output = "---\n"
        output += "id: \(metadata.id)\n"
        output += "name: \(metadata.name)\n"
        output += "icon: \(metadata.icon)\n"
        output += "category: \(metadata.category.codeName)\n"
        output += "summary: \(metadata.summary)\n"
        output += "extensions: [\(metadata.supportedExtensions.joined(separator: ", "))]\n"
        
        if !metadata.parametersDescription.isEmpty {
            output += "parameters:\n"
            for key in metadata.parametersDescription.keys.sorted() {
                output += "  \(key): \(metadata.parametersDescription[key] ?? "")\n"
            }
        }
        
        if !metadata.examplePrompts.isEmpty {
            output += "examples:\n"
            for ex in metadata.examplePrompts {
                output += "  - \(ex)\n"
            }
        }
        
        output += "---\n\n"
        
        if let body = metadata.markdownContent, !body.isEmpty {
            output += body
        } else {
            output += "# \(metadata.name) (\(metadata.id))\n\n\(metadata.summary)\n"
        }
        
        return output
    }
}
