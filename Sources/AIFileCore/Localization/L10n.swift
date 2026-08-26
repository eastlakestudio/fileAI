import Foundation

/// 全局本地化助手：中英文双语支持，根据系统语言自适应，并支持用户手动覆盖（运行时即时切换）。
/// 以中文字符串字面量作为 Key，运行时从 Localizable 表查找对应语言译文；
/// 缺失时回退显示 Key 本身（即中文），保证任何语言环境下界面始终可用。
public enum L10n {

    /// 单元测试环境检测：测试中固定返回 Key，避免宿主 App 语言影响字符串断言
    static let isTestEnvironment: Bool = NSClassFromString("XCTestCase") != nil

    // MARK: - 界面语言手动覆盖

    /// 界面语言选项
    public enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
        case system = ""            // 跟随系统
        case chinese = "zh-Hans"
        case english = "en"

        public var id: String { rawValue }

        /// 持久化键
        static let defaultsKey = "aifiles.interfaceLanguage"

        public static var current: InterfaceLanguage {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
            return InterfaceLanguage(rawValue: raw) ?? .system
        }

        /// 应用语言覆盖：写入 AppleLanguages，并通过 Bundle swizzle 让全 App（含 SwiftUI 字面量）即时生效
        public func apply() {
            let defaults = UserDefaults.standard
            defaults.set(rawValue, forKey: Self.defaultsKey)
            if self == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([rawValue], forKey: "AppleLanguages")
            }
            L10n.setLanguageOverride(self)
        }

        public var displayName: String {
            switch self {
            case .system: return L10n.t("跟随系统")
            case .chinese: return "简体中文"
            case .english: return "English"
            }
        }
    }

    // MARK: - 运行时语言切换（Bundle swizzle）

    /// 当前覆盖语言对应的子 Bundle（nil = 跟随系统）
    nonisolated(unsafe) private static var overrideBundle: Bundle? = nil
    nonisolated(unsafe) private static var swizzleInstalled = false

    /// 语言子 Bundle 解析：优先 App Bundle 资源目录；SPM 裸可执行调试构建则查可执行文件同级目录
    static func bundle(for language: InterfaceLanguage) -> Bundle? {
        let name = language.rawValue
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var bases: [URL] = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        // 裸可执行：Bundle.main.bundleURL 即二进制文件本身，补充其父目录
        let mainURL = Bundle.main.bundleURL
        if !mainURL.hasDirectoryPath {
            bases.append(mainURL.deletingLastPathComponent())
        }
        bases.append(exeDir)
        for base in bases {
            let candidate = base.appendingPathComponent("\(name).lproj")
            if FileManager.default.fileExists(atPath: candidate.path),
               let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }

    /// 设置运行时语言覆盖：安装 swizzle、刷新主 Bundle 本地化解析，并广播全局刷新通知
    public static func setLanguageOverride(_ language: InterfaceLanguage) {
        installSwizzleIfNeeded()
        if language == .system {
            overrideBundle = nil
        } else {
            overrideBundle = bundle(for: language)
        }
        NotificationCenter.default.post(name: .init("aifiles.languageDidChange"), object: nil)
    }

    /// 把 Bundle.main 动态替换为 LanguageOverrideBundle 子类，拦截全部 localizedString 查询
    private static func installSwizzleIfNeeded() {
        guard !swizzleInstalled else { return }
        swizzleInstalled = true
        object_setClass(Bundle.main, LanguageOverrideBundle.self)
    }

    /// 拦截主 Bundle 本地化查询的子类：有覆盖时重定向到覆盖语言的子 Bundle
    final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            if let override = L10n.overrideBundle {
                return override.localizedString(forKey: key, value: value, table: tableName)
            }
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }

    // MARK: - 文案查询

    /// 静态文案本地化（Key 为中文字面量）
    public static func t(_ key: String) -> String {
        if isTestEnvironment { return key }
        return NSLocalizedString(key, bundle: .main, comment: "")
    }

    /// 带参文案本地化：Key 中统一使用 %@ 占位符，调用方将任意类型插值先转为 String，
    /// 例如 `L10n.t("共找到 %@ 个文件", "\(count)")`，保证格式串与参数类型绝对安全。
    public static func t(_ key: String, _ args: String...) -> String {
        if isTestEnvironment { return replaceArgs(in: key, with: args) }
        return replaceArgs(in: NSLocalizedString(key, bundle: .main, comment: ""), with: args)
    }

    /// 用顺序参数替换 %@ 占位符（逐个替换，不使用 String(format:)，避免类型不匹配崩溃）
    private static func replaceArgs(in format: String, with args: [String]) -> String {
        var result = format
        for arg in args {
            if let range = result.range(of: "%@") {
                result.replaceSubrange(range, with: arg)
            } else {
                break
            }
        }
        return result
    }
}


