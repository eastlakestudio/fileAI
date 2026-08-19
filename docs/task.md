# 任务追踪清单 (Task List) - Mac AI Finder 自动化文件工具

## 进阶功能与体验重构迭代 (当前进行中 🚀)
- [ ] **1. 窗体无缝液态毛玻璃与布局优化 (修复顶部留白)**
  - [ ] 优化 `NSPanel` 样式，消除顶部无意义空白，实现极致 Liquid Glass 视觉
  - [ ] 添加顶部精简工具栏（面包屑导航、视图切换、设置、任务看板）
- [ ] **2. 路径树状视图与手动文件拾取**
  - [ ] 增加共同祖先父目录面包屑解析
  - [ ] 实现「平铺列表 / 路径目录树 (`FileTreeView`)」双视图模式
  - [ ] 增加手动「选择文件/目录」与「最近目录」快捷入口
- [ ] **3. 智能 Skill 动态感知与过滤推荐**
  - [ ] 实现 `SmartSkillSuggester`：根据当前选中的文件类型动态推荐高匹配度 Skill 胶囊
  - [ ] 针对不匹配意图提供智能引导与建议
- [ ] **4. 模型配置中心 (`ModelSettingsView`)**
  - [ ] 支持 DeepSeek / OpenAI / Claude / 本地 MLX & Ollama 多 Provider 切换
  - [ ] API Key、Base URL、Model Name 配置与安全存储
  - [ ] 一键连通性测试 (Test Connection)
- [ ] **5. 任务执行跟踪与报告系统 (Task Board: Plan & Walkthrough)**
  - [ ] 设计 `TaskExecutionRecord` 数据结构（包含 Task ID, 状态, Plan 详情, Walkthrough 执行报告）
  - [ ] 构建任务面板 UI（「进行中」与「已完成」双 Tab）
  - [ ] 支持点击历史任务查看详细 Plan & Walkthrough，并可针对该任务一键 Undo 撤销
- [ ] **6. 单元测试与全量验证**
  - [ ] 编写智能推荐器与任务管理器 Unit Tests
  - [ ] 重新编译并在后台运行

---

## 阶段一：原型与核心技术验证 (MVP) [已完成 ✅]
- [x] 搭建原生 Swift 6 模块化架构工程
- [x] 状态栏常驻、拖拽接收与全局快捷键 (⌥Space)
- [x] 隐私优先元数据过滤与内容外发拦截闸口
- [x] 5 大基础核心 Skills (改尺寸, 格式转换, 转PDF, PDF合并拆分, 批量重命名)
- [x] Visual Diff 审查面板与 ⌘Z 撤销事务
- [x] 全量 11 项单元测试通过 (0 failures)
