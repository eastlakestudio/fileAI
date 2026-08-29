import Foundation
import SwiftUI
import AppKit
import Combine
import AIFileCore
import AIFileSkills
import AIFileAgent
import AIFileFinderIntegration

public enum AppNavigationPage: Equatable, Sendable {
    case main
    case taskBoard
    case settings(initialTab: SettingsNavTab)
}

public enum FileListViewMode: String, CaseIterable, Identifiable {
    case list = "平铺列表"
    case tree = "路径树状"
    public var id: String { rawValue }
}

public enum MainViewContentTab: String, CaseIterable, Identifiable {
    case chatTimeline = "对话流"
    case fileList = "选中文件"
    public var id: String { rawValue }
}

/// 迷你窗口内容区切换：聊天（现状布局） / 待办清单（AI 从聊天任务提炼）
public enum MiniContentTab: String, CaseIterable, Identifiable {
    case chat = "聊天"
    case todoList = "待办"
    public var id: String { rawValue }
}

@MainActor
public final class PanelViewModel: ObservableObject, ConsentGateDelegate {
    @Published public var rawURLs: [URL] = []
    @Published public var fileItems: [FileItem] = []
    @Published public var viewMode: FileListViewMode = .list
    @Published public var mainTab: MainViewContentTab = .chatTimeline
    @Published public var currentPage: AppNavigationPage = .main
    
    @Published public var isRecursive: Bool = false {
        didSet { refreshFiles() }
    }
    @Published public var selectedExtensionFilter: String? = nil {
        didSet { refreshFiles() }
    }
    
    @Published public var inputText: String = ""
    @Published public var isThinking: Bool = false
    @Published public var thinkingElapsedSeconds: Double = 0
    @Published public var statusMessage: String? = nil
    /// 桌面钉住模式：窗口常驻所有空间、不抢焦点，像桌面小组件一样贴在桌面
    @Published public var isPinnedToDesktop: Bool = UserDefaults.standard.bool(forKey: "aifiles.pinnedToDesktop") {
        didSet { UserDefaults.standard.set(isPinnedToDesktop, forKey: "aifiles.pinnedToDesktop") }
    }
    /// Finder 自动化权限缺失时的引导横幅
    @Published public var isShowingAutomationGuide: Bool = false
    /// 最近一次 Finder 抓取的诊断信息（界面弹窗展示）
    @Published public var lastFinderDiagnostics: String? = nil
    /// 诊断弹窗显示状态
    @Published public var isShowingDiagnosticsSheet: Bool = false
    @Published public var latestOutputURLs: [URL] = []
    private var thinkingTimerCancellable: AnyCancellable?
    
    @Published public var currentPlan: ExecutionPlan? = nil
    @Published public var isShowingDiffPreview: Bool = false
    @Published public var activeTask: TaskExecutionRecord? = nil
    @Published public var sessionTasks: [TaskExecutionRecord] = []
    @Published public var taskHistory: [TaskExecutionRecord] = []
    @Published public var selectedDetailTask: TaskExecutionRecord? = nil
    
    @Published public var isShowingModelSettings: Bool = false
    
    @Published public var consentRequest: ConsentRequest? = nil
    @Published public var isShowingConsentModal: Bool = false
    private var consentContinuation: CheckedContinuation<ConsentDecision, Never>?
    
    @Published public var smartSuggestions: [SkillSuggestion] = []
    @Published public var executionMode: String = "Agent 模式"
    @Published public var reasoningEffort: String = "High"
    @Published public var isMiniMode: Bool = false {
        didSet {
            if isMiniMode && widgetPresentationMode == .fullWindow {
                widgetPresentationMode = .widgetCard
            } else if !isMiniMode && widgetPresentationMode != .fullWindow {
                widgetPresentationMode = .fullWindow
            }
        }
    }
    
    /// 桌面小组件展现形态 (.pillCapsule 灵动胶囊 / .widgetCard 桌面卡片 / .fullWindow 标准大窗)
    @Published public var widgetPresentationMode: WidgetPresentationMode = .widgetCard {
        didSet {
            isMiniMode = (widgetPresentationMode != .fullWindow)
            widgetSettings.presentationMode = widgetPresentationMode
            widgetSettings.save()
        }
    }
    
    /// 桌面小组件层级 (.floating 始终置顶 / .desktopLevel 贴合桌面)
    @Published public var widgetLevelMode: WidgetLevelMode = .floating {
        didSet {
            isPinnedToDesktop = (widgetLevelMode == .desktopLevel || isPinnedToDesktop)
            widgetSettings.levelMode = widgetLevelMode
            widgetSettings.save()
        }
    }
    
    /// 桌面小组件持久化配置
    @Published public var widgetSettings: DesktopWidgetSettings
    
    /// 外部拖拽文件悬停高亮标识
    @Published public var isDraggingFilesOver: Bool = false
    
    /// 聊天 / 待办 面板切换（迷你窗=底部区域切换；标准窗=主内容区切换）
    @Published public var contentTab: MiniContentTab = .chat
    /// 待办清单（由模型从聊天任务提炼，跨启动持久化）
    @Published public var todos: [TodoItem] = []
    /// 正在调用模型提炼待办（UI 指示与防重入）
    @Published public var isExtractingTodos: Bool = false
    /// 任务 id → 关联待办 id 映射：执行完成后自动勾选待办，失败/取消则还原为待处理
    private var linkedTodosByTaskId: [UUID: UUID] = [:]
    
    private let customDispatcher: AgentDispatcher?
    
    public init(dispatcher: AgentDispatcher? = nil) {
        let savedSettings = DesktopWidgetSettings.load()
        self.widgetSettings = savedSettings
        self.widgetPresentationMode = savedSettings.presentationMode
        self.widgetLevelMode = savedSettings.levelMode
        self.isMiniMode = (savedSettings.presentationMode != .fullWindow)
        
        let registry = SkillRegistry.shared
        registry.register(ImageResizeSkill())
        registry.register(ImageConvertSkill())
        registry.register(DocToPDFSkill())
        registry.register(PDFMergeSplitSkill())
        registry.register(BatchRenameSkill())
        
        self.customDispatcher = dispatcher
        
        ContentConsentGate.shared.delegate = self
        updateSuggestions()
        loadTaskHistory()
        loadTodos()
    }
    
    public var dispatcher: AgentDispatcher {
        if let custom = customDispatcher {
            return custom
        }
        let settings = ModelSettingsManager.shared.settings
        let registry = SkillRegistry.shared
        
        if settings.providerId.starts(with: "cli_") {
            let toolTypeRaw = String(settings.providerId.dropFirst(4))
            if let type = CLIToolType(rawValue: toolTypeRaw) {
                // 优先使用扫描并保存在配置中的确切绝对路径，若无则实时探测
                var execPath: String? = nil
                if !settings.baseURL.isEmpty && !settings.baseURL.starts(with: "cli://") && FileManager.default.fileExists(atPath: settings.baseURL) {
                    execPath = settings.baseURL
                } else {
                    execPath = CLIDiscoveryEngine.shared.findExecutablePath(for: type.executableNames)
                }
                
                let tool = DiscoveredCLITool(type: type, executablePath: execPath, isInstalled: execPath != nil)
                let client = CLIModelClient(tool: tool, modelName: settings.modelName)
                return AgentDispatcher(provider: client, registry: registry)
            }
        }
        
        if !settings.apiKey.isEmpty {
            let client = OpenAICompatibleClient(
                providerName: settings.providerId,
                apiKey: settings.apiKey,
                baseURLString: settings.baseURL,
                modelName: settings.modelName
            )
            return AgentDispatcher(provider: client, registry: registry)
        }
        
        return AgentDispatcher(provider: MockLLMClient(), registry: registry)
    }
    
    /// 从 Finder 抓取最新选中的文件（异步非阻塞）
    /// - Parameter silent: 静默模式（启动/onAppear 自动抓取用）——为空时不提示，避免刷屏
    public func fetchFromFinderAsync(silent: Bool = false) {
        Task { [weak self] in
            let urls = await FinderContextReader.shared.getSelectedFinderItemsAsync(
                onPermissionDenied: {
                    Task { @MainActor in
                        self?.statusMessage = L10n.t("需要「自动化」权限读取 Finder 选中项：请在系统设置 → 隐私与安全性 → 自动化 中允许本应用控制 Finder")
                        self?.isShowingAutomationGuide = true
                    }
                },
                onDiagnostics: { diag in
                    Task { @MainActor in
                        self?.lastFinderDiagnostics = diag
                    }
                }
            )
            await MainActor.run {
                // 抓取为空：静默保持现状（Finder 本就无选中是正常场景，不弹提示刷屏）；
                // 仅当已有文件列表被清空时提示。诊断可随时通过标题栏 🩺 按钮查看。
                if !silent && urls.isEmpty && !(self?.fileItems.isEmpty ?? true) {
                    self?.statusMessage = L10n.t("Finder 当前无选中项（诊断详情见标题栏 🩺 按钮）")
                }
                self?.setTargetURLs(urls)
            }
        }
    }
    
    /// 从 Finder 抓取最新选中的文件（历史同步接口：内部改走异步，避免 AppleScript 阻塞主线程）
    public func fetchFromFinder() {
        fetchFromFinderAsync()
    }
    
    /// 静默抓取（启动/onAppear 自动场景：无选中不提示）
    public func fetchFromFinderSilently() {
        fetchFromFinderAsync(silent: true)
    }
    
    /// 手动打开文件选择器
    public func pickFilesManually() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = L10n.t("选择需要 AI 批处理的文件或文件夹")
        
        if panel.runModal() == .OK {
            setTargetURLs(panel.urls)
        }
    }
    
    /// 设置当前操作的目标 URL 列表
    public func setTargetURLs(_ urls: [URL]) {
        self.rawURLs = urls
        refreshFiles()
    }
    
    /// 移除当前选中的单个文件项
    public func removeFileItem(id: String) {
        if let item = fileItems.first(where: { $0.id == id }) {
            self.rawURLs.removeAll(where: { $0.path == item.url.path })
            refreshFiles()
        }
    }
    
    /// 清空当前所有选中的文件
    public func clearSelectedFiles() {
        self.rawURLs = []
        refreshFiles()
    }
    
    /// 响应外部文件直接拖拽投放至桌面组件
    public func handleDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        setTargetURLs(urls)
        statusMessage = "⚡ \(L10n.t("已接收 %@ 个拖放文件", "\(urls.count)"))"
    }
    
    /// 切换小组件形态 (卡片 ↔ 大窗)
    public func cycleWidgetPresentationMode() {
        switch widgetPresentationMode {
        case .widgetCard:
            widgetPresentationMode = .fullWindow
        case .fullWindow:
            widgetPresentationMode = .widgetCard
        }
    }
    
    /// 刷新元数据提取结果
    public func refreshFiles() {
        var allowedExts: Set<String>? = nil
        if let filter = selectedExtensionFilter, !filter.isEmpty {
            allowedExts = [filter.lowercased()]
        }
        
        self.fileItems = FileMetadataEngine.shared.collectMetadata(
            from: rawURLs,
            recursive: isRecursive,
            allowedExtensions: allowedExts
        )
        updateSuggestions()
    }
    
    /// 计算共同祖先目录
    public var commonParentDirectoryPath: String {
        guard let first = fileItems.first?.url.deletingLastPathComponent().path else {
            return L10n.t("未选择路径")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return first.replacingOccurrences(of: home, with: "~")
    }
    
    /// 更新动态推荐的 Skills
    public func updateSuggestions() {
        self.smartSuggestions = SmartSkillSuggester.shared.suggestSkills(for: fileItems)
    }
    
    /// 所有检测到的文件扩展名（供过滤器使用）
    public var availableExtensions: [String] {
        let allExts = FileMetadataEngine.shared.collectMetadata(from: rawURLs, recursive: isRecursive).map { $0.fileExtension }.filter { !$0.isEmpty }
        return Array(Set(allExts)).sorted()
    }
    
    /// 提交用户自然语言指令（linkedTodoId：由待办清单发起的执行，完成后自动勾选该待办）
    public func submitInstruction(_ text: String? = nil, linkedTodoId: UUID? = nil) {
        Task { @MainActor in
            await submitInstructionAsync(text, linkedTodoId: linkedTodoId)
        }
    }
    
    @MainActor
    private func submitInstructionAsync(_ text: String? = nil, linkedTodoId: UUID? = nil) async {
        let prompt = (text ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        if prompt == "__PICK_FILES__" {
            pickFilesManually()
            return
        }
        if prompt == "__REFRESH_FINDER__" {
            fetchFromFinder()
            return
        }
        
        // 无目标文件不再拦截：闲聊→本地秒回；提问/任务→完整规划（LLM Direct Answer 模式回答）
        self.inputText = "" // 发送后清空输入框
        self.mainTab = .chatTimeline // 发送指令后自动聚焦到对话任务流
        
        // 0. 意图探测（完全由 CLI/LLM 判断，本地零规则）：CASUAL → 展示模型回复；TASK/QUESTION → 完整规划
        //    无论是否有目标文件都探测（有文件时用户也可能只是打招呼）
        doProbe: do {
            isThinking = true
            statusMessage = L10n.t("AI 正在分析意图...")
            let probe = await dispatcher.detectIntentViaLLM(userPrompt: prompt)
            self.isThinking = false
            if probe.isCasual {
                let reply = probe.reply?.isEmpty == false ? probe.reply! : L10n.t("你好！我是文件魔法棒 ✨ 在 Finder 选中文件后，直接告诉我你想做什么（如「压缩后发飞书」「转成 PDF」「批量重命名」），我立刻处理。")
                var casualTask = TaskExecutionRecord(
                    prompt: prompt,
                    status: .completed,
                    plan: ExecutionPlan(summary: reply, actions: []),
                    targetFilePaths: []
                )
                casualTask.completedAt = Date()
                casualTask.walkthroughReport = reply
                self.sessionTasks.removeAll(where: { $0.id == casualTask.id })
                self.sessionTasks.insert(casualTask, at: 0)
                self.taskHistory.removeAll(where: { $0.id == casualTask.id })
                self.taskHistory.insert(casualTask, at: 0)
                self.activeTask = nil
                self.statusMessage = nil
                Task { await TaskManager.shared.recordTask(casualTask) }
                return
            }
        }
        
        isThinking = true
        thinkingElapsedSeconds = 0.0
        statusMessage = L10n.t("AI 正在分析意图并规划操作方案... (⏱️ %@)", "0.0s")
        
        // 1. 任务提交瞬间立即在 MainActor 同步创建卡片，推入聊天任务流
        let targetPaths = self.fileItems.map { $0.url.path }
        let initialPlan = ExecutionPlan(summary: L10n.t("正在规划意图..."), actions: [])
        let taskRecord = TaskExecutionRecord(
            prompt: prompt,
            status: .inProgress,
            plan: initialPlan,
            targetFilePaths: targetPaths
        )
        self.activeTask = taskRecord
        self.sessionTasks.removeAll(where: { $0.id == taskRecord.id })
        self.sessionTasks.insert(taskRecord, at: 0)
        self.taskHistory.removeAll(where: { $0.id == taskRecord.id })
        self.taskHistory.insert(taskRecord, at: 0)
        
        // 待办发起的执行：登记映射并标记为进行中（完成/失败时回写）
        if let todoId = linkedTodoId {
            linkedTodosByTaskId[taskRecord.id] = todoId
            setTodoStatus(id: todoId, .inProgress)
        }
        
        // 启动实时秒表计时器
        let startTime = Date()
        thinkingTimerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isThinking else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                self.thinkingElapsedSeconds = elapsed
                self.statusMessage = L10n.t("AI 正在分析意图并规划操作方案... (⏱️ %@)", String(format: "%.1fs", elapsed))
            }
        
        Task {
            // 异步持久化到 TaskManager
            await TaskManager.shared.recordTask(taskRecord)
            
            do {
                let plan = try await dispatcher.generatePlan(userPrompt: prompt, fileItems: fileItems)
                let elapsed = Date().timeIntervalSince(startTime)
                self.currentPlan = plan
                self.isThinking = false
                self.thinkingTimerCancellable?.cancel()
                self.statusMessage = nil
                
                // 更新会话任务与持久化任务中的 plan
                self.updateSessionTask(id: taskRecord.id) { task in
                    task.plan = plan
                    if task.targetFilePaths.isEmpty {
                        task.targetFilePaths = targetPaths
                    }
                }
                await TaskManager.shared.updateTaskPlan(id: taskRecord.id, plan: plan, targetFilePaths: targetPaths)
                await self.loadTaskHistory()
                
                let isAutonomous = self.executionMode.contains("自主") || self.executionMode.contains("Agent")
                
                if plan.isAwaitingClarification {
                    self.statusMessage = L10n.t("❓ %@", plan.clarification?.question ?? L10n.t("需要您确认操作选项"))
                    self.updateSessionTask(id: taskRecord.id) { task in
                        task.status = .waitingForClarification
                        task.plan = plan
                    }
                } else if isAutonomous && !plan.actions.isEmpty {
                    // 自主/Agent 模式：规划完成后自动执行物理操作，免除人工点击确认，端到端极速闭环
                    self.statusMessage = L10n.t("⚡ 正在自动执行操作方案...")
                    self.confirmExecution()
                } else if !plan.actions.isEmpty {
                    self.isShowingDiffPreview = true
                } else if !plan.summary.isEmpty && plan.summary != L10n.t("计划执行 %@ 项操作", "0") {
                    self.statusMessage = L10n.t("%@ (⏱️ %@)", plan.summary, String(format: "%.2fs", elapsed))
                    // 问答/查询/统计类操作（无物理文件变动），直接记录为已完成并写入 AI 回复
                    self.updateSessionTask(id: taskRecord.id) { task in
                        task.status = .completed
                        task.completedAt = Date()
                        task.walkthroughReport = plan.summary
                    }
                    await TaskManager.shared.completeTask(id: taskRecord.id, transactionId: nil, walkthrough: plan.summary)
                    self.completeLinkedTodo(forTaskId: taskRecord.id)
                    await self.loadTaskHistory()
                    self.generateTodosFromRecentChats(manual: false)
                    self.activeTask = nil
                } else {
                    self.statusMessage = L10n.t("💡 未匹配到需要变动的文件，请尝试调整指令或参考上方推荐 Skill (⏱️ %@)", String(format: "%.2fs", elapsed))
                    self.updateSessionTask(id: taskRecord.id) { task in
                        task.status = .failed
                        task.completedAt = Date()
                        task.errorMessage = L10n.t("未匹配到需要变动的文件")
                    }
                    await TaskManager.shared.failTask(id: taskRecord.id, error: L10n.t("未匹配到需要变动的文件"))
                    self.revertLinkedTodo(forTaskId: taskRecord.id)
                    await self.loadTaskHistory()
                    self.activeTask = nil
                }
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                self.isThinking = false
                self.thinkingTimerCancellable?.cancel()
                self.statusMessage = L10n.t("规划失败: %@ (⏱️ %@)", error.localizedDescription, String(format: "%.1fs", elapsed))
                // 规划阶段出错时，立即记录为【执行失败】
                self.updateSessionTask(id: taskRecord.id) { task in
                    task.status = .failed
                    task.completedAt = Date()
                    task.errorMessage = error.localizedDescription
                }
                await TaskManager.shared.failTask(id: taskRecord.id, error: error.localizedDescription)
                self.revertLinkedTodo(forTaskId: taskRecord.id)
                await self.loadTaskHistory()
                self.activeTask = nil
            }
        }
    }
    
    /// 用户确认执行计划
    public func confirmExecution() {
        guard let plan = currentPlan else { return }
        isShowingDiffPreview = false
        statusMessage = L10n.t("正在安全执行文件操作...")
        
        Task {
            do {
                let record = try await dispatcher.executePlan(plan: plan)
                
                var fileSummaryLines: [String] = []
                var producedURLs: [URL] = []
                
                let createdReverses = record.reverseActions.filter { $0.kind == .deleteCreated || $0.kind == .renameBack }
                if !createdReverses.isEmpty {
                    let cwdPath = FileManager.default.currentDirectoryPath
                    for rev in createdReverses {
                        if !producedURLs.contains(rev.currentURL) {
                            producedURLs.append(rev.currentURL)
                            let originalPath = rev.originalURL.path
                            // 纯生成型产物（无实质输入文件）不伪标来源，避免误导
                            if rev.kind == .deleteCreated && (originalPath == "/" || originalPath == cwdPath || !FileManager.default.fileExists(atPath: originalPath)) {
                                fileSummaryLines.append(L10n.t("📄 %@ (新产物)", rev.currentURL.lastPathComponent))
                            } else {
                                fileSummaryLines.append(L10n.t("📄 %@ (源: %@)", rev.currentURL.lastPathComponent, rev.originalURL.lastPathComponent))
                            }
                        }
                    }
                } else {
                    for action in plan.actions {
                        if let dest = action.targetURL, FileManager.default.fileExists(atPath: dest.path) {
                            if !producedURLs.contains(dest) {
                                producedURLs.append(dest)
                                fileSummaryLines.append(L10n.t("📄 %@ (源: %@)", dest.lastPathComponent, action.sourceURL.lastPathComponent))
                            }
                        }
                    }
                    if producedURLs.isEmpty {
                        fileSummaryLines.append(L10n.t("ℹ️ 纯内容/网络查询或协同任务，未产生本地物理文件变动"))
                    }
                }
                self.latestOutputURLs = producedURLs

                // 待办清单类产物（文件名含 待办/todo/checklist）直接解析并导入 App 的待办面板，可勾选完成；
                // 导入成功后无需再走通用提炼（避免重复）
                var importedTodoCount = 0
                if let sourceTaskId = self.activeTask?.id {
                    for url in producedURLs {
                        importedTodoCount += await TodoImporter.importIfNeeded(url: url, sourceTaskId: sourceTaskId)
                    }
                }

                let count = record.reverseActions.count > 0 ? record.reverseActions.count : plan.actions.count
                let filesBlock = fileSummaryLines.joined(separator: "\n")
                let walkthrough = L10n.t("✅ 成功完成 %@ 项操作\n变更概览: %@\n\n📂 生成结果文件列表:\n%@", "\(count)", plan.summary, filesBlock)

                if let task = self.activeTask {
                    var execLogs = task.executionLogs.isEmpty ? task.plan.executionLogs : task.executionLogs
                    execLogs.append(L10n.t("⚡ 安全沙盒开始执行 %@ 个文件物理操作...", "\(plan.actions.count)"))
                    execLogs.append(L10n.t("💾 写入事务安全日志 (ID: %@)", "\(record.id.uuidString.prefix(8))"))
                    execLogs.append(L10n.t("✅ 全部文件物理变更执行完成"))

                    self.updateSessionTask(id: task.id) { item in
                        item.status = .completed
                        item.completedAt = Date()
                        item.transactionId = record.id
                        item.walkthroughReport = walkthrough
                        item.executionLogs = execLogs
                    }
                    await TaskManager.shared.completeTask(id: task.id, transactionId: record.id, walkthrough: walkthrough)
                    self.completeLinkedTodo(forTaskId: task.id)
                    await self.loadTaskHistory()
                    if importedTodoCount == 0 {
                        self.generateTodosFromRecentChats(manual: false)
                    }
                }
                
                self.currentPlan = nil
                self.activeTask = nil
                if importedTodoCount > 0 {
                    self.loadTodos()
                    self.statusMessage = L10n.t("✅ 执行完成 (共 %@ 项操作) • 已把 %@ 条待办导入待办面板", "\(count)", "\(importedTodoCount)")
                } else {
                    self.statusMessage = L10n.t("✅ 执行完成 (共 %@ 项操作)", "\(count)")
                }
                refreshFiles()
                currentPlan = nil
                activeTask = nil
            } catch {
                if let task = self.activeTask {
                    self.updateSessionTask(id: task.id) { item in
                        item.status = .failed
                        item.completedAt = Date()
                        item.errorMessage = error.localizedDescription
                    }
                    await TaskManager.shared.failTask(id: task.id, error: error.localizedDescription)
                    self.revertLinkedTodo(forTaskId: task.id)
                    await self.loadTaskHistory()
                }
                statusMessage = L10n.t("❌ 执行失败: %@", error.localizedDescription)
            }
        }
    }
    
    /// 在访达中高亮显示最近生成的所有结果文件
    public func revealLatestOutputFiles() {
        guard !latestOutputURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(latestOutputURLs)
    }
    
    /// 打开最近结果文件所在的文件夹
    public func openLatestOutputDirectory() {
        guard let firstURL = latestOutputURLs.first else { return }
        let dirURL = firstURL.deletingLastPathComponent()
        NSWorkspace.shared.open(dirURL)
    }
    
    /// 直接在访达中定位单个文件
    public func revealFile(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    /// 直接使用默认应用打开单个文件
    public func openFile(at url: URL) {
        NSWorkspace.shared.open(url)
    }
    public func cancelCurrentExecution() {
        isShowingDiffPreview = false
        if let task = activeTask {
            updateSessionTask(id: task.id) { item in
                item.status = .cancelled
                item.completedAt = Date()
                item.errorMessage = L10n.t("用户取消了执行确认")
            }
            revertLinkedTodo(forTaskId: task.id)
            Task {
                await TaskManager.shared.cancelTask(id: task.id)
                await self.loadTaskHistory()
            }
        }
        currentPlan = nil
        activeTask = nil
        statusMessage = L10n.t("已取消执行")
    }
    
    /// 从持久化存储中重新加载全部任务卡片历史
    public func loadTaskHistory() async {
        let tasks = await TaskManager.shared.allTasks
        self.taskHistory = tasks
    }
    
    public func loadTaskHistory() {
        Task {
            await self.loadTaskHistory()
        }
    }
    
    public func liveTask(for id: UUID) -> TaskExecutionRecord? {
        return sessionTasks.first(where: { $0.id == id }) ?? taskHistory.first(where: { $0.id == id })
    }
    
    /// 删除单个任务
    public func deleteTask(id: UUID) {
        sessionTasks.removeAll(where: { $0.id == id })
        taskHistory.removeAll(where: { $0.id == id })
        if activeTask?.id == id {
            activeTask = nil
        }
        Task {
            await TaskManager.shared.deleteTask(id: id)
            await loadTaskHistory()
        }
    }
    
    /// 清空所有历史任务
    public func clearAllTasks() {
        sessionTasks.removeAll()
        taskHistory.removeAll()
        activeTask = nil
        Task {
            await TaskManager.shared.clearAllTasks()
            await loadTaskHistory()
        }
    }
    
    private func updateSessionTask(id: UUID, _ mutation: (inout TaskExecutionRecord) -> Void) {
        if let index = sessionTasks.firstIndex(where: { $0.id == id }) {
            mutation(&sessionTasks[index])
        }
    }
    
    /// 点击推荐胶囊：填充指令文本，避免直接静默提交
    public func applySuggestion(_ text: String) {
        if text == "__PICK_FILES__" {
            pickFilesManually()
        } else if text == "__REFRESH_FINDER__" {
            fetchFromFinder()
        } else {
            self.inputText = text
        }
    }
    
    /// 针对指定历史任务重新绑定其原本的目标文件并再次执行
    public func rerunTask(_ task: TaskExecutionRecord) {
        var targetPaths = task.targetFilePaths
        if targetPaths.isEmpty {
            targetPaths = task.plan.actions.map { $0.sourceURL.path }
        }
        
        let existingURLs = targetPaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        
        if !existingURLs.isEmpty {
            self.setTargetURLs(existingURLs)
        } else if !targetPaths.isEmpty {
            self.statusMessage = L10n.t("⚠️ 原任务的目标文件已不存在或已被移除")
        }
        
        self.currentPage = .main
        self.inputText = task.prompt
        self.submitInstruction(task.prompt)
    }
    
    /// 当前启用的模型服务名称展示
    public var activeModelDisplayName: String {
        let s = ModelSettingsManager.shared.settings
        if s.providerId.starts(with: "cli_") {
            let toolName = s.providerId.replacingOccurrences(of: "cli_", with: "")
            return "\(toolName) · \(s.modelName)"
        } else if !s.providerId.isEmpty {
            return "\(s.providerId) · \(s.modelName)"
        }
        return L10n.t("本地内置")
    }
    
    /// 撤销上一次事务操作
    public func undoLastOperation() {
        Task {
            do {
                if let record = try await TransactionJournal.shared.undoLatest() {
                    await TaskManager.shared.markReverted(transactionId: record.id)
                    for i in 0..<self.sessionTasks.count {
                        if self.sessionTasks[i].transactionId == record.id {
                            self.sessionTasks[i].status = .reverted
                        }
                    }
                    statusMessage = L10n.t("↩️ 已成功撤销: %@", record.description)
                    refreshFiles()
                } else {
                    statusMessage = L10n.t("没有可撤销的操作")
                }
            } catch {
                statusMessage = L10n.t("撤销失败: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - 待办清单（AI 从聊天任务提炼）

    public func loadTodos() {
        Task {
            self.todos = await TodoStore.shared.displayOrdered
        }
    }

    /// 点击勾选/取消勾选一条待办
    public func toggleTodoDone(_ id: UUID) {
        guard let item = todos.first(where: { $0.id == id }) else { return }
        setTodoStatus(id: id, item.status == .done ? .pending : .done)
    }

    /// 忽略一条待办（不再展示在上半区，可从清除按钮回收）
    public func dismissTodo(id: UUID) {
        setTodoStatus(id: id, .dismissed)
    }

    public func deleteTodo(id: UUID) {
        todos.removeAll(where: { $0.id == id })
        Task { await TodoStore.shared.remove(id: id) }
    }

    /// 清除全部已完成/已忽略条目
    public func clearFinishedTodos() {
        todos.removeAll(where: { !$0.status.isActive })
        Task { await TodoStore.shared.clearFinished() }
    }

    /// 执行一条待办：以标题为指令发起真实执行流程，并建立关联以便完成后自动勾选；
    /// 同时切回聊天面板让用户看到执行进度
    public func executeTodo(_ todo: TodoItem) {
        guard todo.status.isActive else { return }
        withAnimationIfPossible { contentTab = .chat }
        submitInstruction(todo.title, linkedTodoId: todo.id)
    }

    /// 触发 UI 动画的辅助（VM 层不持有动画参数时的轻量包装）
    private func withAnimationIfPossible(_ body: () -> Void) {
        withAnimation(.easeInOut(duration: 0.18), body)
    }

    /// 从最近已完成的对话/任务记录中提炼待办行动项；
    /// manual=true 为用户手动触发（带结果提示），false 为任务完成后的静默后台提炼
    public func generateTodosFromRecentChats(manual: Bool) {
        guard !isExtractingTodos else { return }
        let recent = Array(taskHistory.filter { $0.status == .completed }.prefix(6))
        guard !recent.isEmpty else {
            if manual { statusMessage = L10n.t("暂无可提炼的已完成对话记录") }
            return
        }
        let transcript = recent.map { task -> String in
            let reply = String((task.walkthroughReport ?? task.plan.summary).prefix(200))
            return "用户: \(task.prompt)\n助手: \(reply)"
        }.joined(separator: "\n---\n")

        isExtractingTodos = true
        Task { [weak self] in
            defer { self?.isExtractingTodos = false }
            guard let items = await self?.dispatcher.extractTodos(fromTranscript: transcript), !items.isEmpty else {
                if manual { self?.statusMessage = L10n.t("没有提炼出新的待办") }
                return
            }
            let added = await TodoStore.shared.addNew(
                titlesWithDetail: items.map { ($0.title, $0.detail, nil) }
            )
            await MainActor.run { [weak self] in
                self?.loadTodos()
                if manual {
                    if added > 0 {
                        self?.statusMessage = L10n.t("✨ 已提炼 %@ 条新待办", "\(added)")
                    } else {
                        self?.statusMessage = L10n.t("没有提炼出新的待办")
                    }
                }
            }
        }
    }

    private func setTodoStatus(id: UUID, _ status: TodoStatus) {
        if let index = todos.firstIndex(where: { $0.id == id }) {
            todos[index].status = status
        }
        Task { await TodoStore.shared.setStatus(id: id, status) }
    }

    /// 关联任务执行完成：自动勾选待办并回写生成的任务 id
    private func completeLinkedTodo(forTaskId taskId: UUID) {
        guard let todoId = linkedTodosByTaskId.removeValue(forKey: taskId) else { return }
        setTodoStatus(id: todoId, .done)
        Task { await TodoStore.shared.linkGeneratedTask(id: todoId, generatedTaskId: taskId) }
    }

    /// 关联任务失败/取消：待办还原为待处理，允许重试
    private func revertLinkedTodo(forTaskId taskId: UUID) {
        guard let todoId = linkedTodosByTaskId.removeValue(forKey: taskId) else { return }
        setTodoStatus(id: todoId, .pending)
    }

    // MARK: - Consent Gate Delegate
    public func presentConsentModal(for request: ConsentRequest) async -> ConsentDecision {
        self.consentRequest = request
        self.isShowingConsentModal = true
        
        return await withCheckedContinuation { continuation in
            self.consentContinuation = continuation
        }
    }
    
    public func handleConsentDecision(_ decision: ConsentDecision) {
        isShowingConsentModal = false
        consentContinuation?.resume(returning: decision)
        consentContinuation = nil
        consentRequest = nil
    }
    
    /// 用户在 UI 卡片中点击澄清选项后，将选项补充入原指令并继续执行
    public func answerClarification(task: TaskExecutionRecord, option: ClarificationOption) {
        let clarifiedPrompt = AgentDispatcher.resolveClarifiedPrompt(originalPrompt: task.prompt, option: option)
        submitInstruction(clarifiedPrompt)
    }
}
