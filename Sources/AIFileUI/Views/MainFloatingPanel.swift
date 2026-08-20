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
        .onAppear {
            viewModel.fetchFromFinder()
            viewModel.loadTaskHistory()
        }
    }
    
    private var mainPanelBody: some View {
        VStack(spacing: 0) {
            // 1. 顶部单行一体化控制栏 (与系统红绿灯 100% 同行对齐，填入最顶端)
            unifiedTopBar
            
            Divider().opacity(0.3)
            
            // 2. 主内容展示区 (对话任务流 / 文件展示区，弹性撑满整个高度)
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
                
                if !viewModel.fileItems.isEmpty {
                    Text("• \(viewModel.fileItems.count) 项待处理")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
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
                onSelectSuggestion: { prompt in viewModel.applySuggestion(prompt) }
            )
        }
    }
    
    private var bottomChatInputBar: some View {
        VStack(spacing: 6) {
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
            }
            
            if let msg = viewModel.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(msg.contains("❌") ? .red : .accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 现代化一体输入卡片组件（内嵌选中文件悬浮胶囊、多行输入与底部工具栏）
            ModernChatInputCardView(viewModel: viewModel)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
