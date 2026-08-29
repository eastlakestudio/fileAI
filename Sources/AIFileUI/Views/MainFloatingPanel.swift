import SwiftUI
import AIFileCore
import AIFileFinderIntegration

/// 聊天输入卡片高度测量键：把输入卡片实测高度传给待办面板，保证切换等高
private struct ChatInputCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
public struct MainFloatingPanel: View {
    @StateObject public var viewModel: PanelViewModel
    /// 界面语言切换刷新令牌：切换后强制重建视图树，让全部字面量文案按新语言重新解析
    @State private var languageRefreshToken: UUID = UUID()
    
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LiquidGlassBackground(
                cornerRadius: 16,
                isCapsule: false,
                isDraggingOver: viewModel.isDraggingFilesOver,
                isStandardLargePanel: viewModel.widgetPresentationMode == .fullWindow || !viewModel.isMiniMode
            )
        )
        .ignoresSafeArea(.all)
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDraggingFilesOver) { providers in
            let group = DispatchGroup()
            var droppedURLs: [URL] = []
            let lock = NSLock()
            
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    if let url = url {
                        lock.lock()
                        droppedURLs.append(url)
                        lock.unlock()
                    }
                }
            }
            
            group.notify(queue: .main) {
                if !droppedURLs.isEmpty {
                    viewModel.handleDroppedURLs(droppedURLs)
                }
            }
            return true
        }
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
        .sheet(item: $viewModel.selectedDetailTask) { task in
            TaskDetailSheetView(
                task: task,
                liveTaskProvider: { id in
                    viewModel.sessionTasks.first(where: { $0.id == id }) ?? viewModel.taskHistory.first(where: { $0.id == id })
                },
                onRerunTask: { task in
                    viewModel.selectedDetailTask = nil
                    viewModel.rerunTask(task)
                },
                onClose: {
                    viewModel.selectedDetailTask = nil
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingDiagnosticsSheet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("🔍 Finder 抓取诊断"))
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Button(L10n.t("复制")) {
                        if let diag = viewModel.lastFinderDiagnostics {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(diag, forType: .string)
                        }
                    }
                    .controlSize(.mini)
                    Button(L10n.t("关闭")) {
                        viewModel.isShowingDiagnosticsSheet = false
                    }
                    .controlSize(.mini)
                    .keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    Text(viewModel.lastFinderDiagnostics ?? L10n.t("暂无诊断记录（请先点 ↻ 抓取一次）"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 220)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }
            .padding(16)
            .frame(width: 480)
        }
        .onAppear {
            viewModel.fetchFromFinderSilently()
            viewModel.loadTaskHistory()
        }
        .id(languageRefreshToken)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("aifiles.languageDidChange"))) { _ in
            languageRefreshToken = UUID()
        }
    }
    
    private var mainPanelBody: some View {
        Group {
            switch viewModel.widgetPresentationMode {
            case .widgetCard:
                DesktopWidgetCardView(viewModel: viewModel)
                    .transition(.opacity)
            case .fullWindow:
                // 标准模式：完整标题栏 + 时间线对话/任务流 + 底部输入框
                VStack(spacing: 0) {
                    // 1. 顶部单行一体化控制栏
                    unifiedTopBar
                    
                    Divider().opacity(0.3)
                    
                    // 2. 主内容展示区 (对话任务流 / 文件展示区)
                    mainContentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Divider().opacity(0.2)
                    
                    // 3. 底部自然语言交互栏
                    bottomChatInputBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Mini Mode Switcher (聊天/待办 垂直图标按钮，位于输入框左侧)

    /// 聊天输入卡片实测高度：待办面板严格取同一高度，保证切换等高
    @State private var chatInputCardHeight: CGFloat = 66

    private func miniTodoPanel(height: CGFloat) -> some View {
        MiniTodoListView(viewModel: viewModel)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    // 与聊天输入卡片一致的均匀玻璃半透
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.40), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 3.5)
    }

    private var miniModeSwitcher: some View {
        VStack(spacing: 3) {
            miniModeButton("text.bubble", tab: .chat, helpText: L10n.t("返回聊天面板"))
            miniModeButton("checklist", tab: .todoList, helpText: L10n.t("查看 AI 提炼的待办清单"))
        }
    }

    /// 未完结待办数（按钮右上角徽标）
    private var pendingTodoCount: Int {
        viewModel.todos.filter { $0.status == .pending || $0.status == .inProgress }.count
    }

    private func miniModeButton(_ systemName: String, tab: MiniContentTab, helpText: String) -> some View {
        let isSelected = viewModel.contentTab == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.contentTab = tab
            }
        }) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .overlay(alignment: .topTrailing) {
            if tab == .todoList && pendingTodoCount > 0 {
                Text("\(pendingTodoCount)")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .frame(height: 9)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 4, y: -4)
            }
        }
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
                
                if !viewModel.fileItems.isEmpty {
                    Text(L10n.t("• %@ 项待处理", "\(viewModel.fileItems.count)"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 顶栏右侧快捷功能入口
            HStack(spacing: 6) {
                // 任务看板入口
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.currentPage = .taskBoard
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11))
                        Text("任务")
                            .font(.system(size: 11, weight: .medium))
                        if !viewModel.sessionTasks.isEmpty {
                            Text("\(viewModel.sessionTasks.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t("查看已执行/正在执行的任务记录"))
                
                // 配置管理入口
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.currentPage = .settings(initialTab: .cliModel)
                    }
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t("配置管理（本地 CLI 引擎与本地技能库）"))
                
                // 桌面钉住切换按钮
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.isPinnedToDesktop.toggle()
                    }
                }) {
                    Image(systemName: viewModel.isPinnedToDesktop ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.isPinnedToDesktop ? .accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(viewModel.isPinnedToDesktop ? L10n.t("取消桌面钉住（恢复普通窗口）") : L10n.t("钉住到桌面：常驻所有空间、不抢焦点"))
                
                // 桌面小组件模式切换按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        viewModel.widgetPresentationMode = .widgetCard
                    }
                }) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t("收起为桌面小组件卡片"))
            }
        }
        .padding(.leading, 78) // 预留左侧 78px 红黄绿系统按钮位置
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            // 聊天记录面板最上方：常驻展示当前多文件与目录上下文（不可关闭）
            PinnedTargetFilesHeaderView(viewModel: viewModel)
            
            if viewModel.contentTab == .todoList {
                ScrollView(.vertical, showsIndicators: false) {
                    MiniTodoListView(viewModel: viewModel, compact: false)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.40), Color.white.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 3.5)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                ChatTimelineView(
                    tasks: viewModel.sessionTasks,
                    activeTaskId: viewModel.activeTask?.id,
                    liveThinkingSeconds: viewModel.thinkingElapsedSeconds,
                    smartSuggestions: viewModel.smartSuggestions,
                    onConfirmExecution: { viewModel.confirmExecution() },
                    onCancelExecution: { viewModel.cancelCurrentExecution() },
                    onRerunTask: { task in viewModel.rerunTask(task) },
                    onShowDetail: { task in viewModel.selectedDetailTask = task },
                    onUndoTask: { task in viewModel.undoLastOperation() },
                    onSelectSuggestion: { prompt in viewModel.applySuggestion(prompt) },
                    onAnswerClarification: { task, option in viewModel.answerClarification(task: task, option: option) }
                )
                .transition(.opacity)
            }
        }
    }
    
    private var bottomChatInputBar: some View {
        VStack(spacing: 5) {
            if let msg = viewModel.statusMessage {
                HStack(spacing: 5) {
                    Image(systemName: msg.contains("✅") ? "checkmark.circle.fill" : (msg.contains("❌") ? "xmark.circle.fill" : "info.circle.fill"))
                        .font(.system(size: 10.5))
                        .foregroundColor(msg.contains("✅") ? .green : (msg.contains("❌") ? .red : .accentColor))
                    
                    Text(msg)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(msg.contains("✅") ? .green : (msg.contains("❌") ? .red : .primary))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !viewModel.latestOutputURLs.isEmpty {
                        Button("在访达中定位结果 ↗") {
                            viewModel.openLatestOutputDirectory()
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
            
            // 输入卡片 + 右侧 聊天/待办 垂直切换按钮（与迷你模式同款开关）
            HStack(alignment: .center, spacing: 8) {
                ModernChatInputCardView(viewModel: viewModel)

                miniModeSwitcher
                    .padding(.trailing, 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
