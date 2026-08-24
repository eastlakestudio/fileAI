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
        var script: String? = nil
        var scriptEngine: ScriptEngineType = .bash
        
        var currentSection: String? = nil
        var multiLineScriptBuffer: [String] = []
        var isReadingMultiLineScript = false
        var batchMode: BatchProcessingMode? = nil
        
        let lines = frontmatter.components(separatedBy: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }
            
            if isReadingMultiLineScript {
                if line.hasPrefix("  ") || line.hasPrefix("\t") {
                    // 缩进的多行脚本行，去除前导 2 个空格
                    let unindented = line.hasPrefix("  ") ? String(line.dropFirst(2)) : String(line.dropFirst(1))
                    multiLineScriptBuffer.append(unindented)
                    continue
                } else if trimmedLine.contains(":") && !trimmedLine.hasPrefix("-") {
                    // 进入下一个字段，结束多行脚本读取
                    isReadingMultiLineScript = false
                    script = multiLineScriptBuffer.joined(separator: "\n")
                    multiLineScriptBuffer.removeAll()
                } else {
                    multiLineScriptBuffer.append(line)
                    continue
                }
            }
            
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
            } else if trimmedLine.hasPrefix("batch_mode:") || trimmedLine.hasPrefix("mode:") {
                let modeStr = trimmedLine.replacingOccurrences(of: "batch_mode:", with: "").replacingOccurrences(of: "mode:", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                if modeStr.contains("aggregate") || modeStr.contains("reduce") {
                    batchMode = .aggregate
                } else if modeStr.contains("zero") || modeStr.contains("direct") {
                    batchMode = .zeroInput
                } else {
                    batchMode = .perFile
                }
                currentSection = nil
            } else if trimmedLine.hasPrefix("script_engine:") || trimmedLine.hasPrefix("engine:") {
                let engStr = trimmedLine.replacingOccurrences(of: "script_engine:", with: "").replacingOccurrences(of: "engine:", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                if engStr.contains("python") {
                    scriptEngine = .python3
                } else if engStr.contains("zsh") {
                    scriptEngine = .zsh
                } else if engStr.contains("apple") {
                    scriptEngine = .applescript
                } else {
                    scriptEngine = .bash
                }
                currentSection = nil
            } else if trimmedLine.hasPrefix("script:") {
                let inlineScript = trimmedLine.replacingOccurrences(of: "script:", with: "").trimmingCharacters(in: .whitespaces)
                if inlineScript == "|" || inlineScript == ">" || inlineScript.isEmpty {
                    isReadingMultiLineScript = true
                    multiLineScriptBuffer.removeAll()
                } else {
                    script = inlineScript
                }
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
        
        if isReadingMultiLineScript && !multiLineScriptBuffer.isEmpty {
            script = multiLineScriptBuffer.joined(separator: "\n")
        }
        
        if id.isEmpty { id = "skill_\(UUID().uuidString.prefix(6))" }
        let cat = SkillCategory.from(string: categoryRaw)
        let isStandardCode = ["all", "image", "document", "organization", "collaboration", "custom", "cloudMarket", "全部技能", "图片处理", "文档与pdf", "整理与命名", "企业协同", "自定义扩展", "云端市场"].contains(categoryRaw.lowercased())
        let customCat: String? = isStandardCode ? nil : categoryRaw
        
        let finalExtensions = extensions.isEmpty ? ["*"] : extensions
        
        return SkillMetadata(
            id: id,
            name: name,
            icon: icon,
            category: cat,
            customCategory: customCat,
            summary: summary,
            supportedExtensions: finalExtensions,
            parametersDescription: parameters,
            examplePrompts: examples,
            markdownContent: body.isEmpty ? nil : body,
            executableScript: script,
            scriptEngine: scriptEngine,
            batchMode: batchMode,
            isEnabled: true
        )
    }
    
    /// 将 SkillMetadata 导出为标准的 Markdown (带 YAML Frontmatter)
    public static func serialize(metadata: SkillMetadata) -> String {
        var output = "---\n"
        output += "id: \(metadata.id)\n"
        output += "name: \(metadata.name)\n"
        output += "icon: \(metadata.icon)\n"
        let catValue = metadata.customCategory ?? metadata.category.codeName
        output += "category: \(catValue)\n"
        output += "summary: \(metadata.summary)\n"
        output += "batch_mode: \(metadata.batchMode.rawValue)\n"
        output += "extensions: [\(metadata.supportedExtensions.joined(separator: ", "))]\n"
        output += "script_engine: \(metadata.scriptEngine.rawValue)\n"
        
        if let sc = metadata.executableScript, !sc.isEmpty {
            if sc.contains("\n") {
                output += "script: |\n"
                for line in sc.components(separatedBy: "\n") {
                    output += "  \(line)\n"
                }
            } else {
                output += "script: \(sc)\n"
            }
        }
        
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
