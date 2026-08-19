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

@MainActor
public final class PanelViewModel: ObservableObject, ConsentGateDelegate {
    @Published public var rawURLs: [URL] = []
    @Published public var fileItems: [FileItem] = []
    @Published public var viewMode: FileListViewMode = .list
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
    @Published public var latestOutputURLs: [URL] = []
    private var thinkingTimerCancellable: AnyCancellable?
    
    @Published public var currentPlan: ExecutionPlan? = nil
    @Published public var isShowingDiffPreview: Bool = false
    @Published public var activeTask: TaskExecutionRecord? = nil
    
    @Published public var isShowingModelSettings: Bool = false
    
    @Published public var consentRequest: ConsentRequest? = nil
    @Published public var isShowingConsentModal: Bool = false
    private var consentContinuation: CheckedContinuation<ConsentDecision, Never>?
    
    @Published public var smartSuggestions: [SkillSuggestion] = []
    
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
                let execPath = CLIDiscoveryEngine.shared.findExecutablePath(for: type.executableNames)
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
    
    /// 从 Finder 抓取最新选中的文件
    public func fetchFromFinder() {
        let urls = FinderContextReader.shared.getSelectedFinderItems()
        setTargetURLs(urls)
    }
    
    /// 手动打开文件选择器
    public func pickFilesManually() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "选择需要 AI 批处理的文件或文件夹"
        
        if panel.runModal() == .OK {
            setTargetURLs(panel.urls)
        }
    }
    
    /// 设置当前操作的目标 URL 列表
    public func setTargetURLs(_ urls: [URL]) {
        self.rawURLs = urls
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
            return "未选择路径"
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
            statusMessage = "⚠️ 请先在 Finder 中选择文件或点击「手动选取」"
            return
        }
        
        isThinking = true
        thinkingElapsedSeconds = 0.0
        statusMessage = "AI 正在分析意图并规划操作方案... (⏱️ 0.0s)"
        
        // 启动实时秒表计时器
        let startTime = Date()
        thinkingTimerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isThinking else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                self.thinkingElapsedSeconds = elapsed
                self.statusMessage = "AI 正在分析意图并规划操作方案... (⏱️ \(String(format: "%.1fs", elapsed)))"
            }
        
        Task {
            // 1. 任务提交瞬间立即持久化记录为【进行中】，绑定目标文件路径
            let targetPaths = self.fileItems.map { $0.url.path }
            let initialPlan = ExecutionPlan(summary: "正在规划意图...", actions: [])
            let taskRecord = await TaskManager.shared.createTask(prompt: prompt, plan: initialPlan, targetFilePaths: targetPaths)
            self.activeTask = taskRecord
            
            do {
                let plan = try await dispatcher.generatePlan(userPrompt: prompt, fileItems: fileItems)
                let elapsed = Date().timeIntervalSince(startTime)
                self.currentPlan = plan
                self.isThinking = false
                self.thinkingTimerCancellable?.cancel()
                self.statusMessage = nil
                
                // 更新持久化任务中的 plan
                await TaskManager.shared.updateTaskPlan(id: taskRecord.id, plan: plan, targetFilePaths: targetPaths)
                
                if !plan.actions.isEmpty {
                    self.isShowingDiffPreview = true
                } else if !plan.summary.isEmpty && plan.summary != "计划执行 0 项操作" {
                    self.statusMessage = "\(plan.summary) (⏱️ \(String(format: "%.2fs", elapsed)))"
                    // 问答/查询/统计类操作（无物理文件变动），直接记录为已完成并写入 AI 回复
                    await TaskManager.shared.completeTask(id: taskRecord.id, transactionId: nil, walkthrough: plan.summary)
                    self.activeTask = nil
                } else {
                    self.statusMessage = "💡 未匹配到需要变动的文件，请尝试调整指令或参考上方推荐 Skill (⏱️ \(String(format: "%.2fs", elapsed)))"
                    await TaskManager.shared.failTask(id: taskRecord.id, error: "未匹配到需要变动的文件")
                    self.activeTask = nil
                }
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                self.isThinking = false
                self.thinkingTimerCancellable?.cancel()
                self.statusMessage = "规划失败: \(error.localizedDescription) (⏱️ \(String(format: "%.1fs", elapsed)))"
                // 规划阶段出错时，立即持久化记录为【执行失败】，写入任务看板！
                await TaskManager.shared.failTask(id: taskRecord.id, error: error.localizedDescription)
                self.activeTask = nil
            }
        }
    }
    
    /// 用户确认执行计划
    public func confirmExecution() {
        guard let plan = currentPlan else { return }
        isShowingDiffPreview = false
        statusMessage = "正在安全执行文件操作..."
        
        Task {
            do {
                let record = try await dispatcher.executePlan(plan: plan)
                
                var fileSummaryLines: [String] = []
                var producedURLs: [URL] = []
                for action in plan.actions {
                    if let dest = action.targetURL {
                        producedURLs.append(dest)
                        fileSummaryLines.append("📄 \(dest.lastPathComponent) (源: \(action.sourceURL.lastPathComponent))")
                    } else {
                        producedURLs.append(action.sourceURL)
                        fileSummaryLines.append("📄 \(action.sourceURL.lastPathComponent)")
                    }
                }
                self.latestOutputURLs = producedURLs
                
                let count = record.reverseActions.count
                guard count > 0 else {
                    throw NSError(
                        domain: "SafeFileExecutor",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "操作未能成功生成目标文件，请检查文件格式或系统依赖权限"]
                    )
                }
                
                let filesBlock = fileSummaryLines.isEmpty ? "（无新文件生成）" : fileSummaryLines.joined(separator: "\n")
                let walkthrough = "✅ 成功完成 \(count) 项物理操作\n变更概览: \(plan.summary)\n\n📂 生成结果文件列表:\n\(filesBlock)"
                
                if let task = self.activeTask {
                    await TaskManager.shared.completeTask(id: task.id, transactionId: record.id, walkthrough: walkthrough)
                }
                
                statusMessage = "✅ 成功完成 \(count) 项操作！已写入任务看板，可随时 ⌘Z 撤销"
                refreshFiles()
                currentPlan = nil
                activeTask = nil
            } catch {
                if let task = self.activeTask {
                    await TaskManager.shared.failTask(id: task.id, error: error.localizedDescription)
                }
                statusMessage = "❌ 执行失败: \(error.localizedDescription)"
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
            Task {
                await TaskManager.shared.cancelTask(id: task.id)
            }
        }
        currentPlan = nil
        activeTask = nil
        statusMessage = "已取消执行"
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
            self.statusMessage = "⚠️ 原任务的目标文件已不存在或已被移除"
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
        return "本地内置"
    }
    
    /// 撤销上一次事务操作
    public func undoLastOperation() {
        Task {
            do {
                if let record = try await TransactionJournal.shared.undoLatest() {
                    await TaskManager.shared.markReverted(transactionId: record.id)
                    statusMessage = "↩️ 已成功撤销: \(record.description)"
                    refreshFiles()
                } else {
                    statusMessage = "没有可撤销的操作"
                }
            } catch {
                statusMessage = "撤销失败: \(error.localizedDescription)"
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
}
