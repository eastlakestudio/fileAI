# 实施方案：飞书联系人姓名解析与任务卡片内嵌结果产出展示

## 需求背景
根据用户最新指令：
1. **飞书姓名适配打通**：通过 `lark-cli contact +search-user --query <姓名> --as user` 自动将“刘明华”或联系人姓名解析为 `open_id` 与 `p2p_chat_id`，并使用工作目录相对路径将文件真实发送给对方；
2. **完成结果文件内嵌任务卡片**：任务完成后，生成的产出结果文件直接在任务卡片内部以精致文件块展示，并带有「🔍 访达定位」与「↗️ 打开」操作；
3. **卡片背景色视觉突出**：任务卡片采用高质感微光渐变背景（进行中蓝光/完成态绿光/失败态红光）+ 高对比度边框与立体投影。

---

## 核心设计与改造方案

### 1. [MODIFY] `LarkCLIService.swift` 增加联系人姓名解析与工作目录文件发送
- **实现 `resolveUserOrChat(query:)`**：
  - 调用 `lark-cli contact +search-user --query <query> --as user`；
  - 自动从响应中提取首个联系人的 `open_id`、`p2p_chat_id` 与姓名；
- **优化 `executeAction`**：
  - 先自动解析联系人，获得 `chat_id` 或 `open_id`；
  - 将子进程执行目录 `currentDirectoryURL` 设置为目标文件的所在目录；
  - 参数传递 `--file <文件名>` 与 `--as user`；
  - 完整记录发送状态与响应。

### 2. [MODIFY] `ChatTaskCardView.swift` 内嵌产出结果列表与视觉突出重构
- **产出结果文件区块 (`completedResultFilesBlock`)**:
  - 当 `task.status == .completed` 时展示；
  - 列出每个生成的结果文件（格式专属图标、文件名、来源说明、大小）；
  - 每项右侧配备 `🔍 访达定位` 和 `↗️ 打开` 快捷按钮；
- **背景与边框视觉突出**:
  - 采用微光渐变与高对比度状态描边（`statusColor.opacity(0.4)`），搭配柔和立体阴影，在聊天流中层次分明。

---

## 验证计划
1. **单元测试**: 编写 `LarkUserResolutionTests.swift` 验证联系人姓名查询解析与卡片产出文件列表提取。
2. **测试套件运行**: `swift test` 确保 100% 单元测试通过。
3. **真实调用验证**: 重新编译运行 `AIFileApp`，发送「通过飞书发给刘明华」，验证自动检索刘明华账号 -> 成功调用飞书 CLI 发送文件 -> 任务卡片内部展示生成的产出结果与定位按钮。
