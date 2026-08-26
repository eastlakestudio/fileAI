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
    @Published public var isMiniMode: Bool = false
    
    private let customDispatcher: AgentDispatcher?
    
    public init(dispatcher: AgentDispatcher? = nil) {
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
    
    /// 从 Finder 抓取最新选中的文件（异步非阻塞；未授权时由 osascript 触发 TCC 授权弹窗）
    public func fetchFromFinderAsync() {
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
                // 诊断模式：结果为空时在状态栏显示可查看诊断弹窗
                if urls.isEmpty {
                    self?.statusMessage = L10n.t("未获取到选中文件，点击右侧「诊断」查看详情")
                }
                self?.setTargetURLs(urls)
            }
        }
    }
    
    /// 从 Finder 抓取最新选中的文件（历史同步接口：内部改走异步，避免 AppleScript 阻塞主线程）
    public func fetchFromFinder() {
        fetchFromFinderAsync()
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
    
    /// 提交用户自然语言指令
    public func submitInstruction(_ text: String? = nil) {
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
        
        if fileItems.isEmpty {
            statusMessage = L10n.t("⚠️ 请先在 Finder 中选择文件或点击「手动选取」")
            return
        }
        
        self.inputText = "" // 发送后清空输入框
        self.mainTab = .chatTimeline // 发送指令后自动聚焦到对话任务流
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
                    await self.loadTaskHistory()
                    self.activeTask = nil
                } else {
                    self.statusMessage = L10n.t("💡 未匹配到需要变动的文件，请尝试调整指令或参考上方推荐 Skill (⏱️ %@)", String(format: "%.2fs", elapsed))
                    self.updateSessionTask(id: taskRecord.id) { task in
                        task.status = .failed
                        task.completedAt = Date()
                        task.errorMessage = L10n.t("未匹配到需要变动的文件")
                    }
                    await TaskManager.shared.failTask(id: taskRecord.id, error: L10n.t("未匹配到需要变动的文件"))
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
                    for rev in createdReverses {
                        if !producedURLs.contains(rev.currentURL) {
                            producedURLs.append(rev.currentURL)
                            fileSummaryLines.append(L10n.t("📄 %@ (源: %@)", rev.currentURL.lastPathComponent, rev.originalURL.lastPathComponent))
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
                    await self.loadTaskHistory()
                }
                
                self.currentPlan = nil
                self.activeTask = nil
                self.statusMessage = L10n.t("✅ 执行完成 (共 %@ 项操作)", "\(count)")
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
