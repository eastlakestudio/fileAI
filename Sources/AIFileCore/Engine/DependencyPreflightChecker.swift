import Foundation

/// 依赖环境预检结果
public struct PreflightCheckResult: Sendable {
    public let isReady: Bool
    public let missingPackages: [String]
    public let autoInstalledPackages: [String]
    public let errorMessage: String?
    
    public init(
        isReady: Bool,
        missingPackages: [String] = [],
        autoInstalledPackages: [String] = [],
        errorMessage: String? = nil
    ) {
        self.isReady = isReady
        self.missingPackages = missingPackages
        self.autoInstalledPackages = autoInstalledPackages
        self.errorMessage = errorMessage
    }
}

/// 负责在脚本执行前进行依赖包与运行环境就绪检查的通用引擎
public final class DependencyPreflightChecker: Sendable {
    public static let shared = DependencyPreflightChecker()
    
    public init() {}
    
    /// Python 标准内置库清单（无需安装）
    public static let pythonStandardLibraries: Set<String> = [
        "os", "sys", "re", "math", "json", "time", "datetime", "pathlib", "shutil",
        "glob", "subprocess", "urllib", "hashlib", "csv", "io", "collections",
        "itertools", "typing", "uuid", "base64", "tempfile", "random", "zipfile",
        "tarfile", "threading", "multiprocessing", "functools", "dataclasses",
        "argparse", "copy", "logging", "socket", "http", "email", "xml", "html",
        "platform", "stat", "struct", "unittest", "sqlite3", "ctypes", "enum",
        "traceback", "inspect", "string", "warnings", "queue", "operator", "decimal",
        "fractions", "codecs", "secrets", "zlib", "gzip", "bz2", "lzma", "signal"
    ]
    
    /// Python 模块导入名称到 PyPI 真实包名的映射字典
    public static let packageAliases: [String: String] = [
        "PIL": "pillow",
        "cv2": "opencv-python",
        "bs4": "beautifulsoup4",
        "docx": "python-docx",
        "pptx": "python-pptx",
        "yaml": "pyyaml",
        "fitz": "PyMuPDF",
        "sklearn": "scikit-learn",
        "serial": "pyserial",
        "jwt": "pyjwt",
        "dateutil": "python-dateutil",
        "pydub": "pydub",
        "mutagen": "mutagen",
        "openpyxl": "openpyxl",
        "pandas": "pandas",
        "numpy": "numpy",
        "pdfplumber": "pdfplumber",
        "requests": "requests",
        "seaborn": "seaborn",
        "matplotlib": "matplotlib",
        "moviepy": "moviepy"
    ]
    
    /// 从 Python 脚本源码中智能提取所需引用的第三方依赖包清单
    public func extractPythonDependencies(script: String) -> [String] {
        var dependencies = Set<String>()
        let lines = script.components(separatedBy: "\n")
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // 忽略注释行与空行
            if line.hasPrefix("#") || line.isEmpty {
                continue
            }
            
            // 匹配 "import xxx" 或 "import xxx, yyy"
            if line.hasPrefix("import ") {
                let rest = line.dropFirst("import ".count)
                let parts = rest.components(separatedBy: ",")
                for part in parts {
                    let token = part.trimmingCharacters(in: .whitespaces)
                    let rootModule = token.components(separatedBy: " ").first?.components(separatedBy: ".").first ?? ""
                    if !rootModule.isEmpty && !Self.pythonStandardLibraries.contains(rootModule) {
                        let pkgName = Self.packageAliases[rootModule] ?? rootModule
                        dependencies.insert(pkgName)
                    }
                }
            }
            // 匹配 "from xxx import yyy" 或 "from xxx.sub import yyy"
            else if line.hasPrefix("from ") {
                let rest = line.dropFirst("from ".count)
                if let importRange = rest.range(of: " import ") {
                    let modulePart = String(rest[..<importRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let rootModule = modulePart.components(separatedBy: ".").first ?? ""
                    if !rootModule.isEmpty && !Self.pythonStandardLibraries.contains(rootModule) {
                        let pkgName = Self.packageAliases[rootModule] ?? rootModule
                        dependencies.insert(pkgName)
                    }
                }
            }
        }
        
        return Array(dependencies).sorted()
    }
    
    /// 探测指定 Python 模块是否在本机环境中安装可用
    public func isPythonModuleAvailable(moduleOrPackage: String, pythonPath: String) -> Bool {
        // 反查用于 import 的模块名称
        var importName = moduleOrPackage
        for (mod, pkg) in Self.packageAliases where pkg.lowercased() == moduleOrPackage.lowercased() {
            importName = mod
            break
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import \(importName)"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// 尝试通过 pip 静默自动安装缺失的依赖包
    public func autoInstallPackages(packages: [String], pythonPath: String) -> Bool {
        guard !packages.isEmpty else { return true }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        var args = ["-m", "pip", "install", "--quiet", "--disable-pip-version-check"]
        args.append(contentsOf: packages)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// 执行全套依赖与运行环境就绪检查（支持自动安装与智能修复提示）
    public func ensureDependencies(
        script: String,
        engine: ScriptEngineType,
        pythonPath: String
    ) async -> PreflightCheckResult {
        // 目前仅对 Python 脚本执行深度第三方库分析
        guard engine == .python3 else {
            return PreflightCheckResult(isReady: true)
        }
        
        let requiredPackages = extractPythonDependencies(script: script)
        guard !requiredPackages.isEmpty else {
            return PreflightCheckResult(isReady: true)
        }
        
        var missing: [String] = []
        for pkg in requiredPackages {
            if !isPythonModuleAvailable(moduleOrPackage: pkg, pythonPath: pythonPath) {
                missing.append(pkg)
            }
        }
        
        // 全部依赖已就绪
        if missing.isEmpty {
            return PreflightCheckResult(isReady: true)
        }
        
        // 尝试通过 pip 自动安装缺失包
        let installOk = autoInstallPackages(packages: missing, pythonPath: pythonPath)
        if installOk {
            return PreflightCheckResult(
                isReady: true,
                autoInstalledPackages: missing
            )
        }
        
        // 自动安装失败，生成清晰的指引文案
        let packagesStr = missing.joined(separator: " ")
        let errorMsg = """
        ⚠️ 技能执行依赖的 Python 库未就绪: [\(missing.joined(separator: ", "))]
        系统尝试自动安装未成功，请在终端手动执行以下命令进行安装：
        pip3 install \(packagesStr)
        """
        
        return PreflightCheckResult(
            isReady: false,
            missingPackages: missing,
            errorMessage: errorMsg
        )
    }
}
