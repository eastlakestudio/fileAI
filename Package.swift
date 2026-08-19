// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AIFileAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AIFileCore", targets: ["AIFileCore"]),
        .library(name: "AIFileSkills", targets: ["AIFileSkills"]),
        .library(name: "AIFileAgent", targets: ["AIFileAgent"]),
        .library(name: "AIFileFinderIntegration", targets: ["AIFileFinderIntegration"]),
        .library(name: "AIFileUI", targets: ["AIFileUI"]),
        .executable(name: "AIFileApp", targets: ["AIFileApp"])
    ],
    dependencies: [
        // 保持核心零第三方依赖，纯 Swift 原生框架
    ],
    targets: [
        // 1. 核心层：数据模型、元数据提取、隐私拦截闸口、事务日志与安全执行
        .target(
            name: "AIFileCore",
            dependencies: [],
            path: "Sources/AIFileCore"
        ),
        
        // 2. Skill 技能层：图像处理、PDF处理、智能重命名等具体物理操作
        .target(
            name: "AIFileSkills",
            dependencies: ["AIFileCore"],
            path: "Sources/AIFileSkills"
        ),
        
        // 3. Agent 调度与 LLM 通信网关
        .target(
            name: "AIFileAgent",
            dependencies: ["AIFileCore", "AIFileSkills"],
            path: "Sources/AIFileAgent"
        ),
        
        // 4. 系统集成层：状态栏 NSStatusItem、全局快捷键、Finder 选中项捕获
        .target(
            name: "AIFileFinderIntegration",
            dependencies: ["AIFileCore"],
            path: "Sources/AIFileFinderIntegration"
        ),
        
        // 5. UI 交互层：SwiftUI 悬浮窗、Diff 审查面板、隐私授权弹窗
        .target(
            name: "AIFileUI",
            dependencies: ["AIFileCore", "AIFileSkills", "AIFileAgent", "AIFileFinderIntegration"],
            path: "Sources/AIFileUI"
        ),
        
        // 6. 可执行主程序入口
        .executableTarget(
            name: "AIFileApp",
            dependencies: ["AIFileUI"],
            path: "Sources/AIFileApp"
        ),
        
        // 测试 Targets
        .testTarget(
            name: "AIFileCoreTests",
            dependencies: ["AIFileCore"],
            path: "Tests/AIFileCoreTests"
        ),
        .testTarget(
            name: "AIFileSkillsTests",
            dependencies: ["AIFileSkills", "AIFileCore"],
            path: "Tests/AIFileSkillsTests"
        ),
        .testTarget(
            name: "AIFileAgentTests",
            dependencies: ["AIFileAgent", "AIFileCore", "AIFileSkills"],
            path: "Tests/AIFileAgentTests"
        )
    ]
)
