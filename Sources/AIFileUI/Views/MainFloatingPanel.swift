import SwiftUI
import AIFileCore
import AIFileFinderIntegration

@MainActor
public struct MainFloatingPanel: View {
    @StateObject public var viewModel: PanelViewModel
    
    public init(viewModel: PanelViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public init() {
        self._viewModel = StateObject(wrappedValue: PanelViewModel())
    }
    
    public var body: some View {
        Group {
            switch viewModel.currentPage {
            case .taskBoard:
                TaskBoardView(onBack: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.currentPage = .main
                    }
                })
                .transition(.opacity)
            case .skillManagement:
                SkillManagementView(
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.currentPage = .main
                        }
                    },
                    onSelectPrompt: { prompt in
                        viewModel.inputText = prompt
                    }
                )
                .transition(.opacity)
            case .modelSettings:
                ModelSettingsView(onBack: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.currentPage = .main
                    }
                })
                .transition(.opacity)
            case .main:
                mainPanelBody
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thickMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.90))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .ignoresSafeArea(.all)
        .sheet(isPresented: $viewModel.isShowingDiffPreview) {
            DiffPreviewView(
                plan: $viewModel.currentPlan,
                onConfirm: { viewModel.confirmExecution() },
                onCancel: { viewModel.cancelCurrentExecution() }
            )
        }
        .sheet(isPresented: $viewModel.isShowingConsentModal) {
            ConsentGateModalView(
                request: viewModel.consentRequest,
                onDecision: { decision in viewModel.handleConsentDecision(decision) }
            )
        }
        .onAppear {
            viewModel.fetchFromFinder()
        }
    }
    
    private var mainPanelBody: some View {
        VStack(spacing: 0) {
            // 1. 顶部单行一体化控制栏 (与系统红绿灯 100% 同行对齐，填入最顶端)
            unifiedTopBar
            
            Divider().opacity(0.3)
            
            // 2. 文件展示区 (列表 / 路径树状视图，弹性撑满整个高度并推动顶栏置顶)
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().opacity(0.2)
            
            // 3. 智能关联 Skill 推荐胶囊
            smartSkillRecommendationSection
            
            // 4. 底部自然语言交互栏
            bottomChatInputBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Single Unified Top Bar (与 TaskBoard 100% 结构一致)
    
    private var unifiedTopBar: some View {
        HStack(spacing: 8) {
            // App 标志与名称
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("文件魔法棒")
                    .font(.system(size: 13, weight: .bold))
            }
            
            Spacer()
            
            // 递归扫描开关
            Toggle("递归", isOn: $viewModel.isRecursive)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
            
            // 视图切换 (平铺列表 / 路径树状)
            Picker("", selection: $viewModel.viewMode) {
                Image(systemName: "list.bullet").tag(FileListViewMode.list)
                Image(systemName: "list.triangle").tag(FileListViewMode.tree)
            }
            .pickerStyle(.segmented)
            .frame(width: 52)
            .controlSize(.mini)
            
            // 任务看板全页切换
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.currentPage = .taskBoard
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "list.clipboard")
                    Text("任务看板")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // Skill 管理全页切换
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.currentPage = .skillManagement
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "puzzlepiece.extension")
                    Text("Skill 管理")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // 模型配置全页切换
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.currentPage = .modelSettings
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                    Text("模型配置")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // 撤销
            Button(action: { viewModel.undoLastOperation() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("撤销上次操作 (⌘Z)")
            .keyboardShortcut("z", modifiers: .command)
            
            // 手动拾取文件
            Button(action: { viewModel.pickFilesManually() }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("手动选择文件或文件夹")
            
            // 刷新 Finder
            Button(action: { viewModel.fetchFromFinder() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("从当前前台 Finder 重新抓取")
        }
        .padding(.leading, 78) // 预留左侧 78px 红黄绿系统按钮位置
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            // 当前操作路径与文件统计面包屑栏 (不拥挤，更清晰)
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("当前路径:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(viewModel.commonParentDirectoryPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
                
                Spacer()
                
                Text("已选 \(viewModel.fileItems.count) 项")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.02))
            
            Divider().opacity(0.15)
            
            Group {
                if viewModel.fileItems.isEmpty {
                    emptyPlaceholderView
                } else {
                    if viewModel.viewMode == .list {
                        flatListView
                    } else {
                        FileTreeView(items: viewModel.fileItems)
                    }
                }
            }
        }
    }
    
    private var flatListView: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(viewModel.fileItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.fileExtension))
                            .foregroundColor(item.isDirectory ? .yellow : .accentColor)
                            .font(.system(size: 13))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(item.formattedSize)
                                if let w = item.imageWidth, let h = item.imageHeight {
                                    Text("• \(w)x\(h)")
                                }
                                if let p = item.pdfPageCount {
                                    Text("• \(p) 页")
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                    .cornerRadius(6)
                }
            }
            .padding(10)
        }
    }
    
    private var emptyPlaceholderView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("当前 Finder 未选中任何文件")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Button("📂 打开文件选取器") {
                    viewModel.pickFilesManually()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("⚡ 抓取当前访达") {
                    viewModel.fetchFromFinder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var smartSkillRecommendationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text("智能推荐 Skill (已结合当前 \(viewModel.fileItems.count) 个文件动态过滤):")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.smartSuggestions) { suggestion in
                        Button(action: {
                            viewModel.applySuggestion(suggestion.promptText)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 10))
                                Text(suggestion.title)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }
    
    private var bottomChatInputBar: some View {
        VStack(spacing: 4) {
            if let msg = viewModel.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(msg.contains("❌") ? .red : .accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            
            VStack(spacing: 4) {
                // 双行自然语言输入卡片
                HStack(alignment: .top, spacing: 8) {
                    TextField(
                        "输入自然语言指令（如：把这里的ppt转成pdf、统一改为1920x1080、批量重命名）...",
                        text: $viewModel.inputText,
                        axis: .vertical
                    )
                    .lineLimit(2...3)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minHeight: 38, alignment: .topLeading)
                    .onSubmit {
                        viewModel.submitInstruction()
                    }
                    
                    VStack(spacing: 6) {
                        if viewModel.isThinking {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 26, height: 26)
                        } else {
                            Button(action: { viewModel.submitInstruction() }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(6)
                
                // 输入框下方状态行：左侧提示，右侧显示当前模型服务名称与跳转快捷入口
                HStack(spacing: 6) {
                    Text("回车发送指令 • 随时 ⌘Z 撤销")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.currentPage = .modelSettings
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                            Text(viewModel.activeModelDisplayName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("点击切换或配置当前 AI 模型服务")
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
    
    private func fileIcon(for ext: String) -> String {
        switch ext {
        case "png", "jpg", "jpeg", "heic", "webp": return "photo"
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.text"
        default: return "doc"
        }
    }
}
