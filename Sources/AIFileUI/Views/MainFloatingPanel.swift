import SwiftUI
import AIFileCore
import AIFileFinderIntegration

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
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: viewModel.isMiniMode ? 160 : 450, maxHeight: viewModel.isMiniMode ? 235 : .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.82))
                
                // 次表面流动微光层
                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.08), Color.clear]),
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 400
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.40),
                            Color.white.opacity(0.12),
                            Color.black.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 6)
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
            viewModel.fetchFromFinder()
            viewModel.loadTaskHistory()
        }
        .id(languageRefreshToken)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("aifiles.languageDidChange"))) { _ in
            languageRefreshToken = UUID()
        }
    }
    
    private var mainPanelBody: some View {
        Group {
            if viewModel.isMiniMode {
                // 迷你模式：彻底无系统标题栏，聊天框始终贴紧底端，预留空间居中于目标文件与聊天框之间
                VStack(spacing: 0) {
                    // 1. 顶部目标文件胶囊
                    PinnedTargetFilesHeaderView(viewModel: viewModel)
                        .padding(.top, 6)
                    
                    // 2. 中间弹性预留区（展示执行状态与结果定位，位于聊天框正上方）
                    VStack(spacing: 4) {
                        Spacer(minLength: 4)
                        
                        if viewModel.isShowingAutomationGuide {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.orange)
                                Text(L10n.t("需要「自动化」权限读取 Finder 选中项，点击右侧按钮去开启"))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(2)
                                Spacer()
                                Button(L10n.t("去系统设置开启")) {
                                    FinderContextReader.shared.openAutomationSettingsPane()
                                    viewModel.isShowingAutomationGuide = false
                                }
                                .font(.system(size: 9.5, weight: .semibold))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                Button {
                                    viewModel.isShowingAutomationGuide = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                            .padding(.horizontal, 14)
                            .transition(.opacity)
                        } else if let msg = viewModel.statusMessage {
                            HStack(spacing: 5) {
                                Image(systemName: msg.contains("✅") ? "checkmark.circle.fill" : (msg.contains("❌") ? "xmark.circle.fill" : "info.circle.fill"))
                                    .font(.system(size: 10.5))
                                    .foregroundColor(msg.contains("✅") ? .green : (msg.contains("❌") ? .red : .accentColor))
                                
                                Text(msg)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(msg.contains("✅") ? .green : (msg.contains("❌") ? .red : .primary))
                                    .lineLimit(1)
                                
                                if viewModel.lastFinderDiagnostics != nil {
                                    Button(L10n.t("诊断")) {
                                        viewModel.isShowingDiagnosticsSheet = true
                                    }
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .padding(.horizontal, 14)
                            .transition(.opacity)
                        }
                        
                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 3. 底部自然语言输入卡片（始终紧贴底端）
                    ModernChatInputCardView(viewModel: viewModel)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .frame(minWidth: 640, maxWidth: .infinity, minHeight: 160, maxHeight: 235)
            } else {
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
                .frame(minWidth: 640, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity, alignment: .top)
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
                
                // 迷你模式切换按钮
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.isMiniMode.toggle()
                    }
                }) {
                    Image(systemName: viewModel.isMiniMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(viewModel.isMiniMode ? L10n.t("展开为标准完整面板") : L10n.t("收起为迷你悬浮卡片"))
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
            
            // 现代化一体输入卡片组件（内嵌选中文件悬浮胶囊、多行输入与底部工具栏）
            ModernChatInputCardView(viewModel: viewModel)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
