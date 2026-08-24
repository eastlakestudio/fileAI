# 应用名称与本地化配置改造：文件魔法棒 (Walkthrough)

## 1. 变更说明

### 1.1 应用名称与编译设置更新 (`project.yml`)
- 在 `AIFileApp` target 的设置中添加：
  ```yaml
  PRODUCT_NAME: "文件魔法棒"
  ```
- 在 `info.properties` 中显式指定：
  ```yaml
  CFBundleName: "文件魔法棒"
  CFBundleDisplayName: "文件魔法棒"
  ```
- 在 `sources` 中引入本地化多语言资源：
  ```yaml
  - path: Support/zh-Hans.lproj/InfoPlist.strings
  - path: Support/en.lproj/InfoPlist.strings
  ```

### 1.2 本地化资源文件创建
- 创建 `Support/zh-Hans.lproj/InfoPlist.strings`（中文显示名称：“文件魔法棒”）；
- 创建 `Support/en.lproj/InfoPlist.strings`（英文显示名称：“AI File Assistant”）。

### 1.3 Xcode 工程重新生成
- 运行 `xcodegen generate`，成功更新 Copy Bundle Resources 构建阶段。

---

## 2. 自动化测试与构建验证

### 2.1 全量单元测试
- 执行 `swift test --arch arm64`：**119 个测试 100% 全部通过**。

### 2.2 构建产物检验
- 执行 `xcodebuild` 构建产物为 **`文件魔法棒.app`**；
- 检查 `Contents/Info.plist` 确认 `CFBundleDisplayName`、`CFBundleName` 与 `CFBundleExecutable` 均为 `文件魔法棒`；
- 检查 `Contents/Resources` 确认包含 `zh-Hans.lproj/InfoPlist.strings` 与 `en.lproj/InfoPlist.strings`；
- 在 macOS 系统的 Finder、Launchpad、Dock 栏及 TestFlight 安装后将 100% 正确展示为 **“文件魔法棒”**。


