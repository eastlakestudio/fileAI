# 文件魔法棒 AI File Assistant — 本周变更日志

**周期**：2026-08-21 ~ 2026-08-27
**版本**：v1.0.0 → v1.1.0

---

## 🚀 新功能

### 中英双语本地化
- 全量 600+ 条翻译表（`Localizable.xcstrings`），跟随系统语言自适应
- 设置中心新增「界面语言」选项：跟随系统 / 简体中文 / English，**切换即时生效**（Bundle swizzle），重启后恢复上次选择
- 任务状态、操作类型、技能分类、菜单、错误提示全量双语

### 云端技能市场（skills.sh 生态）
- 内置官方精选源：Anthropic / 飞书 (larksuite/cli) / Vercel / Microsoft / Superpowers
- GitHub 全站技能仓库搜索 + `owner/repo` 直达；SKILL.md 一键安装转本地技能
- 工程化网络层：git trees 单次列举 + codeload tarball 降级通道（不占 API 限额）+ 24h 磁盘缓存 + GITHUB_TOKEN 自动加持

### 性能优化（响应速度）
- **意图探测交由 CLI/LLM**（本地零规则）：CASUAL / TASK / QUESTION 三分类，闲聊秒回、提问直接回答
- **codebuddy 会话复用**（`-c` 续会话）：系统提示词与技能池仅首会话传输，后续只传用户输入
- 系统提示词静态块指纹缓存 + Tools Schema 紧凑化（体积约 -40%）
- 无目标文件不再拦截提问，走 Direct Answer

### 交互改进
- 全局呼出快捷键支持自定义（点击徽章录制，持久化；Esc 取消）
- 偏好页控件统一 150pt 等宽右对齐
- 沙箱目录授权：非沙箱构建自动隐藏；沙箱下「重新扫描」自动弹授权向导（HOME → ~/.npm-global → ~/.local 多目录集合）
- 技能库去分类化：平铺列表 + 名称/描述/格式搜索
- 任务看板筛选 Tab 计数徽章预留两位数宽度，不再换行跳动
- 聊天任务卡片背景与窗体分层增强
- 移除设置页「退出」按钮与 llama-cli 内置支持；恢复 accessory 模式（收起后 Dock 不留痕）

---

## 🐛 修复

- **zip 等归档不再包含父目录层级**：技能脚本 argv 改传相对 cwd 路径
- Finder 选中读取三通道架构：进程内 NSAppleScript（主）+ osascript AppleScript / JXA（备），TCC 未授权时 UI 引导去系统设置
- 沙箱 CLI 执行前 symlink 解析 + 授权作用域校验与明确报错指引
- Info.plist 补 `NSAppleEventsUsageDescription`（Apple Events 授权弹窗必需声明）
- `CLIModelClient` Swift 6 并发合规（ResumeLatch 原子门闩），清理全部编译警告
- DMG 制作挂载残留与公证校验语法修复

---

## 📦 发布与分发

- **v1.0.1 / v1.1.0**：Developer ID 签名 + Apple 公证（Notarized）+ Staple，Gatekeeper 无警告
- 一键发布脚本 `Scripts/release_dmg.sh`：构建 → 签名 → DMG → 公证 → Staple → GitHub Release
- 双语 README + 产品落地页（GitHub Pages：https://eastlakestudio.github.io/fileAI/ ）
- `PrivacyInfo.xcprivacy` 隐私清单（MAS 提审必需）
- **v1.1.0 起：取消 App 沙箱**，专注官网/Developer ID 分发（沙箱代码保留供未来 MAS 双轨）

---

## 🧪 质量

- 测试套件适配异步意图探测与新交互行为，除 2 个环境依赖用例外全部通过
- Mock 引擎补格式转换关键词命中

**下载**：[GitHub Releases](https://github.com/eastlakestudio/fileAI/releases) · [官网](https://eastlakestudio.github.io/fileAI/)
