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
                TaskBoardView(
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.currentPage = .main
                        }
                    },
                    onRerunTask: { task in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.rerunTask(task)
                        }
                    }
                )
                .transition(.opacity)
            case .settings(let tab):
                UnifiedSettingsView(
                    initialTab: tab,
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
            
            // 3. 底部自然语言交互栏 (内置 + 号 Skill 呼出菜单)
            bottomChatInputBar
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Single Unified Top Bar (极简纯净顶栏)
    
    private var unifiedTopBar: some View {
        HStack(spacing: 8) {
            // App 标志与名称
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("文件魔法棒")
                    .font(.system(size: 13, weight: .bold))
            }
            
            Spacer()
            
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
            
            // 统一配置管理全页切换
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.currentPage = .settings(initialTab: .cloudModel)
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                    Text("配置管理")
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
            
            // 退出应用
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.85))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("退出文件魔法棒 (⌘Q)")
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.leading, 78) // 预留左侧 78px 红黄绿系统按钮位置
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            // 当前操作路径与文件控制快捷工具栏
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(viewModel.commonParentDirectoryPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(1)
                    
                    Text("(\(viewModel.fileItems.count) 项)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 递归开关
                Toggle("递归", isOn: $viewModel.isRecursive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                
                // 视图切换 (平铺列表 / 路径树状)
                Picker("", selection: $viewModel.viewMode) {
                    Image(systemName: "list.bullet").tag(FileListViewMode.list)
                    Image(systemName: "list.triangle").tag(FileListViewMode.tree)
                }
                .pickerStyle(.segmented)
                .frame(width: 48)
                .controlSize(.mini)
                
                // 手动拾取文件
                Button(action: { viewModel.pickFilesManually() }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("手动选取文件")
                
                // 重新抓取 Finder
                Button(action: { viewModel.fetchFromFinder() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("重新抓取前台 Finder 选中项")
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
                            HStack(spacing: 5) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                
                                if viewModel.latestOutputURLs.contains(where: { $0.path == item.url.path }) {
                                    Text("✨ 刚生成")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.18))
                                        .foregroundColor(.green)
                                        .cornerRadius(3)
                                }
                            }
                            
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
                        
                        // 快捷定位与打开按钮
                        HStack(spacing: 4) {
                            Button(action: { viewModel.revealFile(at: item.url) }) {
                                Image(systemName: "magnifyingglass.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("在访达中定位高亮此文件")
                            
                            Button(action: { viewModel.openFile(at: item.url) }) {
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("使用系统默认程序打开此文件")
                        }
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
    
    private var bottomChatInputBar: some View {
        VStack(spacing: 4) {
            // 最近生成文件的快捷定位与打开横幅
            if !viewModel.latestOutputURLs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    
                    Text("已生成 \(viewModel.latestOutputURLs.count) 个结果文件")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: { viewModel.revealLatestOutputFiles() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10, weight: .bold))
                            Text("在访达中高亮定位")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    
                    Button(action: { viewModel.openLatestOutputDirectory() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text("打开目录")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)
                .padding(.horizontal, 14)
            }
            
            if let msg = viewModel.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(msg.contains("❌") ? .red : .accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            
            VStack(spacing: 4) {
                // 双行自然语言输入卡片 (集成 + 号 Skill 呼出菜单)
                HStack(alignment: .top, spacing: 8) {
                    // + 号 Skill 呼出菜单
                    skillPlusMenu
                    
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
                    
                    VStack(spacing: 2) {
                        if viewModel.isThinking {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(String(format: "%.1fs", viewModel.thinkingElapsedSeconds))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 4)
                            .frame(height: 26)
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
                            viewModel.currentPage = .settings(initialTab: .cloudModel)
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
    
    private var skillPlusMenu: some View {
        Menu {
            if !viewModel.smartSuggestions.isEmpty {
                Section("✨ 智能推荐 (已结合所选 \(viewModel.fileItems.count) 项文件)") {
                    ForEach(viewModel.smartSuggestions) { suggestion in
                        Button(action: {
                            viewModel.applySuggestion(suggestion.promptText)
                        }) {
                            Label(suggestion.title, systemImage: suggestion.icon)
                        }
                    }
                }
            }
            
            Section("🧩 常用文件 Skill") {
                Button(action: { viewModel.applySuggestion("统一将图片分辨率调整为 1920x1080") }) {
                    Label("图片尺寸智能调整", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                }
                Button(action: { viewModel.applySuggestion("将选中的图片批量转换为 JPG 格式") }) {
                    Label("图片格式批量转换", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
                Button(action: { viewModel.applySuggestion("将选中的所有文档转为标准 PDF") }) {
                    Label("文档一键转 PDF", systemImage: "doc.richtext.fill")
                }
                Button(action: { viewModel.applySuggestion("将选中的 PDF 文件按顺序合并为一个") }) {
                    Label("PDF 合并与拆分", systemImage: "doc.on.doc.fill")
                }
                Button(action: { viewModel.applySuggestion("在文件名最前面统一加上前缀") }) {
                    Label("智能批量重命名与编号", systemImage: "character.cursor.ibeam")
                }
                Button(action: { viewModel.applySuggestion("清除照片中的 GPS 拍摄定位与 EXIF 隐私") }) {
                    Label("隐私与 EXIF 清理", systemImage: "wand.and.rays")
                }
            }
            
            Section("🏢 企业协同") {
                Button(action: { viewModel.applySuggestion("把整理好的文件同步上传到飞书云文档") }) {
                    Label("飞书生态协同", systemImage: "paperplane.fill")
                }
                Button(action: { viewModel.applySuggestion("将选中的文件归档到企业微信微盘并通知群聊") }) {
                    Label("企业微信协同", systemImage: "bubble.left.and.bubble.right.fill")
                }
                Button(action: { viewModel.applySuggestion("把选中的文件上传钉盘并自动发起审批流") }) {
                    Label("钉钉云文档与审批", systemImage: "bell.badge.fill")
                }
            }
            
            Divider()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.currentPage = .settings(initialTab: .skills)
                }
            }) {
                Label("打开 Skill 管理中心...", systemImage: "puzzlepiece.extension")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("点击选择或调用 Skill 技能")
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
