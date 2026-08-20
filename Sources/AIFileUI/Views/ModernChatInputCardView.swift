import SwiftUI
import AIFileCore

/// 现代 AI IDE 风格的一体化智能聊天输入卡片组件
public struct ModernChatInputCardView: View {
    @ObservedObject var viewModel: PanelViewModel
    
    @State private var isHoveringSend = false
    
    public init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. 多行自然语言指令输入框
            mainTextInputArea
            
            // 2. 底部：内嵌式多功能工具栏 (+, 模式, 模型切换, 思考强度, ↑发送)
            bottomToolbarRow
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - 2. 自然语言输入区
    
    private var mainTextInputArea: some View {
        TextField(
            "",
            text: $viewModel.inputText,
            axis: .vertical
        )
        .lineLimit(2...4)
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        .padding(.vertical, 2)
        .onSubmit {
            if !NSEvent.modifierFlags.contains(.shift) {
                viewModel.submitInstruction()
            }
        }
    }
    
    // MARK: - 3. 底部内嵌式操作工具栏
    
    private var bottomToolbarRow: some View {
        HStack(spacing: 8) {
            // + 菜单：添加文件与智能技能
            plusActionMenu
            
            // 模式选择 (纯净标签，去除下拉箭头)
            modeSelectorMenu
            
            // 模型选择 (如: ✨ DeepSeek V4 Flash ⌄ / ✨ Google Antigravity ⌄)
            modelSelectorMenu
            
            // 思考强度 (如: High ⌄ / Medium ⌄ / Low ⌄)
            effortSelectorMenu
            
            Spacer()
            
            // 右侧发送按钮 / 加载计时器
            sendOrLoadingButton
        }
    }
    
    // MARK: - 工具栏子组件
    
    private var plusActionMenu: some View {
        Menu {
            Section("文件与上下文") {
                Button(action: { viewModel.pickFilesManually() }) {
                    Label("📂 手动选取文件/文件夹...", systemImage: "folder.badge.plus")
                }
                Button(action: { viewModel.fetchFromFinder() }) {
                    Label("⚡ 从当前访达直接抓取", systemImage: "macwindow.and.cursorarrow")
                }
            }
            
            if !viewModel.smartSuggestions.isEmpty {
                Section("✨ 针对当前文件的智能推荐") {
                    ForEach(viewModel.smartSuggestions) { sug in
                        Button(action: {
                            viewModel.applySuggestion(sug.promptText)
                        }) {
                            Label(sug.title, systemImage: sug.icon)
                        }
                    }
                }
            }
            
            dynamicSkillsSections
            
            Divider()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.currentPage = .settings(initialTab: .skills)
                }
            }) {
                Label("⚙️ 打开 Skill 管理中心...", systemImage: "puzzlepiece.extension")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("选取文件或快速调用已安装 Skill 技能")
    }
    
    @ViewBuilder
    private var dynamicSkillsSections: some View {
        let skills = SkillManager.shared.allSkills.filter { $0.isEnabled }
        let displayCategories: [SkillCategory] = [.image, .document, .organization, .collaboration, .custom]
        
        ForEach(displayCategories, id: \.self) { cat in
            let categorySkills = skills.filter { $0.category == cat }
            if !categorySkills.isEmpty {
                Section(categorySectionTitle(for: cat)) {
                    ForEach(categorySkills) { (s: SkillMetadata) in
                        Button(action: {
                            let text = s.examplePrompts.first ?? s.summary
                            viewModel.applySuggestion(text)
                        }) {
                            Label(s.name, systemImage: s.icon)
                        }
                    }
                }
            }
        }
    }
    
    private func categorySectionTitle(for category: SkillCategory) -> String {
        switch category {
        case .image: return "🖼️ 图片处理 Skill"
        case .document: return "📄 文档与 PDF Skill"
        case .organization: return "🏷️ 整理与重命名 Skill"
        case .collaboration: return "🏢 企业生态协同"
        case .custom: return "🧩 扩展自定义技能"
        default: return "🧩 \(category.rawValue)"
        }
    }
    
    private var modeSelectorMenu: some View {
        Menu {
            Button("🤖 Agent 模式 (智能自动规划)") {
                viewModel.executionMode = "Agent 模式"
            }
            Button("⚡ 极速模式 (本地规则秒级分流)") {
                viewModel.executionMode = "极速模式"
            }
            Button("👁️ 仅预览 (Diff 检查不自动执行)") {
                viewModel.executionMode = "仅预览"
            }
        } label: {
            Text(viewModel.executionMode)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }
    
    private var modelSelectorMenu: some View {
        Menu {
            Section("当前活跃模型引擎") {
                Button(action: {
                    withAnimation {
                        viewModel.currentPage = .settings(initialTab: .cloudModel)
                    }
                }) {
                    Label("\(viewModel.activeModelDisplayName)", systemImage: "checkmark")
                }
            }
            
            Divider()
            
            Button(action: {
                withAnimation {
                    viewModel.currentPage = .settings(initialTab: .cloudModel)
                }
            }) {
                Label("切换/配置更多模型与 CLI...", systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.purple.opacity(0.9))
                
                Text(viewModel.activeModelDisplayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .menuStyle(.borderlessButton)
    }
    
    private var effortSelectorMenu: some View {
        Menu {
            Button("🧠 High (完整深度思考)") {
                viewModel.reasoningEffort = "High"
            }
            Button("💡 Medium (标准思考推理)") {
                viewModel.reasoningEffort = "Medium"
            }
            Button("⚡ Low (极速低延迟)") {
                viewModel.reasoningEffort = "Low"
            }
        } label: {
            HStack(spacing: 3) {
                Text(viewModel.reasoningEffort)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .menuStyle(.borderlessButton)
    }
    
    private var sendOrLoadingButton: some View {
        Group {
            if viewModel.isThinking {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.55)
                    Text(String(format: "%.1fs", viewModel.thinkingElapsedSeconds))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(6)
            } else {
                let hasInput = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button(action: {
                    viewModel.submitInstruction()
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(hasInput ? .white : .secondary.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hasInput ? Color.accentColor : Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!hasInput)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private func fileIcon(for ext: String) -> String {
        let e = ext.lowercased()
        switch e {
        case "png", "jpg", "jpeg", "heic", "webp", "gif", "svg":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages", "txt", "md":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "play.rectangle.fill"
        case "zip", "tar", "gz", "7z", "rar":
            return "doc.zipper"
        default:
            return "doc.fill"
        }
    }
}
