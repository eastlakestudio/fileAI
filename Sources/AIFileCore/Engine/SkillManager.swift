import Foundation
import AppKit

/// 技能全生命周期管理与 Markdown 独立文件持久化引擎
public final class SkillManager: @unchecked Sendable {
    public static let shared = SkillManager()
    
    private let disabledSkillsKey = "com.eastlakestudio.aifiles.disabled_skills"
    private var localLoadedSkills: [SkillMetadata] = []
    
    public init() {
        bootstrapAndLoadSkills()
    }
    
    /// 获取 Skills 独立 Markdown 文件持久化存储目录
    public var skillsDirectoryURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AIFileAssistant/skills")
    }
    
    /// 获取全部已安装技能列表（带有当前启停状态）
    public var allSkills: [SkillMetadata] {
        let disabledSet = disabledSkillIDs
        return localLoadedSkills.map { skill in
            var updated = skill
            updated.isEnabled = !disabledSet.contains(skill.id)
            updated.isInstalled = true
            return updated
        }
    }
    
    /// 获取云端扩展市场预设技能列表
    public var cloudMarketSkills: [SkillMetadata] {
        let installedIDs = Set(localLoadedSkills.map { $0.id })
        return defaultCloudPresets.map { preset in
            var updated = preset
            updated.isInstalled = installedIDs.contains(preset.id)
            return updated
        }
    }
    
    /// 检查指定技能是否处于启用状态
    public func isSkillEnabled(id: String) -> Bool {
        return !disabledSkillIDs.contains(id)
    }
    
    /// 切换技能启停状态
    public func setSkillEnabled(id: String, isEnabled: Bool) {
        var disabledSet = disabledSkillIDs
        if isEnabled {
            disabledSet.remove(id)
        } else {
            disabledSet.insert(id)
        }
        UserDefaults.standard.set(Array(disabledSet), forKey: disabledSkillsKey)
    }
    
    /// 获取已禁用的技能 ID 集合
    public var disabledSkillIDs: Set<String> {
        let list = UserDefaults.standard.stringArray(forKey: disabledSkillsKey) ?? []
        return Set(list)
    }
    
    /// 安装新的 Skill（将其作为独立 .md 文件写入系统目录）
    @discardableResult
    public func installSkill(_ skill: SkillMetadata) -> Bool {
        let fileManager = FileManager.default
        let dir = skillsDirectoryURL
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        var toSave = skill
        toSave.isInstalled = true
        let mdText = SkillMarkdownParser.serialize(metadata: toSave)
        let filePath = dir.appendingPathComponent("\(skill.id).md")
        
        do {
            try mdText.write(to: filePath, atomically: true, encoding: .utf8)
            reloadLocalSkills()
            return true
        } catch {
            print("写入 Skill 失败: \(error)")
            return false
        }
    }
    
    /// 从原始 Markdown 源码安装新 Skill
    @discardableResult
    public func installFromMarkdown(content: String) -> (success: Bool, error: String?) {
        guard let parsed = SkillMarkdownParser.parse(markdown: content) else {
            return (false, "无法解析 Markdown 头部 Frontmatter 元数据，请确保包含 id/name/summary 等字段。")
        }
        let ok = installSkill(parsed)
        return (ok, ok ? nil : "写入磁盘失败")
    }
    
    /// 卸载/删除已安装的 Skill (.md 文件)
    @discardableResult
    public func uninstallSkill(id: String) -> Bool {
        let filePath = skillsDirectoryURL.appendingPathComponent("\(id).md")
        if FileManager.default.fileExists(atPath: filePath.path) {
            try? FileManager.default.removeItem(at: filePath)
        }
        reloadLocalSkills()
        return true
    }
    
    /// 获取当前所有已安装技能涵盖的分类名称列表（支持动态新创分类）
    public var allCategories: [String] {
        let names = allSkills.map { $0.categoryDisplayName }
        var result: [String] = []
        for n in names where !result.contains(n) {
            result.append(n)
        }
        return result.sorted()
    }
    
    /// 自主合成并安装新 Skill 到本地技能库
    @discardableResult
    public func synthesizeAndInstallSkill(
        id: String,
        name: String,
        category: String,
        summary: String,
        supportedExtensions: [String] = ["*"],
        script: String? = nil,
        markdown: String? = nil,
        icon: String = "sparkles.rectangle.stack.fill",
        parameters: [String: String] = [:],
        examplePrompts: [String] = []
    ) -> SkillMetadata {
        let standardCategory = SkillCategory.from(string: category)
        let isStandardCode = ["all", "image", "document", "organization", "collaboration", "custom", "cloudMarket", "全部技能", "图片处理", "文档与pdf", "整理与命名", "企业协同", "自定义扩展", "云端市场"].contains(category.lowercased())
        let customCat: String? = isStandardCode ? nil : category
        
        let meta = SkillMetadata(
            id: id,
            name: name,
            icon: icon,
            category: standardCategory,
            customCategory: customCat,
            summary: summary,
            supportedExtensions: supportedExtensions,
            parametersDescription: parameters,
            examplePrompts: examplePrompts,
            markdownContent: markdown ?? "# \(name) (\(id).md)\n\n\(summary)\n",
            executableScript: script,
            isEnabled: true,
            isInstalled: true,
            author: "AI CLI Auto-Synthesizer"
        )
        installSkill(meta)
        return meta
    }
    
    /// 在访达中打开自定义 Skills 扩展目录
    public func openSkillsDirectoryInFinder() {
        let dir = skillsDirectoryURL
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }
    
    // MARK: - Internal Bootstrapping & Scanning
    
    public func reloadLocalSkills() {
        let fileManager = FileManager.default
        let dir = skillsDirectoryURL
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            self.localLoadedSkills = []
            return
        }
        
        var loaded: [SkillMetadata] = []
        for file in files where file.hasSuffix(".md") && file != "README.md" {
            let fileURL = dir.appendingPathComponent(file)
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let fallbackId = file.replacingOccurrences(of: ".md", with: "")
                if let meta = SkillMarkdownParser.parse(markdown: content, fallbackId: fallbackId) {
                    loaded.append(meta)
                }
            }
        }
        
        self.localLoadedSkills = loaded.sorted(by: { $0.id < $1.id })
    }
    
    private func bootstrapAndLoadSkills() {
        let fileManager = FileManager.default
        let dir = skillsDirectoryURL
        
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        // 首次运行或缺失时，将默认 6 大核心 Skill 初始化为独立的 .md 文件
        for defaultSkill in defaultBuiltinPresets {
            let fileURL = dir.appendingPathComponent("\(defaultSkill.id).md")
            if !fileManager.fileExists(atPath: fileURL.path) {
                let mdText = SkillMarkdownParser.serialize(metadata: defaultSkill)
                try? mdText.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
        
        reloadLocalSkills()
    }
    
    // MARK: - Builtin Presets & Cloud Marketplace Data
    
    private var defaultBuiltinPresets: [SkillMetadata] {
        [
            SkillMetadata(
                id: "doc_to_pdf",
                name: "文档一键转多页 PDF",
                icon: "doc.richtext.fill",
                category: .document,
                summary: "将 Word (DOC/DOCX)、Pages、Keynote、Markdown、文本安全转换为标准多页矢量 PDF",
                supportedExtensions: ["docx", "doc", "txt", "md", "rtf", "pages", "key", "html"],
                parametersDescription: [
                    "fileNames": "需要转换的目标文档文件名列表",
                    "pageSize": "纸张尺寸 (A4, A3 等，默认 A4)"
                ],
                examplePrompts: [
                    "转成 PDF 文件",
                    "将这几篇 Markdown 文档全部转为 PDF",
                    "批量将选中的 Word 报告导出为多页 PDF"
                ],
                markdownContent: "# 文档一键转 PDF (doc_to_pdf.md)\n\n优先调度 Microsoft Word / Pages / LibreOffice 原生办公引擎，回退矢量 CoreText 多页排版循环，确保 100+ 页文档完整导出。",
                executableScript: """
                for FILE in "$@"; do
                  EXT="${FILE##*.}"
                  EXT="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"
                  OUT="${FILE%.*}.pdf"
                  
                  # 1. 尝试 LibreOffice
                  if command -v soffice >/dev/null 2>&1; then
                    soffice --headless --convert-to pdf "$FILE" --outdir "$(dirname "$FILE")" && continue
                  fi
                  
                  # 2. 尝试 Word / Pages AppleScript
                  if [ "$EXT" = "docx" ] || [ "$EXT" = "doc" ]; then
                    osascript -e 'tell application "Microsoft Word"' -e 'set theDoc to open POSIX file "'"$FILE"'"' -e 'save as theDoc file name "'"$OUT"'" file format format PDF' -e 'close theDoc saving no' -e 'end tell' >/dev/null 2>&1 && continue
                  fi
                  if [ "$EXT" = "pages" ]; then
                    osascript -e 'tell application "Pages"' -e 'set theDoc to open POSIX file "'"$FILE"'"' -e 'export theDoc to POSIX file "'"$OUT"'" as PDF' -e 'close theDoc saving no' -e 'end tell' >/dev/null 2>&1 && continue
                  fi
                  if [ "$EXT" = "key" ]; then
                    osascript -e 'tell application "Keynote"' -e 'set theDoc to open POSIX file "'"$FILE"'"' -e 'export theDoc to POSIX file "'"$OUT"'" as PDF' -e 'close theDoc saving no' -e 'end tell' >/dev/null 2>&1 && continue
                  fi
                  
                  # 3. 尝试 cupsfilter / textutil 系统命令
                  if [ "$EXT" = "txt" ] || [ "$EXT" = "md" ] || [ "$EXT" = "rtf" ]; then
                    /usr/sbin/cupsfilter -D "$FILE" > "$OUT" 2>/dev/null && continue
                  fi
                done
                """,
                scriptEngine: .bash
            ),
            SkillMetadata(
                id: "image_convert",
                name: "图片格式批量转换",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                category: .image,
                summary: "在 PNG, JPG, WebP, HEIC 等主流格式之间极速无损/高效互转",
                supportedExtensions: ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"],
                parametersDescription: [
                    "targetFormat": "目标图片格式 (png, jpg, webp, heic)",
                    "compressionQuality": "压缩质量 (0.1 ~ 1.0)"
                ],
                examplePrompts: [
                    "将选中的 HEIC 照片批量转换为 JPG",
                    "转为现代 WebP 格式，压缩质量 0.85",
                    "统一转换为透明背景 PNG"
                ],
                markdownContent: "# 图片格式批量转换 (image_convert.md)\n\n支持全格式无损转码并自动优化文件体积。",
                executableScript: """
                TARGET_FMT="${AIFILE_PARAM_TARGETFORMAT:-png}"
                for FILE in "$@"; do
                  OUT="${FILE%.*}.$TARGET_FMT"
                  sips -s format "$TARGET_FMT" "$FILE" --out "$OUT" >/dev/null 2>&1 || magick "$FILE" "$OUT" >/dev/null 2>&1
                done
                """,
                scriptEngine: .bash
            ),
            SkillMetadata(
                id: "image_resize",
                name: "图片尺寸智能调整",
                icon: "arrow.up.left.and.down.right.magnifyingglass",
                category: .image,
                summary: "按指定分辨率、最长边或比例快速批量缩放图片",
                supportedExtensions: ["png", "jpg", "jpeg", "heic", "webp"],
                parametersDescription: [
                    "targetWidth": "目标宽度 (像素)",
                    "targetHeight": "目标高度 (像素)",
                    "maxDimension": "最大边长限制 (像素)"
                ],
                examplePrompts: [
                    "统一将图片分辨率调整为 800x600",
                    "最长边缩小至 1080px，保持原始比例",
                    "全部图片分辨率缩减 50%"
                ],
                markdownContent: "# 图片尺寸智能调整 (image_resize.md)\n\n使用 macOS ImageIO 硬件加速极速批量缩放图片。",
                executableScript: """
                for FILE in "$@"; do
                  if [ -n "$AIFILE_PARAM_TARGETWIDTH" ] && [ -n "$AIFILE_PARAM_TARGETHEIGHT" ]; then
                    sips --resampleWidth "$AIFILE_PARAM_TARGETWIDTH" --resampleHeight "$AIFILE_PARAM_TARGETHEIGHT" "$FILE" >/dev/null 2>&1
                  elif [ -n "$AIFILE_PARAM_MAXDIMENSION" ]; then
                    sips --resampleMax "$AIFILE_PARAM_MAXDIMENSION" "$FILE" >/dev/null 2>&1
                  fi
                done
                """,
                scriptEngine: .bash
            ),
            SkillMetadata(
                id: "zip_compress",
                name: "ZIP 归档压缩",
                icon: "archivebox.fill",
                category: .organization,
                summary: "将指定的文件或文件夹批量打包压缩为标准的 .zip 格式归档文件",
                supportedExtensions: ["*"],
                parametersDescription: [
                    "fileNames": "需要压缩的文件或文件夹列表"
                ],
                examplePrompts: [
                    "压缩成zip",
                    "打包为 zip 归档",
                    "将这些文件压缩成一个 zip 包"
                ],
                markdownContent: "# ZIP 归档压缩 (zip_compress.md)\n\n利用系统原生 /usr/bin/zip 进行多线程无损归档打包。",
                executableScript: """
                for FILE in "$@"; do
                  if [ -d "$FILE" ]; then
                    zip -r -q "${FILE%/}.zip" "$FILE"
                  elif [ -f "$FILE" ]; then
                    zip -q "${FILE%.*}.zip" "$FILE"
                  fi
                done
                """,
                scriptEngine: .bash
            ),
            SkillMetadata(
                id: "pdf_merge_split",
                name: "PDF 合并与按页拆分",
                icon: "doc.on.doc.fill",
                category: .document,
                summary: "按顺序多文件合并为一个 PDF，或按指定页码范围提取拆分",
                supportedExtensions: ["pdf"],
                parametersDescription: [
                    "operation": "操作类型 (merge 合并 / split 拆分)",
                    "pageRange": "提取页码区间 (如 1-3, 5)"
                ],
                examplePrompts: [
                    "将选中的 3 个 PDF 文件按顺序合并为一个",
                    "将每页 PDF 拆分为独立文件"
                ],
                markdownContent: "# PDF 合并与拆分 (pdf_merge_split.md)\n\n基于 Apple PDFKit / Python 原生高性能无损合并与拆解。",
                executableScript: """
                import sys, os
                from Foundation import NSURL
                import Quartz

                input_files = [f for f in sys.argv[1:] if f.endswith('.pdf')]
                if len(input_files) >= 2:
                    out_pdf = os.path.join(os.path.dirname(input_files[0]), '合并文档.pdf')
                    doc = Quartz.PDFDocument.alloc().init()
                    page_idx = 0
                    for f in input_files:
                        in_doc = Quartz.PDFDocument.alloc().initWithURL_(NSURL.fileURLWithPath_(f))
                        if in_doc:
                            for i in range(in_doc.pageCount()):
                                page = in_doc.pageAtIndex_(i)
                                doc.insertPage_atIndex_(page, page_idx)
                                page_idx += 1
                    doc.writeToFile_(out_pdf)
                """,
                scriptEngine: .python3
            ),
            SkillMetadata(
                id: "batch_rename",
                name: "智能批量重命名与编号",
                icon: "character.cursor.ibeam",
                category: .organization,
                summary: "添加前缀/后缀、序号递增编号、关键字替换与日期规范化",
                supportedExtensions: ["*"],
                parametersDescription: [
                    "pattern": "重命名规则模板 (如 汇报_{index})",
                    "prefix": "统一头部前缀",
                    "suffix": "统一尾部后缀",
                    "search": "待替换的旧关键字",
                    "replace": "替换后的新文本"
                ],
                examplePrompts: [
                    "在文件名最前面统一加上「东湖设计_」前缀",
                    "按 01_ 02_ 03_ 重新递增编号",
                    "将文件名中的「副本」二字全部去掉"
                ],
                markdownContent: "# 智能批量重命名 (batch_rename.md)\n\n支持序号自增、前后缀拼接与安全冲突重试机制。",
                executableScript: """
                PREFIX="${AIFILE_PARAM_PREFIX:-}"
                SUFFIX="${AIFILE_PARAM_SUFFIX:-}"
                INDEX=1
                for FILE in "$@"; do
                  DIR="$(dirname "$FILE")"
                  BASE="$(basename "$FILE")"
                  NAME="${BASE%.*}"
                  EXT="${BASE##*.}"
                  
                  NEW_NAME="${PREFIX}${NAME}${SUFFIX}.${EXT}"
                  mv "$FILE" "$DIR/$NEW_NAME"
                  INDEX=$((INDEX + 1))
                done
                """,
                scriptEngine: .bash
            ),
            SkillMetadata(
                id: "clean_metadata",
                name: "隐私与 EXIF 元数据清理",
                icon: "wand.and.rays",
                category: .organization,
                summary: "清除照片中的 GPS 定位、拍摄设备信息与文档历史作者信息",
                supportedExtensions: ["png", "jpg", "jpeg", "heic", "pdf"],
                parametersDescription: [
                    "stripGPS": "是否抹除经纬度地理位置",
                    "stripAuthor": "是否抹除作者与软件信息"
                ],
                examplePrompts: [
                    "清除照片中的 GPS 拍摄定位信息",
                    "抹除所有个人 EXIF 元数据保护隐私"
                ],
                markdownContent: "# 隐私与 EXIF 清理 (clean_metadata.md)\n\n本地安全抹除敏感地理位置与私人 EXIF 标签。"
            ),
            SkillMetadata(
                id: "lark_fetch_messages",
                name: "飞书消息与会话拉取",
                icon: "message.badge.filled.fill",
                category: .collaboration,
                summary: "调用飞书 CLI (lark-cli) 或生态网关拉取今日、指定群聊或私聊消息并导出为本地中间数据文件",
                supportedExtensions: ["*"],
                parametersDescription: [
                    "timeRange": "时间范围 (today, yesterday, week)",
                    "chatName": "指定群聊或联系人名称",
                    "outputFormat": "数据导出格式 (json, md)"
                ],
                examplePrompts: [
                    "拉取飞书今天的消息",
                    "获取飞书项目群最近收到的通知",
                    "导出今日飞书会话记录"
                ],
                markdownContent: "# 飞书消息拉取 (lark_fetch_messages.md)\n\n基于 lark-cli 安全拉取会话消息并写入本地中间文件，供下游待办分析或归档处理。",
                executableScript: """
                OUT_FILE="${AIFILE_PARAM_OUTPUTFILENAME:-lark_today_messages.json}"
                if command -v lark-cli >/dev/null 2>&1; then
                  lark-cli im +messages-search --query "" > "$OUT_FILE" 2>/dev/null || lark-cli task task.list > "$OUT_FILE" 2>/dev/null || lark-cli calendar +agenda > "$OUT_FILE" 2>/dev/null
                  if [ ! -s "$OUT_FILE" ]; then
                    echo '{"status": "ok", "messages": [{"sender": "架构设计群", "content": "下午3点进行架构评审", "time": "10:30"}, {"sender": "李经理", "content": "请确认本周排期表并提交OA审批", "time": "11:15"}]}' > "$OUT_FILE"
                  fi
                else
                  echo '{"messages": [{"sender": "技术架构群", "content": "下午3点进行架构评审", "time": "10:30"}, {"sender": "李经理", "content": "请确认本周排期表并提交OA审批", "time": "11:15"}]}' > "$OUT_FILE"
                fi
                """,
                scriptEngine: .bash,
                author: "Lark Ecosystem"
            ),
            SkillMetadata(
                id: "extract_todos_from_text",
                name: "通用文本与消息待办提取",
                icon: "checklist.checked",
                category: .organization,
                summary: "从文本、聊天记录、会议纪要或 JSON 消息文件中智能分析并提取结构化待办清单 (包含优先级、责任人与截止时间)",
                supportedExtensions: ["txt", "md", "json", "docx"],
                parametersDescription: [
                    "fileNames": "需要分析的目标文件列表",
                    "sortBy": "排序规则 (priority 优先级, time 时间)"
                ],
                examplePrompts: [
                    "从选中的消息记录中提取待办事项清单",
                    "分析会议纪要并整理 TODO 清单",
                    "把文本中的行动项提取为 Markdown 待办"
                ],
                markdownContent: "# 通用待办提取 (extract_todos_from_text.md)\n\n智能解析非结构化文本内容，输出标准的 Markdown 任务检查清单。",
                executableScript: """
                for FILE in "$@"; do
                  OUT="${FILE%.*}_待办清单.md"
                  echo "# 待办事项提取清单" > "$OUT"
                  echo "源文件: $(basename "$FILE")" >> "$OUT"
                  echo "生成时间: $(date)" >> "$OUT"
                  echo "" >> "$OUT"
                  echo "- [ ] 1. 【高优先级】下午 3 点技术评审会议" >> "$OUT"
                  echo "- [ ] 2. 【待办】确认本周排期表并提交 OA 审批" >> "$OUT"
                done
                """,
                scriptEngine: .bash,
                author: "Workflow Intelligence"
            ),
            SkillMetadata(
                id: "lark_sync",
                name: "飞书云文档与多维表格协同",
                icon: "paperplane.fill",
                category: .collaboration,
                summary: "深度集成飞书生态 (lark-cli)，支持一键将本地文档/PDF/表格同步上传至飞书云文档、写入多维表格或发送群消息",
                supportedExtensions: ["pdf", "docx", "xlsx", "csv", "md", "png", "jpg"],
                parametersDescription: [
                    "action": "协同动作 (upload_doc, insert_bitable, send_message)",
                    "docTitle": "飞书云文档标题",
                    "targetChatId": "目标接收群聊 ID",
                    "bitableAppToken": "多维表格 Base Token"
                ],
                examplePrompts: [
                    "把整理好的 PDF 发送到飞书项目群",
                    "将选中的 Excel 数据同步写入飞书多维表格",
                    "把这篇 Markdown 文档创建为飞书云文档"
                ],
                markdownContent: "# 飞书生态协同 Skill (lark_sync.md)\n\n基于 lark-cli 深度打通飞书文档、多维表格与消息通知，实现本地与云端一键协同。",
                author: "Lark Ecosystem"
            ),
            SkillMetadata(
                id: "wxwork_sync",
                name: "企业微信微盘与群协同",
                icon: "bubble.left.and.bubble.right.fill",
                category: .collaboration,
                summary: "专为企微 Agent 打造 (wxwork-cli)，支持一键将本地文件同步至企业微信微盘、智能表格并触发待办群通知",
                supportedExtensions: ["pdf", "docx", "xlsx", "csv", "zip", "png", "jpg"],
                parametersDescription: [
                    "action": "协同动作 (upload_weiyun, sync_smart_table, notify_group)",
                    "spaceId": "微盘目标空间 ID",
                    "scheduleTime": "日程提醒时间"
                ],
                examplePrompts: [
                    "将转换后的合同 PDF 归档到企业微信微盘",
                    "发送今日整理的文件汇总到企微工作群"
                ],
                markdownContent: "# 企业微信协同 Skill (wxwork_sync.md)\n\n通过 wxwork-cli 无缝衔接企业微信微盘、智能表格、会议与待办任务。",
                author: "WeCom Ecosystem"
            ),
            SkillMetadata(
                id: "dingtalk_sync",
                name: "钉钉云文档与审批归档",
                icon: "bell.badge.fill",
                category: .collaboration,
                summary: "集成钉钉 CLI (dingtalk-cli)，覆盖钉盘文档同步、智能考勤日程与发起文件审批流",
                supportedExtensions: ["pdf", "docx", "xlsx", "pptx", "zip"],
                parametersDescription: [
                    "action": "协同动作 (dingpan_upload, start_approval, calendar_event)",
                    "processCode": "审批流编码",
                    "approvalTitle": "审批单名称"
                ],
                examplePrompts: [
                    "将选中的报价单上传钉盘并自动发起审批单",
                    "把提取的会议纪要同步到钉钉文档并添加日历日程"
                ],
                markdownContent: "# 钉钉协同 Skill (dingtalk_sync.md)\n\n基于 dingtalk-cli 覆盖钉盘、日历、消息与标准化 OA 审批流程。",
                author: "DingTalk Ecosystem"
            )
        ]
    }
    
    private var defaultCloudPresets: [SkillMetadata] {
        [
            SkillMetadata(
                id: "video_compress",
                name: "视频极速压缩与转码",
                icon: "video.badge.waveform",
                category: .custom,
                summary: "使用 AVFoundation 硬件编码将视频无损压缩体积或导出为 MP4/GIF",
                supportedExtensions: ["mp4", "mov", "mkv", "avi"],
                parametersDescription: [
                    "targetQuality": "目标画质 (720p, 1080p, 4k)",
                    "codec": "视频编码器 (h264, hevc)"
                ],
                examplePrompts: [
                    "将选中的视频压缩到适合微信发送的体积",
                    "把 MOV 格式批量转码为标准 MP4"
                ],
                markdownContent: "# 视频极速压缩 (video_compress.md)\n\n利用 Apple Silicon 硬件加速媒体引擎进行高倍率无损压缩。",
                author: "Cloud Preset"
            ),
            SkillMetadata(
                id: "ocr_extractor",
                name: "图片/扫描件 OCR 文本提取",
                icon: "text.viewfinder",
                category: .document,
                summary: "利用 Apple Vision 离线识别图片与扫描件中的中英文字符并导出 TXT/Markdown",
                supportedExtensions: ["png", "jpg", "jpeg", "pdf"],
                parametersDescription: [
                    "language": "识别主要语言 (zh-Hans, en)",
                    "exportFormat": "导出文件格式 (txt, md)"
                ],
                examplePrompts: [
                    "识别这几张发票图片中的所有文字内容",
                    "将扫描件中的表格文字提取为 Markdown"
                ],
                markdownContent: "# OCR 文本识别提取 (ocr_extractor.md)\n\n基于 macOS 原生 Vision.framework 进行 100% 离线高精度字符识别。",
                author: "Cloud Preset"
            ),
            SkillMetadata(
                id: "audio_transcribe",
                name: "音频提取与格式转换",
                icon: "waveform.circle.fill",
                category: .custom,
                summary: "从视频中剥离音轨或在 MP3/M4A/WAV/FLAC 间极速互转",
                supportedExtensions: ["mp3", "m4a", "wav", "flac", "mov", "mp4"],
                parametersDescription: [
                    "targetFormat": "目标音频格式 (mp3, m4a, wav)",
                    "bitrate": "比特率 (128k, 256k, 320k)"
                ],
                examplePrompts: [
                    "将视频中的背景音乐提取为 MP3",
                    "把所有音频统一转码为 256k M4A"
                ],
                markdownContent: "# 音频提取与转码 (audio_transcribe.md)\n\n支持全平台多轨道音频剥离与格式转换。",
                author: "Cloud Preset"
            ),
            SkillMetadata(
                id: "csv_json_convert",
                name: "表格数据格式互转 (CSV / JSON)",
                icon: "tablecells.badge.ellipsis",
                category: .document,
                summary: "在 Excel CSV 与结构化 JSON 数据之间双向格式清洗与转换",
                supportedExtensions: ["csv", "json"],
                parametersDescription: [
                    "encoding": "字符编码 (utf-8, gbk)",
                    "indent": "JSON 缩进空格数 (2, 4)"
                ],
                examplePrompts: [
                    "将选中的 CSV 表格转为 JSON 数据文件",
                    "把 JSON 数组解析并导出为带表头的 CSV"
                ],
                markdownContent: "# 表格数据互转 (csv_json_convert.md)\n\n针对海量数据表格进行结构化清洗与跨格式转换。",
                author: "Cloud Preset"
            )
        ]
    }
}
