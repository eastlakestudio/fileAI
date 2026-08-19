import SwiftUI
import ServiceManagement
import AIFileCore

/// 配置管理主导航 Tab 枚举 (云端 API 与本地 CLI 明确解耦二选一)
public enum SettingsNavTab: String, CaseIterable, Identifiable, Sendable {
    case cloudModel = "云端 API 引擎"
    case cliModel = "本地 CLI 引擎"
    case skills = "本地技能库"
    case marketplace = "云端技能库"
    case general = "偏好与系统"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .cloudModel: return "network"
        case .cliModel: return "terminal.fill"
        case .skills: return "puzzlepiece.extension.fill"
        case .marketplace: return "icloud.and.arrow.down.fill"
        case .general: return "gearshape.fill"
        }
    }
}

/// 统一配置管理页面：整合云端/本地模型设置、Skill 技能管理、云端市场与系统偏好
public struct UnifiedSettingsView: View {
    @State private var selectedTab: SettingsNavTab
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("uiWindowMode") private var uiWindowMode: String = "standard"
    
    // Model Settings 状态
    @State private var modelSettings: ModelSettings
    @State private var availableProviders: [ProviderDefinition] = []
    @State private var discoveredCLIs: [DiscoveredCLITool] = []
    @State private var isScanningCLIs: Bool = false
    @State private var isShowApiKey: Bool = false
    @State private var testStatus: String? = nil
    @State private var isTesting: Bool = false
    
    // Skill Management 状态
    @State private var selectedSkillCategory: SkillCategory = .all
    @State private var localSkills: [SkillMetadata] = []
    @State private var cloudSkills: [SkillMetadata] = []
    @State private var expandedSkillId: String? = nil
    @State private var isShowingImportModal: Bool = false
    @State private var importMarkdownText: String = ""
    @State private var importErrorMessage: String? = nil
    
    public let onBack: () -> Void
    public var onSelectPrompt: ((String) -> Void)? = nil
    
    public init(
        initialTab: SettingsNavTab = .cloudModel,
        onBack: @escaping () -> Void,
        onSelectPrompt: ((String) -> Void)? = nil
    ) {
        let initialSettings = ModelSettingsManager.shared.settings
        self._modelSettings = State(initialValue: initialSettings)
        
        // 若未显式指定，根据当前活跃 Provider 自动定位到云端或本地 CLI 导航
        let activeTab: SettingsNavTab = {
            if initialTab != .cloudModel { return initialTab }
            return initialSettings.providerId.starts(with: "cli_") ? .cliModel : .cloudModel
        }()
        self._selectedTab = State(initialValue: activeTab)
        self.onBack = onBack
        self.onSelectPrompt = onSelectPrompt
    }
    
    private var cloudProviders: [ProviderDefinition] {
        availableProviders.filter { !$0.isLocal }
    }
    
    private var currentProvider: ProviderDefinition? {
        availableProviders.first(where: { $0.id == modelSettings.providerId }) ?? cloudProviders.first
    }
    
    private var isUsingLocalCLI: Bool {
        modelSettings.providerId.starts(with: "cli_")
    }
    
    private var displayedLocalSkills: [SkillMetadata] {
        if selectedSkillCategory == .all {
            return localSkills
        }
        return localSkills.filter { $0.category == selectedSkillCategory }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部贴顶纯净导航条 (无多余杂乱按钮)
            topNavigationBar
            
            Divider().opacity(0.3)
            
            // 2. 经典 macOS 左右两栏导航
            HStack(spacing: 0) {
                leftSidebarNavigation
                    .frame(width: 190)
                
                Divider().opacity(0.2)
                
                rightContentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider().opacity(0.2)
            
            // 3. 底部状态栏
            bottomActionBar
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
        .sheet(isPresented: $isShowingImportModal) {
            importMarkdownSkillSheet
        }
        .onAppear {
            reloadAllData()
        }
    }
    
    // MARK: - 1. Top Navigation Bar (极简纯净)
    
    private var topNavigationBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("返回主页")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("配置管理中心 • \(selectedTab.rawValue)")
                    .font(.system(size: 12, weight: .bold))
            }
            
            Spacer()
        }
        .padding(.leading, 78) // 预留交通灯
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    // MARK: - 2. Left Sidebar Navigation
    
    private var leftSidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI 引擎模式 (二选一)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            
            // 引擎 1：云端 API
            tabNavRow(
                tab: .cloudModel,
                badge: !isUsingLocalCLI ? "当前使用" : "\(cloudProviders.count) 个"
            )
            
            // 引擎 2：本地 CLI
            tabNavRow(
                tab: .cliModel,
                badge: isUsingLocalCLI ? "当前使用" : "\(discoveredCLIs.filter { $0.isInstalled }.count) 就绪"
            )
            
            Text("功能扩展")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            tabNavRow(tab: .skills, badge: "\(localSkills.count)")
            tabNavRow(tab: .marketplace, badge: "云端 \(cloudSkills.count)")
            
            Text("系统设置")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            tabNavRow(tab: .general, badge: "⌥M")
            
            Spacer()
            
            Divider().padding(.horizontal, 8)
            
            // 底部快捷工具入口
            VStack(spacing: 6) {
                Button(action: {
                    SkillManager.shared.openSkillsDirectoryInFinder()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("打开本地 Skills 目录")
                    }
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button(action: {
                    ProviderConfigRegistry.shared.openConfigFileInFinder()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.gearshape")
                        Text("编辑 providers.json")
                    }
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.02))
    }
    
    @ViewBuilder
    private func tabNavRow(tab: SettingsNavTab, badge: String) -> some View {
        let isSelected = selectedTab == tab
        let isCurrentEngine = (tab == .cloudModel && !isUsingLocalCLI) || (tab == .cliModel && isUsingLocalCLI)
        
        Button(action: {
            selectedTab = tab
            testStatus = nil
        }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)
                
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
                
                Text(badge)
                    .font(.system(size: 9, weight: isCurrentEngine ? .bold : .regular, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isCurrentEngine ? Color.green.opacity(0.18) : (isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
                    .foregroundColor(isCurrentEngine ? .green : (isSelected ? .accentColor : .secondary))
                    .cornerRadius(3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    // MARK: - 3. Right Content Area
    
    private var rightContentArea: some View {
        Group {
            switch selectedTab {
            case .cloudModel:
                ScrollView {
                    cloudAPISection
                        .padding(14)
                }
            case .cliModel:
                ScrollView {
                    localCLIDiscoverySection
                        .padding(14)
                }
            case .skills:
                skillLibraryContentView
            case .marketplace:
                cloudMarketplaceContentView
            case .general:
                generalPreferencesContentView
            }
        }
    }
    
    // MARK: - Tab 1: 云端 API 配置区
    
    private var cloudAPISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("云端 API 模型服务商配置:")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if !isUsingLocalCLI {
                    Text("● 正在作为活跃 AI 引擎")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            
            VStack(spacing: 10) {
                // 1. 服务商
                HStack(spacing: 10) {
                    Text("模型服务商:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    
                    Picker("", selection: Binding(
                        get: { modelSettings.providerId },
                        set: { newId in
                            if let p = availableProviders.first(where: { $0.id == newId }) {
                                selectProvider(p)
                            }
                        }
                    )) {
                        ForEach(cloudProviders) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Spacer()
                }
                
                // 2. 选用模型 (下拉选择官方预设模型，或在无预设时自由输入)
                HStack(spacing: 10) {
                    Text("选用模型:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    
                    if let provider = currentProvider, !provider.models.isEmpty {
                        Picker("", selection: Binding(
                            get: {
                                provider.models.contains(where: { $0.id == modelSettings.modelName }) ? modelSettings.modelName : (provider.defaultModel?.id ?? modelSettings.modelName)
                            },
                            set: { newModelId in
                                modelSettings.modelName = newModelId
                            }
                        )) {
                            ForEach(provider.models) { model in
                                HStack {
                                    Text(model.name)
                                    if model.isRecommended {
                                        Text("[推荐]")
                                    }
                                }
                                .tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("输入具体 Model 标识符 (如 deepseek-chat, gpt-4o 等)", text: $modelSettings.modelName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .cornerRadius(5)
                    }
                    
                    Spacer()
                }
                
                Divider().opacity(0.15)
                
                // 3. API Key
                HStack(spacing: 10) {
                    Text("API Key / Token:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    
                    HStack {
                        if isShowApiKey {
                            TextField("输入 API Key (如 sk-...)", text: $modelSettings.apiKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("输入 API Key (如 sk-...)", text: $modelSettings.apiKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        
                        Button(action: { isShowApiKey.toggle() }) {
                            Image(systemName: isShowApiKey ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .cornerRadius(5)
                }
                
                // 4. Base URL
                HStack(spacing: 10) {
                    Text("Base URL:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    
                    TextField("API 端点地址 (如 https://api.deepseek.com/v1)", text: $modelSettings.baseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .cornerRadius(5)
                }
                
                // 5. 采样温度
                HStack(spacing: 10) {
                    Text("采样温度 (Temp):")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    
                    Slider(value: $modelSettings.temperature, in: 0.0...1.0, step: 0.05)
                    
                    Text(String(format: "%.2f", modelSettings.temperature))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(!isUsingLocalCLI ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }
    
    // MARK: - Tab 2: 本地 CLI 配置区
    
    private var localCLIDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地已安装 AI CLI 工具 (自动检测无需 API Key):")
                        .font(.system(size: 12, weight: .bold))
                    Text("选择下方任意已就绪的 CLI 工具，将自动切换为本地终端引擎：")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { scanLocalCLIs() }) {
                    HStack(spacing: 3) {
                        if isScanningCLIs {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("重新扫描")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isScanningCLIs)
            }
            
            VStack(spacing: 8) {
                ForEach(discoveredCLIs) { cli in
                    let isSelected = modelSettings.providerId == cli.id
                    cliToolCardRow(cli: cli, isSelected: isSelected)
                }
            }
        }
    }
    
    @ViewBuilder
    private func cliToolCardRow(cli: DiscoveredCLITool, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: cli.isInstalled ? "terminal.fill" : "terminal")
                    .font(.system(size: 15))
                    .foregroundColor(cli.isInstalled ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(cli.name)
                            .font(.system(size: 12, weight: .bold))
                        
                        if cli.isInstalled {
                            Text("已安装 (免Key)")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(3)
                        } else {
                            Text("未安装")
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .foregroundColor(.secondary)
                                .cornerRadius(3)
                        }
                    }
                    
                    Text(cli.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if cli.isInstalled {
                    if isSelected {
                        Button(action: { selectCLITool(cli) }) {
                            Text("✓ 正在使用")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    } else {
                        Button(action: { selectCLITool(cli) }) {
                            Text("切换为此 CLI")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                } else if let url = URL(string: cli.installGuideURL) {
                    Link("安装指引", destination: url)
                        .font(.system(size: 10))
                }
            }
            
            if isSelected && cli.isInstalled {
                Divider().opacity(0.15)
                
                HStack(spacing: 8) {
                    Text("选用模型:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    if !cli.availableModels.isEmpty {
                        Picker("", selection: $modelSettings.modelName) {
                            ForEach(cli.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    } else {
                        TextField("输入模型标识符 (如 gemini-3.7-flash, gpt-4o 等)", text: $modelSettings.modelName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(4)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(6)
    }
    
    // MARK: - Tab: Skill 技能库
    
    private var skillLibraryContentView: some View {
        VStack(spacing: 0) {
            // 分类胶囊栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SkillCategory.allCases.filter { $0 != .cloudMarket }) { cat in
                        let isCatSelected = selectedSkillCategory == cat
                        let count = cat == .all ? localSkills.count : localSkills.filter { $0.category == cat }.count
                        Button(action: { selectedSkillCategory = cat }) {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 9))
                                Text("\(cat.rawValue) (\(count))")
                                    .font(.system(size: 11, weight: isCatSelected ? .bold : .regular))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isCatSelected ? Color.accentColor : Color.primary.opacity(0.06))
                            .foregroundColor(isCatSelected ? .white : .primary)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        importErrorMessage = nil
                        importMarkdownText = defaultMarkdownTemplate
                        isShowingImportModal = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                            Text("导入 Skill")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Color.primary.opacity(0.02))
            
            Divider().opacity(0.15)
            
            // 技能卡片列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    if displayedLocalSkills.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("当前分类暂无已安装的 Skill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(displayedLocalSkills) { skill in
                            skillCardRow(skill: skill)
                        }
                    }
                }
                .padding(14)
            }
        }
    }
    
    @ViewBuilder
    private func skillCardRow(skill: SkillMetadata) -> some View {
        let isExpanded = expandedSkillId == skill.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.system(size: 14))
                    .foregroundColor(skill.isEnabled ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(skill.isEnabled ? 0.12 : 0.05))
                    .cornerRadius(5)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(skill.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(skill.isEnabled ? .primary : .secondary)
                        
                        Text(skill.category.rawValue)
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                    
                    Text(skill.summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedSkillId = isExpanded ? nil : skill.id
                    }
                }) {
                    Text(isExpanded ? "收起" : "参数/示例")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { newVal in toggleSkill(id: skill.id, isEnabled: newVal) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            
            if isExpanded {
                Divider().opacity(0.15)
                
                if !skill.examplePrompts.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("💡 示例指令 (点击立即填入主页):")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        ForEach(skill.examplePrompts, id: \.self) { prompt in
                            Button(action: {
                                onSelectPrompt?(prompt)
                                onBack()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 9))
                                    Text(prompt)
                                        .font(.system(size: 10))
                                    Spacer()
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.08))
                                .foregroundColor(.accentColor)
                                .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(skill.isEnabled ? 0.85 : 0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(skill.isEnabled ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(6)
    }
    
    // MARK: - Tab: 云端扩展市场
    
    private var cloudMarketplaceContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("所有技能均以独立 Markdown (.md) 文件提供，点击「一键安装」即可下载至本地：")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                ForEach(cloudSkills) { skill in
                    HStack(spacing: 8) {
                        Image(systemName: skill.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(5)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.name)
                                .font(.system(size: 12, weight: .bold))
                            Text(skill.summary)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if skill.isInstalled {
                            Text("✓ 已安装")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            Button("一键安装") {
                                installCloudSkill(skill)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                }
            }
            .padding(14)
        }
    }
    
    // MARK: - Tab: 偏好与系统
    
    private var generalPreferencesContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. 系统启动与交互呈现模式卡片
                VStack(alignment: .leading, spacing: 10) {
                    Text("⚙️ 系统与交互偏好")
                        .font(.system(size: 12, weight: .bold))
                    
                    // 开机自启动
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开机自动启动")
                                .font(.system(size: 11, weight: .medium))
                            Text("登录 macOS 系统时在后台静默启动常驻守护")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin },
                            set: { newVal in
                                launchAtLogin = newVal
                                setLaunchAtLogin(enabled: newVal)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    
                    Divider().opacity(0.15)
                    
                    // 窗口交互呈现模式
                    VStack(alignment: .leading, spacing: 6) {
                        Text("窗口交互呈现模式:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack(spacing: 8) {
                            Button(action: { uiWindowMode = "standard" }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 14))
                                        .foregroundColor(uiWindowMode == "standard" ? .accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("标准面板模式")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("完整文件树、多文件批量与看板")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(uiWindowMode == "standard" ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(uiWindowMode == "standard" ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { uiWindowMode = "mini" }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "rectangle.compress.vertical")
                                        .font(.system(size: 14))
                                        .foregroundColor(uiWindowMode == "mini" ? .accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Mini 聊天框模式")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("极简悬浮输入胶囊与即时触发")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(uiWindowMode == "mini" ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(uiWindowMode == "mini" ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .cornerRadius(8)
                
                // 2. 快捷键卡片
                VStack(alignment: .leading, spacing: 8) {
                    Text("⌨️ 全局快捷键与呼出")
                        .font(.system(size: 12, weight: .bold))
                    
                    HStack {
                        Text("呼出/隐藏文件魔法棒:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⌥ M (Option + M)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("撤销上次物理文件操作:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⌘ Z (Command + Z)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("退出应用程序:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⌘ Q (Command + Q)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .cornerRadius(8)
                
                // 3. 系统单进程与安全守护
                VStack(alignment: .leading, spacing: 8) {
                    Text("🛡️ 系统单进程与安全守护")
                        .font(.system(size: 12, weight: .bold))
                    
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("POSIX 单进程独占锁已激活 (禁止多开并自动激活现有窗口)")
                            .font(.system(size: 11))
                    }
                    
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                            .foregroundColor(.blue)
                        Text("原子事务日志回滚栈已就绪 (全面支持无损 Undo)")
                            .font(.system(size: 11))
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .cornerRadius(8)
                
                Spacer()
                
                // 退出应用
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                        Text("退出文件魔法棒")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
        }
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("LaunchAtLogin setting status changed: \(enabled)")
            }
        }
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            if selectedTab == .cloudModel || selectedTab == .cliModel {
                Button(action: testConnection) {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                        }
                        Text("测试连通性")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)
                
                if let status = testStatus {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(status.contains("✅") ? .green : .red)
                        .lineLimit(1)
                }
            } else if selectedTab == .skills {
                Text("已启用 \(localSkills.filter { $0.isEnabled }.count) / \(localSkills.count) 个本地 Markdown 技能")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("保存并返回") {
                ModelSettingsManager.shared.updateSettings(modelSettings)
                onBack()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    // MARK: - 导入弹窗
    
    private var importMarkdownSkillSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("导入新的 Markdown Skill 文件")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button("关闭") { isShowingImportModal = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            
            TextEditor(text: $importMarkdownText)
                .font(.system(size: 10, design: .monospaced))
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(5)
                .frame(minHeight: 200)
            
            if let err = importErrorMessage {
                Text(err).font(.system(size: 10)).foregroundColor(.red)
            }
            
            HStack {
                Spacer()
                Button("立即安装保存") {
                    let result = SkillManager.shared.installFromMarkdown(content: importMarkdownText)
                    if result.success {
                        reloadSkills()
                        isShowingImportModal = false
                    } else {
                        importErrorMessage = result.error ?? "安装失败"
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 500, height: 360)
    }
    
    private var defaultMarkdownTemplate: String {
        """
        ---
        id: custom_script_skill
        name: 自定义文件处理 Skill
        icon: wand.and.stars
        category: custom
        summary: 执行自定义文件处理规则
        extensions: [*]
        ---

        # 自定义 Skill
        """
    }
    
    // MARK: - Data Loaders & Handlers
    
    private func reloadAllData() {
        reloadProviders()
        scanLocalCLIs()
        reloadSkills()
    }
    
    private func reloadProviders() {
        ProviderConfigRegistry.shared.reload()
        self.availableProviders = ProviderConfigRegistry.shared.providers
    }
    
    private func scanLocalCLIs() {
        isScanningCLIs = true
        Task {
            let tools = await CLIDiscoveryEngine.shared.discoverAllTools()
            self.discoveredCLIs = tools
            self.isScanningCLIs = false
        }
    }
    
    private func reloadSkills() {
        SkillManager.shared.reloadLocalSkills()
        self.localSkills = SkillManager.shared.allSkills
        self.cloudSkills = SkillManager.shared.cloudMarketSkills
    }
    
    private func selectProvider(_ provider: ProviderDefinition) {
        modelSettings.providerId = provider.id
        modelSettings.baseURL = provider.baseURL
        if let defModel = provider.defaultModel {
            modelSettings.modelName = defModel.id
        }
        testStatus = "✅ 已选用 \(provider.name)"
    }
    
    private func selectCLITool(_ tool: DiscoveredCLITool) {
        modelSettings.providerId = tool.id
        modelSettings.baseURL = tool.executablePath ?? "cli://\(tool.type.rawValue)"
        if let firstModel = tool.availableModels.first {
            modelSettings.modelName = firstModel
        }
        testStatus = "✅ 已选用 \(tool.name) 本地调度"
    }
    
    private func toggleSkill(id: String, isEnabled: Bool) {
        SkillManager.shared.setSkillEnabled(id: id, isEnabled: isEnabled)
        reloadSkills()
    }
    
    private func installCloudSkill(_ skill: SkillMetadata) {
        SkillManager.shared.installSkill(skill)
        reloadSkills()
    }
    
    private func testConnection() {
        isTesting = true
        testStatus = "正在测试连接..."
        Task {
            do {
                let msg = try await ModelSettingsManager.shared.testConnection(settings: modelSettings)
                self.testStatus = msg
                self.isTesting = false
            } catch {
                self.testStatus = "❌ \(error.localizedDescription)"
                self.isTesting = false
            }
        }
    }
}
