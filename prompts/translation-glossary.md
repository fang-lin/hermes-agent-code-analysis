# 翻译术语词库（中 → 英）

本文件是 hermes-agent 源码分析文档**中译英的唯一术语真相源**。

## 怎么用

- **翻译前必读**：主线翻译每一篇前先通读本表，确保术语用固定译法。
- **遇到新术语先登记再用**：翻译中碰到表里没有的关键术语，**先把它加进本表**（连同选定的译法和理由），再在译文里使用。像写代码先定义再调用——绝不在没登记的情况下临时决定译法。
- **审核依据**：翻译审核 Agent 逐条对照本表检查译文，表里每个词在译文中必须用指定译法。这一项不靠语感，靠查表，所以结论可复现。
- **改动留痕**：本表纳入 git，任何术语译法的变更都通过 commit 记录，便于回溯「为什么这个词这么译」。

## 总规则（优先级高于下面的逐词表）

1. **代码标识符一律不译，原样保留**：函数名 `run_conversation()`、类名 `SessionDB`、文件路径与行号 `file_operations.py:1342`、配置键 `display.skin`、环境变量 `HERMES_TUI`、CLI 命令 `hermes cron create` —— 全部保持中文版里的原样，不翻译、不改大小写、不加空格。
2. **代码块、Mermaid 图、行号引用零改动**：译文里的 ``` 代码块、```mermaid 图、`file.py:行号` 必须和中文版逐字符一致，只翻译其中的中文「注释」和「图注文字」（图节点里的纯标识符不动）。
3. **数字保真**：所有数字（行数、次数、阈值、版本号、端口）原样照搬，不四舍五入、不改写。
4. **官方文档链接**：`https://hermes-agent.nousresearch.com/docs/...` 路径原样保留；链接的显示文字（如「延伸阅读」）译成英文。
5. **保持术语单复数/大小写一致**：见下表「说明」列的约定。

## 逐词表

> 初始化时（翻译 00 章过程中）逐条填入。每翻一篇，新出现的关键术语追加到此。

| 中文 | English | 说明 / 为什么这么译 |
|------|---------|---------------------|
| 智能体 / Agent | Agent | 首字母大写，指 Hermes 的 AIAgent；泛指「一个 agent」时小写 agent |
| 子 Agent | subagent | 一个词，不用 "sub-agent" / "child agent" |
| 工具 | tool | |
| 工具集 | toolset | 一个词，不用 "tool set" |
| 工具调用 | tool call | |
| 技能 | skill | |
| 钩子 | hook | |
| 网关 | gateway | 小写（除句首）；指 `gateway/` 模块 |
| 插件 | plugin | |
| 审批 | approval | 危险命令审批用 approval，不用 authorization |
| 凭证池 | credential pool | |
| 轨迹 | trajectory | 训练数据语境 |
| 看板 | Kanban | 首字母大写 |
| 守护进程 / 后台线程 | daemon thread | 不译成 "guard process"；区分「进程」daemon process |
| 派发器 | Dispatcher | Kanban 语境，首字母大写 |
| 运行模式 | run mode | |
| 交互模式 | interactive mode | |
| 单查询模式 | single-query mode | |
| 机器可读模式 | machine-readable mode | `--quiet` 那种 |
| 流式 / 流式投递 | streaming / stream delivery | |
| 上下文压缩 | context compression | |
| 提示缓存 | prompt caching | 保留英文 prompt caching 亦可，全程统一 |
| 回退链 / Fallback | fallback chain | |
| 重试与退避 | retry and backoff | |
| 终端后端 | terminal backend | |
| 沙箱 | sandbox | |
| 会话 | session | |
| 会话存储 | session storage | |
| 全文搜索 | full-text search | |
| 原子写入 | atomic write | |
| 声明式列协调 | declarative column reconciliation | schema 演化语境 |
| 车队效应 | convoy effect | SQLite 并发写语境 |
| 供应链硬化 | supply-chain hardening | |
| 语言服务器 | language server | LSP 语境 |
| 诊断 | diagnostic(s) | LSP 报的错误 |
| 语音模式 | voice mode | |
| 静音检测 | silence detection | |
| 模态状态机 | modal state machine | 经典 TUI 输入框语境 |
| 皮肤 | skin | |
| 破题段 | （文档结构词，不直译，按英文写作习惯处理开篇段） | |
| 使用指南 | Usage Guide | 章节小标题 |
| 架构与实现 | Architecture & Implementation | 章节小标题 |
| 常见场景 | Common Scenarios | |
| 排错指引 | Troubleshooting | |
| 设计决策 | Design Decisions | |
| 扩展点 | Extension Points | |
| 与其他章节的关系 | Relationship to Other Chapters | |
| 延伸阅读（官方文档） | Further Reading (Official Docs) | |
| 本章定位 | Scope | 定位块小标题 |
| 失败模式 | failure mode | 9 问之一 |
| 降级 | degrade / fall back | |

## 章节标题对照（文件名已固定，标题译法在此统一）

| 中文章节 | 英文文件名 | 英文标题 |
|----------|-----------|----------|
| 00 项目全景 | 00-project-overview.md | Project Overview |
| 01 基础设施层 | 01-infrastructure.md | Infrastructure Layer |
| 02 Agent 核心 | 02-agent-core.md | Agent Core |
| 03 工具系统 | 03-tool-system.md | Tool System |
| 04 技能系统 | 04-skill-system.md | Skill System |
| 05 网关层 | 05-gateway.md | Gateway Layer |
| 06 协议适配层 | 06-protocols.md | Protocol Adapters |
| 07 插件框架 | 07-plugin-framework.md | Plugin Framework |
| 08 内置插件 | 08-builtin-plugins.md | Built-in Plugins |
| 09 Kanban 系统 | 09-kanban.md | Kanban System |
| 10 交互界面与运行模式 | 10-interfaces-and-run-modes.md | Interfaces & Run Modes |
| 11 Cron 调度 | 11-cron-scheduling.md | Cron Scheduling |
| 12 批量运行与轨迹生成 | 12-batch-and-trajectories.md | Batch Running & Trajectory Generation |
| 13 工程实践 | 13-engineering-practices.md | Engineering Practices |

> 章节标题里那些「问题式」的副标题（如「让 Agent 在你不说话时也能干活」），按英文写作习惯意译，保留同样的「问题驱动」张力，不逐字直译。具体译法翻到该章时定，并登记回本表。
