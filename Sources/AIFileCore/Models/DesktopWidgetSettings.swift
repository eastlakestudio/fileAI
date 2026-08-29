import Foundation
import CoreGraphics

/// 桌面小组件展现形态
public enum WidgetPresentationMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 桌面小组件卡片态 (标准桌面小组件形态，带目标文件与自然语言输入卡片)
    case widgetCard = "widgetCard"
    /// 全功能大窗 (完整多轮对话流、文件列表与高级设置)
    case fullWindow = "fullWindow"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .widgetCard:
            return "桌面卡片"
        case .fullWindow:
            return "标准大窗"
        }
    }
    
    public var iconName: String {
        switch self {
        case .widgetCard:
            return "rectangle.dock"
        case .fullWindow:
            return "macwindow"
        }
    }
}

/// 桌面小组件窗口层级
public enum WidgetLevelMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 始终置顶层 (悬浮于所有普通窗口之上，随手可用)
    case floating = "floating"
    /// 桌面壁纸层 (贴在壁纸之上，切换其他应用时不遮挡工作内容)
    case desktopLevel = "desktopLevel"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .floating:
            return "始终置顶"
        case .desktopLevel:
            return "贴合桌面"
        }
    }
    
    public var iconName: String {
        switch self {
        case .floating:
            return "square.stack.3d.up.fill"
        case .desktopLevel:
            return "display"
        }
    }
}

/// 桌面小组件配置与持久化存储管理
public struct DesktopWidgetSettings: Codable, Sendable, Equatable {
    /// macOS 原生中型桌面小组件标准宽度 (Apple HIG: 364 pt)
    public static let standardWidgetWidth: CGFloat = 364
    /// 桌面小组件最小高度
    public static let minWidgetHeight: CGFloat = 160
    /// 桌面小组件标准高度
    public static let standardWidgetHeight: CGFloat = 205
    
    public var presentationMode: WidgetPresentationMode
    public var levelMode: WidgetLevelMode
    public var isSnapToEdgeEnabled: Bool
    public var lastSavedOriginX: Double?
    public var lastSavedOriginY: Double?
    
    public init(
        presentationMode: WidgetPresentationMode = .widgetCard,
        levelMode: WidgetLevelMode = .floating,
        isSnapToEdgeEnabled: Bool = true,
        lastSavedOriginX: Double? = nil,
        lastSavedOriginY: Double? = nil
    ) {
        self.presentationMode = presentationMode
        self.levelMode = levelMode
        self.isSnapToEdgeEnabled = isSnapToEdgeEnabled
        self.lastSavedOriginX = lastSavedOriginX
        self.lastSavedOriginY = lastSavedOriginY
    }
    
    private static let userDefaultsKey = "com.eastlakestudio.aifiles.desktopWidgetSettings"
    
    /// 从 UserDefaults 加载小组件配置
    public static func load() -> DesktopWidgetSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(DesktopWidgetSettings.self, from: data) else {
            return DesktopWidgetSettings()
        }
        return settings
    }
    
    /// 持久化小组件配置到 UserDefaults
    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
