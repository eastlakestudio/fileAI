import SwiftUI
import AIFileCore

public struct ModelSettingsView: View {
    @State private var settings: ModelSettings
    @State private var selectedTab: Int = 0 // 0: 云端 API, 1: 本地 CLI / 离线引擎
    @State private var availableProviders: [ProviderDefinition] = []
    @State private var discoveredCLIs: [DiscoveredCLITool] = []
    @State private var isScanningCLIs: Bool = false
    @State private var isShowApiKey: Bool = false
    @State private var testStatus: String? = nil
    @State private var isTesting: Bool = false
    public let onBack: () -> Void
    
    public init(onBack: @escaping () -> Void) {
        self._settings = State(initialValue: ModelSettingsManager.shared.settings)
        self.onBack = onBack
    }
    
    private var cloudProviders: [ProviderDefinition] {
        availableProviders.filter { !$0.isLocal }
    }
    
    private var currentProvider: ProviderDefinition? {
        availableProviders.first(where: { $0.id == settings.providerId }) ?? cloudProviders.first
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部贴顶导航条 (对齐红绿灯)
            topNavigationBar
            
            Divider().opacity(0.3)
            
            // 2. 主体配置内容 (根据 Tab 切换)
            ScrollView {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        // 🌐 云端 API 模型配置（下拉列表 + 可编辑模型名称）
                        cloudAPISection
                    } else {
                        // 💻 本地已安装 AI CLI 自动发现与配置
                        localCLIDiscoverySection
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().opacity(0.2)
            
            // 3. 底部操作栏
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
        .onAppear {
            reloadProviders()
            scanLocalCLIs()
        }
    }
    
    // MARK: - Top Navigation Bar
    
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
            
            Text("LLM 模型与引擎配置中心")
                .font(.system(size: 12, weight: .bold))
            
            Spacer()
            
            Picker("", selection: $selectedTab) {
                Text("🌐 云端 API 模型").tag(0)
                Text(L10n.t("💻 本地已安装 CLI (%@ 就绪)", "\(discoveredCLIs.filter { $0.isInstalled }.count)")).tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            .controlSize(.small)
        }
        .padding(.leading, 78) // 预留交通灯
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
    
    // MARK: - Tab 1: 云端 API 配置区 (下拉选择 + 可自由编辑模型)
    
    private var cloudAPISection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 服务商与预设下拉选择卡片
            VStack(spacing: 12) {
                // 1. 云端服务商下拉列表
                HStack(spacing: 12) {
                    Text("模型服务商:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 120, alignment: .leading)
                    
                    Picker("", selection: Binding(
                        get: { settings.providerId },
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
                
                // 2. 预设推荐模型下拉列表
                if let provider = currentProvider, !provider.models.isEmpty {
                    HStack(spacing: 12) {
                        Text("预设推荐模型:")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 120, alignment: .leading)
                        
                        Picker("", selection: Binding(
                            get: {
                                provider.models.contains(where: { $0.id == settings.modelName }) ? settings.modelName : (provider.defaultModel?.id ?? "")
                            },
                            set: { newModelId in
                                settings.modelName = newModelId
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
                        
                        Spacer()
                    }
                    
                    // 模型说明提示
                    if let activeDesc = provider.models.first(where: { $0.id == settings.modelName })?.description, !activeDesc.isEmpty {
                        HStack {
                            Text(L10n.t("💡 %@", activeDesc))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.leading, 132)
                    }
                }
                
                Divider().opacity(0.15)
                
                // 3. 模型名称 (支持手动编辑与输入任何新模型)
                HStack(spacing: 12) {
                    Text("模型名称 (可编辑):")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 120, alignment: .leading)
                    
                    TextField("输入具体 Model 标识符 (如 deepseek-chat, gpt-4o 等)", text: $settings.modelName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(7)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .cornerRadius(6)
                }
                
                // 4. API Key / Token
                HStack(spacing: 12) {
                    Text("API Key / Token:")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 120, alignment: .leading)
                    
                    HStack {
                        if isShowApiKey {
                            TextField("输入 API Key (如 sk-...)", text: $settings.apiKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("输入 API Key (如 sk-...)", text: $settings.apiKey)
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
                    .padding(7)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
                }
                
                // 5. Base URL
                HStack(spacing: 12) {
                    Text("Base URL (API地址):")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 120, alignment: .leading)
                    
                    TextField("API 端点地址 (如 https://api.deepseek.com/v1)", text: $settings.baseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(7)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .cornerRadius(6)
                }
                
                // 6. 采样温度 (Temperature) 与数值含义动态说明
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text("采样温度 (Temp):")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 120, alignment: .leading)
                        
                        Slider(value: $settings.temperature, in: 0.0...1.0, step: 0.05)
                        
                        Text(String(format: "%.2f", settings.temperature))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                    }
                    
                    // 动态模式与数值含义解析
                    HStack(spacing: 6) {
                        let cat = temperatureCategory(settings.temperature)
                        Text(cat.badge)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(cat.color.opacity(0.15))
                            .foregroundColor(cat.color)
                            .cornerRadius(4)
                        
                        Text(cat.explanation)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 132)
                }
                
                // 7. 官方文档直达超链接
                if let provider = currentProvider, !provider.docURL.isEmpty, let url = URL(string: provider.docURL) {
                    Divider().opacity(0.15)
                    
                    HStack {
                        Spacer()
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text(L10n.t("查看 %@ 官方开发文档与 API Key 申请", provider.name))
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }
    
    // MARK: - Tab 2: 本地已安装 AI CLI 自动发现
    
    private var localCLIDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地已安装 AI CLI 工具 (自动检测无需 API Key):")
                        .font(.system(size: 13, weight: .bold))
                    Text("自动检测系统中已安装并认证过的终端工具，无需填写 Token，直接复用已登录凭据。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { scanLocalCLIs() }) {
                    HStack(spacing: 4) {
                        if isScanningCLIs {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("重新扫描")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanningCLIs)
            }
            
            // CLI 工具卡片列表
            VStack(spacing: 10) {
                ForEach(discoveredCLIs) { cli in
                    let isSelected = settings.providerId == cli.id
                    cliToolCardRow(cli: cli, isSelected: isSelected)
                }
            }
        }
    }
    
    @ViewBuilder
    private func cliToolCardRow(cli: DiscoveredCLITool, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // 图标与名称
                Image(systemName: cli.isInstalled ? "terminal.fill" : "terminal")
                    .font(.system(size: 16))
                    .foregroundColor(cli.isInstalled ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cli.name)
                            .font(.system(size: 13, weight: .bold))
                        
                        if cli.isInstalled {
                            Text("已安装 (免Key)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                            
                            if let ver = cli.version {
                                Text(ver)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("未检测到安装")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(cli.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if let path = cli.executablePath {
                        Text(L10n.t("路径: %@", path))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // 选择按钮或安装指引
                if cli.isInstalled {
                    if isSelected {
                        Button(action: {
                            selectCLITool(cli)
                        }) {
                            Text("✓ 正在使用")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button(action: {
                            selectCLITool(cli)
                        }) {
                            Text("选用此 CLI")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    if let url = URL(string: cli.installGuideURL) {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle")
                                Text("安装指引")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            
            // 若已选定且有发现的模型，展示下拉选择列表与可自由编辑输入框
            if isSelected && cli.isInstalled {
                Divider().opacity(0.15)
                
                VStack(alignment: .leading, spacing: 8) {
                    // 1. 预设推荐模型下拉选择列表
                    if !cli.availableModels.isEmpty {
                        HStack(spacing: 12) {
                            Text("预设推荐模型:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 110, alignment: .leading)
                            
                            Picker("", selection: $settings.modelName) {
                                ForEach(cli.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Spacer()
                        }
                    }
                    
                    // 2. 模型名称 (支持自由键盘输入任何新版本/私有模型)
                    HStack(spacing: 12) {
                        Text("模型名称 (可编辑):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                        
                        TextField("输入具体 Model 标识符 (如 gemini-2.5-flash, claude-3-7-sonnet 等)", text: $settings.modelName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                            .cornerRadius(5)
                    }
                }
            }
        }
        .padding(12)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.08)
                : Color(nsColor: .controlBackgroundColor).opacity(0.4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            // 在访达中编辑 JSON
            Button(action: {
                ProviderConfigRegistry.shared.openConfigFileInFinder()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.gearshape")
                    Text("在访达中编辑 JSON 配置")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // 刷新 JSON
            Button(action: {
                reloadProviders()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.t("重新读取本地 providers_config.json"))
            
            // 测试连通性
            Button(action: testConnection) {
                HStack(spacing: 4) {
                    if isTesting {
                        ProgressView().scaleEffect(0.6)
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
                    .font(.system(size: 11))
                    .foregroundColor(status.contains("✅") ? .green : .red)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("保存并应用") {
                ModelSettingsManager.shared.updateSettings(settings)
                onBack()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func selectProvider(_ provider: ProviderDefinition) {
        settings.providerId = provider.id
        settings.baseURL = provider.baseURL
        if let defModel = provider.defaultModel {
            settings.modelName = defModel.id
        }
        testStatus = nil
    }
    
    private func selectCLITool(_ tool: DiscoveredCLITool) {
        settings.providerId = tool.id
        settings.baseURL = tool.executablePath ?? "cli://\(tool.type.rawValue)"
        if let firstModel = tool.availableModels.first {
            settings.modelName = firstModel
        }
        testStatus = L10n.t("✅ 已选用 %@ 本地调度", tool.name)
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
    
    private func testConnection() {
        isTesting = true
        testStatus = L10n.t("正在测试连接...")
        Task {
            do {
                let msg = try await ModelSettingsManager.shared.testConnection(settings: settings)
                self.testStatus = msg
                self.isTesting = false
            } catch {
                self.testStatus = L10n.t("❌ %@", error.localizedDescription)
                self.isTesting = false
            }
        }
    }
    
    private func temperatureCategory(_ temp: Double) -> (badge: String, explanation: String, color: Color) {
        if temp <= 0.3 {
            return (
                badge: L10n.t("🎯 精准严谨 (推荐)"),
                explanation: L10n.t("确定性极高，严格遵守匹配规则与规划，最适合批量重命名、裁剪与格式转换等精准操作。"),
                color: .green
            )
        } else if temp <= 0.7 {
            return (
                badge: L10n.t("⚖️ 平衡模式"),
                explanation: L10n.t("兼顾逻辑严谨度与表达多样性，适合常规自然语言分析与意图推断。"),
                color: .blue
            )
        } else {
            return (
                badge: L10n.t("🎨 创意发散"),
                explanation: L10n.t("随机性高，容易产生多样化命名或发散结果，不建议在需要严密一致性的文件批处理中使用。"),
                color: .orange
            )
        }
    }
}
