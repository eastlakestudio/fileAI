# 清理历史遗留自创技能与修正 lark-cli 适配说明 (Walkthrough)

## 1. 问题根因
- 之前大模型在旧版提示词下曾自创并安装过一个 `lark_fetch_todo.md` 技能到用户本地技能库；
- 该技能中 AI 自创了错误的命令 `lark-cli message fetch --today`，而真实安装的飞书官方 `lark-cli` 架构为 `lark-cli im`、`lark-cli task` 与 `lark-cli calendar`，导致出现 `unknown command "message" for "lark-cli"` 退出码 2 报错。

## 2. 修复方案
1. **清理历史遗留瑕疵技能**：从用户技能库中彻底删除了旧版自创的 `lark_fetch_todo.md`；
2. **规范官方原子能力适配**：更新了系统预置的 `lark_fetch_messages` 脚本，全面对接官方 `lark-cli im +messages-search` / `lark-cli task`；
3. **单元测试与热重启**：87 项自动化测试全量通过，应用已热重启完成。
