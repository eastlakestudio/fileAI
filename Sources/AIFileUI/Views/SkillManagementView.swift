import SwiftUI
import AIFileCore

public struct SkillManagementView: View {
    @State private var selectedCategory: SkillCategory = .all
    @State private var localSkills: [SkillMetadata] = []
    @State private var cloudSkills: [SkillMetadata] = []
    @State private var expandedSkillId: String? = nil
    
    @State private var isShowingImportModal: Bool = false
    @State private var importMarkdownText: String = ""
    @State private var importErrorMessage: String? = nil
    
    public let onBack: () -> Void
    public var onSelectPrompt: ((String) -> Void)? = nil
    
    public init(onBack: @escaping () -> Void, onSelectPrompt: ((String) -> Void)? = nil) {
        self.onBack = onBack
        self.onSelectPrompt = onSelectPrompt
    }
    
    private var displayedLocalSkills: [SkillMetadata] {
        if selectedCategory == .all {
            return localSkills
        }
        return localSkills.filter { $0.category == selectedCategory }
    }
    
    private var enabledCount: Int {
        localSkills.filter { $0.isEnabled }.count
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部极简导航栏 (无 Tab 按钮，仅保留返回与标题)
            topNavigationBar
            
            Divider().opacity(0.3)
            
            // 2. 两栏经典 macOS 导航布局 (左侧分类导航 + 右侧内容市场/卡片)
            HStack(spacing: 0) {
                leftSidebarNavigation
                    .frame(width: 190)
                
                Divider().opacity(0.2)
                
                rightContentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider().opacity(0.2)
            
            // 3. 底部状态栏
            bottomActionBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .ignoresSafeArea(.all)
        .sheet(isPresented: $isShowingImportModal) {
            importMarkdownSkillSheet
        }
        .onAppear {
            reloadSkills()
        }
    }
    
    // MARK: - 1. Top Navigation Bar (极简无 Tab)
    
    private var topNavigationBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("返回主页")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            
            Text("Skill 技能管理与扩展中心")
                .font(.system(size: 12, weight: .bold))
            
            Spacer()
            
            Text("基于独立 Markdown (.md) 驱动")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.leading, 78) // 预留交通灯
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    // MARK: - 2. Left Sidebar Navigation
    
    private var leftSidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("技能分类")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            
            // 本地分类列表
            ForEach(SkillCategory.allCases.filter { $0 != .cloudMarket }) { cat in
                let count = cat == .all ? localSkills.count : localSkills.filter { $0.category == cat }.count
                categoryNavRow(category: cat, badge: "\(count)")
            }
            
            Divider()
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            
            Text("在线扩展")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            
            // 云端市场入口
            categoryNavRow(category: .cloudMarket, badge: "云端 \(cloudSkills.count)")
            
            Spacer()
            
            // 底部快速操作
            VStack(spacing: 6) {
                Button(action: {
                    importErrorMessage = nil
                    importMarkdownText = defaultMarkdownTemplate
                    isShowingImportModal = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("导入 Markdown Skill")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: {
                    SkillManager.shared.openSkillsDirectoryInFinder()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("打开本地 Skills 目录")
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.02))
    }
    
    @ViewBuilder
    private func categoryNavRow(category: SkillCategory, badge: String) -> some View {
        let isSelected = selectedCategory == category
        Button(action: {
            selectedCategory = category
        }) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)
                
                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
                
                Text(badge)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    // MARK: - 3. Right Content Area (本地技能 vs 云端市场)
    
    private var rightContentArea: some View {
        Group {
            if selectedCategory == .cloudMarket {
                cloudMarketplaceView
            } else {
                localSkillsListView
            }
        }
    }
    
    private var localSkillsListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if displayedLocalSkills.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("当前分类暂无已安装的 Skill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(displayedLocalSkills) { skill in
                        localSkillCardRow(skill: skill)
                    }
                }
            }
            .padding(14)
        }
    }
    
    @ViewBuilder
    private func localSkillCardRow(skill: SkillMetadata) -> some View {
        let isExpanded = expandedSkillId == skill.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: skill.icon)
                    .font(.system(size: 16))
                    .foregroundColor(skill.isEnabled ? .accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(skill.isEnabled ? 0.12 : 0.05))
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(skill.isEnabled ? .primary : .secondary)
                        
                        Text("\(skill.id).md")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        Text(skill.category.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                    
                    Text(skill.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 查看参数
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedSkillId = isExpanded ? nil : skill.id
                    }
                }) {
                    HStack(spacing: 2) {
                        Text(isExpanded ? "收起" : "参数与示例")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                // 启停 Toggle
                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { newVal in
                        toggleSkill(id: skill.id, isEnabled: newVal)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            
            // 支持格式
            HStack(spacing: 4) {
                Text("支持格式:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                
                ForEach(skill.supportedExtensions, id: \.self) { ext in
                    Text(ext)
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .cornerRadius(3)
                }
            }
            
            // 展开参数与示例
            if isExpanded {
                Divider().opacity(0.15)
                
                VStack(alignment: .leading, spacing: 8) {
                    if !skill.parametersDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("🔧 可调参数规范 (YAML/JSON Schema):")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            ForEach(Array(skill.parametersDescription.keys.sorted()), id: \.self) { paramKey in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(paramKey)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                    Text(":")
                                    Text(skill.parametersDescription[paramKey] ?? "")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .cornerRadius(6)
                    }
                    
                    if !skill.examplePrompts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("💡 典型示例指令 (点击立即填入主页执行):")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            ForEach(skill.examplePrompts, id: \.self) { prompt in
                                Button(action: {
                                    onSelectPrompt?(prompt)
                                    onBack()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 10))
                                        Text(prompt)
                                            .font(.system(size: 11))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.08))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(skill.isEnabled ? 0.45 : 0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(skill.isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    // MARK: - 云端市场视图
    
    private var cloudMarketplaceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("☁️ 云端与预设技能市场")
                            .font(.system(size: 13, weight: .bold))
                        Text("所有技能均以独立 Markdown (.md) 文件提供，点击「一键安装」即可下载至本地立即使用。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                ForEach(cloudSkills) { skill in
                    cloudSkillRow(skill: skill)
                }
            }
            .padding(14)
        }
    }
    
    @ViewBuilder
    private func cloudSkillRow(skill: SkillMetadata) -> some View {
        HStack(spacing: 10) {
            Image(systemName: skill.icon)
                .font(.system(size: 18))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .bold))
                    Text("\(skill.id).md")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Text(skill.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(skill.supportedExtensions, id: \.self) { ext in
                        Text(ext)
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(3)
                    }
                }
            }
            
            Spacer()
            
            if skill.isInstalled {
                Text("✓ 已安装")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
            } else {
                Button(action: {
                    installCloudSkill(skill)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.down")
                        Text("一键安装")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    // MARK: - 4. 底部状态栏
    
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Text("已启用 \(enabledCount) / \(localSkills.count) 个本地 Markdown 技能")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("完成并返回") {
                onBack()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - 5. 导入 Markdown Skill 弹窗 Sheet
    
    private var importMarkdownSkillSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("导入新的 Markdown Skill 文件")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                Button("关闭") {
                    isShowingImportModal = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Text("粘贴包含 YAML Frontmatter 规范的 Markdown 源代码，系统将自动解析并在本地生成独立 .md 文件：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            TextEditor(text: $importMarkdownText)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .frame(minHeight: 220)
            
            if let err = importErrorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            
            HStack {
                Button("选择本地 .md 文件导入") {
                    pickAndImportMarkdownFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button("立即安装保存") {
                    let result = SkillManager.shared.installFromMarkdown(content: importMarkdownText)
                    if result.success {
                        reloadSkills()
                        isShowingImportModal = false
                    } else {
                        importErrorMessage = result.error ?? "安装失败"
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 540, height: 420)
    }
    
    private var defaultMarkdownTemplate: String {
        """
        ---
        id: custom_watermark_remover
        name: 图片水印快速清理
        icon: eraser.line.dashed.fill
        category: image
        summary: 自动识别并擦除图片角落的水印或日期标签
        extensions: [png, jpg, jpeg]
        parameters:
          region: 水印位置 (top-right, bottom-right)
        examples:
          - 抹除照片右下角的水印
        ---

        # 图片水印快速清理 Skill
        
        基于 macOS 本地图像算法对指定区域进行纹理修补与水印去除。
        """
    }
    
    private func pickAndImportMarkdownFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        panel.message = "选择自定义 Skill Markdown (.md) 文件"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                self.importMarkdownText = content
            }
        }
    }
    
    private func reloadSkills() {
        SkillManager.shared.reloadLocalSkills()
        self.localSkills = SkillManager.shared.allSkills
        self.cloudSkills = SkillManager.shared.cloudMarketSkills
    }
    
    private func toggleSkill(id: String, isEnabled: Bool) {
        SkillManager.shared.setSkillEnabled(id: id, isEnabled: isEnabled)
        reloadSkills()
    }
    
    private func installCloudSkill(_ skill: SkillMetadata) {
        SkillManager.shared.installSkill(skill)
        reloadSkills()
    }
}
