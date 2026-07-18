# 翻译术语词库（中 → 英）

本文件是 hermes-agent 源码分析文档**中译英的唯一术语真相源**。

## 怎么用

- **翻译前必读**：主线翻译每一篇前先通读本表，确保术语用固定译法。
- **遇到新术语先登记再用**：翻译中碰到表里没有的关键术语，**先把它加进本表**（连同选定的译法和理由），再在译文里使用。像写代码先定义再调用——绝不在没登记的情况下临时决定译法。
- **技术术语的译法必须回 codebase 验证，不靠中文词面臆造**：凡是「对应某个 hermes 概念/机制」的术语（如 tool call、context compression、daemon thread、approval），登记前先 `grep` 源码和官方文档，用 hermes **实际高频使用的那个词**，并在「说明」列写明依据（如「源码 tool_call 195 次 / tool_use 29 次」）。中文同一个词可能对应源码里两个不同概念（如「审批」= approval 危险命令审批 / authorization 用户授权），必须拆开。这是本表「可查、可复现」的根基。
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
| 工具调用 | tool call | 用 tool call 不用 tool use——hermes 源码 `tool_call` 195 次/`tool_use` 29 次、官方文档 tool call 216/tool use 24，压倒性用 tool call（虽基于 Anthropic API，但 hermes 自己的命名是 tool call） |
| 技能 | skill | |
| 钩子 | hook | |
| 网关 | gateway | 小写（除句首）；指 `gateway/` 模块 |
| 插件 | plugin | |
| 审批（危险命令） | approval | 危险命令审批：`approval_callback`/`approval_mode`。**与下面的「用户授权」是两个概念** |
| 用户授权（谁能跟 bot 对话） | user authorization | gateway 层：`_is_user_authorized`、allowlist/DM pairing。**不要和 approval 混译** |
| 凭证池 | credential pool | |
| 轨迹 | trajectory | 训练数据语境 |
| 看板 | Kanban | 首字母大写 |
| 后台线程 / daemon 线程 | daemon thread | `threading.Thread(daemon=True)`（全仓 157 处）：CLI 的 Agent 调用、MCP 事件循环、技能 review、缓存清理等。**不译成 daemon process** |
| 守护进程 | daemon process / daemon | 独立 OS 进程：`hermes kanban daemon`、systemd service（`hermes-kanban-dispatcher.service`）；02 章 LSP「避免启动守护进程」也指进程。**与 daemon thread 是两回事** |
| 派发器 | Dispatcher | Kanban 语境，首字母大写 |
| 运行模式 | run mode | |
| 交互模式 | interactive mode | |
| 单查询模式 | single-query mode | |
| 机器可读模式 | machine-readable mode | `--quiet` 那种 |
| 流式 / 流式投递 | streaming / streaming delivery | streaming delivery 比 stream delivery 顺口 |
| 上下文压缩 | context compression | 用 compression 不用 compaction——hermes 源码 compress 653 次/compaction 21 次、官方文档 compression 206/compaction 15，压倒性用 compression |
| 提示缓存 | prompt caching | 保留英文 prompt caching 亦可，全程统一 |
| 回退链 / Fallback | fallback chain | |
| 重试与退避 | retry and backoff | |
| 终端后端 | terminal backend | 配置项语境（`terminal.backend`） |
| 执行后端 | execution backend | `tools/environments/` 的 7 种运行时（local/docker/ssh/daytona/singularity/modal…），接口类 `BaseEnvironment`；官方文档 execution backend / execution environment 混用，统一取 execution backend。与「终端后端」是同一物的不同视角，正文按中文原词对应译（终端后端→terminal backend、执行后端→execution backend） |
| 沙箱 | sandbox | |
| 会话 | session | |
| 会话存储 | session storage | |
| 原子写入 | atomic write | 泛指概念用 atomic write；具体函数名 `atomic_json_write`/`atomic_yaml_write`/`atomic_replace`/`atomic_roundtrip_yaml_update` 是标识符，原样保留（无 `atomic_write` 这个函数） |
| 全文搜索 | full-text search | 叙述用 full-text search；`FTS5`/`messages_fts`/`search_messages` 是标识符，原样保留 |
| 声明式列协调 | declarative column reconciliation | schema 演化语境 |
| 车队效应 | convoy effect | SQLite 并发写语境 |
| 供应链硬化 | supply-chain hardening | |
| 语言服务器 | language server | LSP 语境 |
| 诊断 | diagnostic(s) | LSP 报的错误 |
| 语音模式 | voice mode | |
| 静音检测 | silence detection | |
| 模态状态机 | modal state machine | 经典 TUI 输入框语境 |
| 皮肤 | skin | |
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
| 降级 | degrade / graceful degradation | 服务质量下降。**不用 fall back**——那套词留给「回退」，避免与 fallback chain 串味（降级≠回退：降级是质量下降，回退是切到备用路径） |
| 自改进 | self-improving | 项目定位词，源 `pyproject.toml:11` "The self-improving AI agent"，原样用 |
| 智能体框架 | agent framework | |
| 桌面应用 / 桌面客户端 | desktop app / desktop client | `apps/desktop`，Electron；与章节标题 Desktop App 一致 |
| 平台大迁移 / 平台迁移 | platform migration | v0.15-v0.18 主流平台从 gateway 内建搬进 `plugins/platforms/` |
| 上帝文件 | god-file | 源码 commit 自称 "god-file decomposition campaign"，保留 god-file 连字符写法 |
| 上帝文件分解 | god-file decomposition | 同上，用源码原短语 |
| 延迟加载 / 延迟加载器 | deferred loading / deferred loader | 平台插件语境，源码 `LoadedPlugin.deferred`/`platform_registry` 用 deferred（非 lazy——lazy 留给 Lazy Import 依赖懒加载） |
| 记忆双注入 | memory dual-injection | 00 章：内置快照入系统提示 + 外部检索入用户消息 |
| 中断传播 | interrupt propagation | `agent.interrupt()` 多层级递归 |
| 破题段 / 破题 | opening | 文档开篇段，按英文习惯处理，不直译 |
| 消息网关 | message gateway | 泛指时 message gateway；指模块用 gateway |
| 虚拟 Provider | virtual provider | MoA 语境，`moa://local` |
| 多模型聚合 / MoA | Mixture of Agents (MoA) | 首次出现给全称 + 缩写，之后用 MoA；源码/官方文档一致 |
| 工具网关 / Tool Gateway | Tool Gateway（专名大写）/ tool gateway（泛指小写） | 官方产品名，官方文档 `index.mdx:91` 大写作专名（"four Tool Gateway tools"）；转述性描述（如 registry 自述"捆绑工具网关"）用小写 tool gateway |
| 控制平面 | control plane | hermes_cli 的定位——不参与对话但决定对话环境 |
| 托管作用域 | managed scope | `managed_scope.py`，`/etc/hermes/` 企业管控层，按叶键覆盖 |
| 粘性文件 | sticky file | `~/.hermes/active_profile`，`hermes profile use` 的持久化 |
| 优雅重启 / drain | graceful restart / drain | 网关 SIGUSR1 drain 在途会话；drain 保留原词 |
| 凭证 | credential | 与 credential pool 一致 |
| 设备码流程 | device code flow | OAuth，RFC 8628 |
| 断路器 | circuit breaker | Kanban `consecutive_failures` + `max_retries` |
| 乐观锁 | optimistic locking | Kanban 任务认领 |
| 别名 | alias | `/model` 别名解析，`resolve_alias()` |
| 快速启动 | fast launch / fast start | Termux 三级加速 |
| 配置项 | config key / setting | `DEFAULT_CONFIG` 的键 |
| 优先级链 | precedence chain | provider 解析等多级链路 |
| 深度合并 | deep merge | `_deep_merge()` 配置合并 |
| 对话协调器 | conversation orchestrator | AIAgent 的定位 |
| 参考模型 / 参谋 | reference model / advisor | MoA，源码 `_REFERENCE_SYSTEM_PROMPT` 用 advisor |
| 聚合模型 / 聚合器 | aggregator | MoA，源码 "the aggregator is the acting model" |
| 扇出 | fan-out | MoA 参考扇出（fan out to reference models） |
| 预飞压缩 | pre-flight compression | 进循环前的压缩闸门 |
| 发前压力复查 | pre-call pressure recheck | 每次 API 调用前的第二道压缩闸门 |
| 序幕 / 收尾 | prologue / epilogue | turn_context 序幕 / turn_finalizer 收尾 |
| 心跳 | heartbeat | 子 Agent 活动信号 |
| 计费 / 账单 | billing | credits_tracker/billing_view |
| 可观测性 | observability | display 实时 / insights 事后 |
| 退款 | refund | IterationBudget.refund() |
| 预算 | budget | IterationBudget |
| 抖动 | jitter | 带抖动的指数退避 |
| 崩溃恢复 | crash recovery | turn_context 持久化 |
| 记忆预取 | memory prefetch | 外部 memory provider 检索 |
| 消毒 / 修复 | sanitize / repair | `_sanitize_api_messages` |
| entitlement 检测 | entitlement check | 403 检测：缺订阅 vs token 过期，保留 entitlement 原词 |

## 章节标题对照（文件名已固定，标题译法在此统一）

| 中文章节 | 英文文件名 | 英文标题 |
|----------|-----------|----------|
| 00 项目全景 | 00-project-overview.md | Project Overview |
| 01 基础设施层 | 01-infrastructure.md | Infrastructure Layer |
| 02 Agent 核心 | 02-agent-core.md | Agent Core |
| 03 工具系统 | 03-tool-system.md | Tool System |
| 04 技能系统 | 04-skill-system.md | Skill System |
| 05 网关层 | 05-gateway.md | Gateway Layer |
| 06 协议适配层 | 06-protocols.md | Protocol Adaptation Layer |
| 07 插件框架 | 07-plugin-framework.md | Plugin Framework |
| 08 内置插件 | 08-builtin-plugins.md | Built-in Plugins |
| 09 Kanban 系统 | 09-kanban.md | Kanban System |
| 10 交互界面与运行模式 | 10-interfaces-and-run-modes.md | Interfaces & Run Modes |
| 11 Cron 调度 | 11-cron-scheduling.md | Cron Scheduling |
| 12 批量运行与轨迹生成 | 12-batch-and-trajectories.md | Batch Running & Trajectory Generation |
| 13 工程实践 | 13-engineering-practices.md | Engineering Practices |
| 14 桌面应用 | 14-desktop-app.md | Desktop App |

> 章节标题里那些「问题式」的副标题（如「让 Agent 在你不说话时也能干活」），按英文写作习惯意译，保留同样的「问题驱动」张力，不逐字直译。具体译法翻到该章时定，并登记回本表。
