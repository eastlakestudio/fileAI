import Foundation

/// 产出文件名清洗：确保中文名原样落盘。
/// 清除模型/文本来源中可能夹带的 \uXXXX 转义、百分号编码、首尾引号与非法路径字符，
/// 仅保留真实字符（CJK、字母数字、常用符号），杜绝「\\u5f85\\u529e…」「%E5%BE%85…」这类畸形文件名。
public enum FileNameSanitizer {

    public static func clean(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉包裹引号
        if name.count >= 2,
           let first = name.first, let last = name.last,
           "\"'`「」".contains(first) && "\"'`「」".contains(last) {
            name = String(name.dropFirst().dropLast())
        }

        // 解码 \uXXXX 转义（如 "\u5f85\u529e清\u5355"）
        if name.contains("\\u") || name.contains("\\U") {
            name = decodeUnicodeEscapes(name)
        }

        // 解码百分号编码（如 %E5%BE%85…）
        if name.contains("%") {
            let removed = name.replacingOccurrences(of: "+", with: " ")
            if let decoded = removed.removingPercentEncoding {
                name = decoded
            }
        }

        // 去除路径分隔符与控制字符，压缩空白
        let illegal = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        name = name.components(separatedBy: illegal).joined(separator: " ")
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? "" : name
    }

    /// 手工解码字符串中的 \uXXXX 序列（JSONSerialization 未参与时的兜底）
    private static func decodeUnicodeEscapes(_ s: String) -> String {
        guard let data = "\"\(s)\"".data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? String else {
            return s
        }
        return obj
    }
}

/// 从任务产物文件中识别「待办清单」并导入 TodoStore（使内容真正进入 App 的待办面板）。
/// 支持 Markdown 复选框（- [ ] / - [x]）与 JSON 数组两种格式；识别条件为文件名含待办/todo/checklist。
public enum TodoImporter {

    @discardableResult
    public static func importIfNeeded(url: URL, sourceTaskId: UUID?) async -> Int {
        let name = url.lastPathComponent.lowercased()
        let looksLikeTodoList = name.contains("待办") || name.contains("todo") || name.contains("checklist")
        guard looksLikeTodoList else { return 0 }
        guard ["md", "txt", "json"].contains(url.pathExtension.lowercased()) else { return 0 }
        guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else { return 0 }

        let parsed: [(title: String, detail: String?, isDone: Bool)]
        if url.pathExtension.lowercased() == "json",
           let data = raw.data(using: .utf8),
           let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            parsed = array.compactMap { obj in
                let title = (obj["title"] as? String) ?? (obj["content"] as? String) ?? (obj["text"] as? String)
                guard var t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
                t = cleanItemText(t)
                let detail = (obj["detail"] as? String) ?? (obj["description"] as? String)
                let isDone = (obj["done"] as? Bool) ?? (((obj["status"] as? String)?.lowercased()) == "done")
                return (t, detail?.isEmpty == false ? detail : nil, isDone)
            }
        } else {
            parsed = raw.split(separator: "\n").compactMap { line -> (String, String?, Bool)? in
                let s = line.trimmingCharacters(in: .whitespaces)
                var isDone = false
                var body: Substring? = nil
                if s.hasPrefix("- [ ]") {
                    body = s.dropFirst(5)
                } else if s.hasPrefix("- [x]") || s.hasPrefix("- [X]") {
                    body = s.dropFirst(5)
                    isDone = true
                }
                guard var text = body?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
                text = cleanItemText(text)
                return text.isEmpty ? nil : (text, nil, isDone)
            }
        }

        guard !parsed.isEmpty else { return 0 }
        return await TodoStore.shared.addImported(
            items: parsed.map { ($0.title, $0.detail, $0.isDone) },
            sourceTaskId: sourceTaskId
        )
    }

    /// 行内清洗：去掉序号前缀、加粗标记等杂质，保留中文原文
    private static func cleanItemText(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "**", with: "")
        while let first = text.first, first.isNumber || first == "." || first == "、" || first == "." {
            text.removeFirst()
        }
        text = text.replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }
}
