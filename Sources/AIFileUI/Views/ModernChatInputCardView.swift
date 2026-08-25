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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.40),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 3.5)
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
            
            // 当前活跃的大模型 / CLI 引擎指示与快速切换 (如: ✨ DeepSeek V4 / 💻 Ollama)
            modelSelectorMenu
            
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
        .help(L10n.t("选取文件或快速调用已安装 Skill 技能"))
    }
    
    @ViewBuilder
    private var dynamicSkillsSections: some View {
        let skills = SkillManager.shared.allSkills
            .filter { $0.isEnabled }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        Section(L10n.t("✨ 已启用技能")) {
            ForEach(skills) { (s: SkillMetadata) in
                Button(action: {
                    let text = s.examplePrompts.first ?? s.summary
                    viewModel.applySuggestion(text)
                }) {
                    Label(s.name, systemImage: s.icon)
                }
            }
        }
    }
    
    private var modelSelectorMenu: some View {
        let isCLI = viewModel.activeModelDisplayName.contains("CLI") || viewModel.activeModelDisplayName.contains("Ollama") || viewModel.activeModelDisplayName.contains("Claude")
        return Menu {
            Section("当前活跃本地 CLI 引擎") {
                Button(action: {
                    withAnimation {
                        viewModel.currentPage = .settings(initialTab: .cliModel)
                    }
                }) {
                    Label("\(viewModel.activeModelDisplayName)", systemImage: "checkmark")
                }
            }
            
            Divider()
            
            Button(action: {
                withAnimation {
                    viewModel.currentPage = .settings(initialTab: .cliModel)
                }
            }) {
                Label("切换/管理本地 CLI 引擎...", systemImage: "terminal.fill")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isCLI ? "terminal.fill" : "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(isCLI ? .accentColor : .purple.opacity(0.9))
                
                Text(viewModel.activeModelDisplayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.t("当前使用的模型/CLI引擎，点击可快速切换或配置"))
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
