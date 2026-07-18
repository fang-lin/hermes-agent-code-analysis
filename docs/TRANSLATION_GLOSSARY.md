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
6. **代码块里的「自然语言字符串值」可译**：CLI 示例里作为演示内容的自然语言字符串值（如 `--title "实现用户登录 API"` 的标题、`--summary`/`body=` 的正文）译成英文，方便英文读者理解——这不违反规则 2，因为改的是给人读的示例内容，不是命令结构、标识符、flag 名。但字符串若本身是标识符/slug/枚举值（如 `--assignee backend-dev`、`board=default`），保持原样不译。
7. **「N 件套」译成集合名词**：中文口语「三件套/四件套」指一组固定钩子/组件时，译成 trio/quartet 等集合名词（看板三件套→Kanban trio、会话四件套→session quartet），而非 "three-piece set"。

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
| 看板（系统/专名） | Kanban | 首字母大写；指 Kanban 系统本身（Kanban System、Kanban 调度器） |
| 看板（具体板实例） | board | 指某一块具体的板（default board、board slug）；源码本身用 `board=`/`boards/`/`HERMES_KANBAN_BOARD`/`kanban boards switch`，跟随源码小写 |
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
| 抖动（退避算法义） | jitter | 带抖动的指数退避 |
| 抖动（网络不稳定义） | blip / flakiness | 网络/DNS 瞬时不稳定，非退避 jitter（同字两义，勿混） |
| 崩溃恢复 | crash recovery | turn_context 持久化 |
| 记忆预取 | memory prefetch | 外部 memory provider 检索 |
| 消毒 / 修复 | sanitize / repair | `_sanitize_api_messages` |
| entitlement 检测 | entitlement check | 403 检测：缺订阅 vs token 过期，保留 entitlement 原词 |
| 命令审批 | command approval | approval.py 危险命令审批 |
| 写入审批 | write approval | write_approval.py 记忆/技能写入 |
| 硬底线 / HARDLINE | hardline | **专指**命令审批的 HARDLINE_PATTERNS（--yolo 也绕不过，03 章）。其他语境下泛用的"硬底线"（如 04 章技能保护名单 PROTECTED_BUILTIN_SKILLS）用 "hard bottom line"，非本术语 |
| 防线 | line of defense | 安全"不止三道防线" |
| 渐进式（工具）披露 | progressive (tool) disclosure | tool_search |
| 威胁模式库 | threat-pattern library | threat_patterns.py |
| 提示注入 | prompt injection | promptware/数据外渗语境 |
| 路径穿越 / 路径遍历 | path traversal | path_security |
| 内容级威胁 | content-level threat | Tirith 扫描 |
| 结果大小治理 | result-size governance | budget_config |
| 后台委托 | background delegation | delegate_task(background=true) |
| 桌面控制 | desktop control | computer_use |
| 自注册 | self-registration | registry.register() |
| 净化 / 消毒 | sanitize | `_sanitize_tool_error` |
| 一等公民 | first-class citizen | MCP 工具与内置工具同接口 |
| 策展人 / Curator | Curator | agent/curator.py 技能库策展，首字母大写 |
| 遥测 | telemetry | 技能使用遥测 .usage.json |
| 就绪状态 | readiness status | AVAILABLE/SETUP_NEEDED/UNSUPPORTED |
| 陈旧 | stale | 技能生命周期 active→stale→archived |
| 归档 | archive / archived | .archive/ 目录，可恢复 |
| 抑制名单 | suppression list | 防 update 重装已归档技能 |
| 前置条件 | prerequisite | 技能 required_* 声明 |
| 来源追踪 | provenance tracking | skill_provenance ContextVar 前台/后台 |
| 条件激活 | conditional activation | metadata.hermes conditions |
| 操作手册 | playbook / operating manual | SKILL.md 是给模型的操作手册 |
| 多源聚合器 | multi-source aggregator | Skills Hub |
| 信任级 | trust level / trust tier | builtin > trusted > community |
| 摘要重放 | digest replay | review 异模型场景 _digest_history |
| 全量重放 | full replay | review 同模型场景 |
| 适配器 | adapter | BasePlatformAdapter |
| 平台注册表 | platform registry | gateway/platform_registry.py |
| 能力宣告 | capability declaration | 适配器 supports_* 属性 |
| 草稿流式 | draft streaming | Telegram DM 原生草稿预览 |
| 编辑节奏 | edit cadence | 流式 edit_message 触发节奏 |
| dead-target | dead target | DeadTargetRegistry，保留原词 |
| 静默叙述过滤 | silence-narration filtering | 幻觉"我保持安静"噪声 |
| 投递路由 | delivery router | Delivery Router |
| 中继 | relay | Team Gateway relay 子包 |
| 会话恢复 / 续接 | session recovery / resumption | resume_pending |
| 优雅关闭 | graceful shutdown | stop() SIGTERM |
| 熔断器 | circuit breaker | 平台重连（与 Kanban circuit breaker 同词） |
| 拦截型命令 | intercept command | /stop /new 忙碌路径立即处理 |
| 规整化 | canonicalize / normalize | WhatsApp JID/LID 规整化 |
| 消息容器 | message envelope | MessageEvent |
| 富媒体 | rich media | 图片/语音/视频 |
| 协议适配 | protocol adaptation | ACP/MCP，章节标题 Protocol Adaptation Layer |
| 编辑审批 | edit approval | ACP edit_approval.py |
| 会话血统追踪 | session provenance tracking | acp_adapter/provenance.py |
| 血统 / 血统链 | provenance / provenance chain | 压缩换头的会话 ID 链 |
| 敏感路径 | sensitive path | .env/.ssh 始终询问 |
| 换头 | head rotation | 压缩后开新 session head |
| 前身项目 | predecessor project | OpenClaw |
| 出站 / 入站 | outbound / inbound | messages_send 出站通路 |
| 事件桥 | event bridge | EventBridge |
| 游标 | cursor | events_poll after_cursor |
| 中间件 | middleware | register_middleware，与钩子并列的扩展面 |
| 洋葱模型 | onion model | 执行中间件 next_call 包裹 |
| 载荷 | payload | 请求中间件改写 request/args |
| 门控 | gate / gating | fail-closed 门控 |
| 互斥（插件） | exclusive | kind=exclusive 记忆/上下文引擎 |
| 遮蔽 | shadowing | 跨工具集同名注册默认拒绝 |
| 生命周期钩子 | lifecycle hook | VALID_HOOKS 23 种 |
| 白名单 | allowlist | plugins.enabled（与黑名单 denylist 对） |
| 阻断 | block | pre_tool_call block 动作 |
| 升级（到人工审批） | escalate | pre_tool_call approve→人工审批门 |
| 伪 context | pseudo-context | _ProviderCollector no-op stub |
| 开销感知 | cost-aware | Honcho cadence 退避 |
| 声明式插件 | declarative plugin | model-provider 只声明元数据 |
| 双模式 | dual-mode | nemo_relay observe_only/adaptive |
| 一次性定时器 | one-shot timer | chronos 定时器 |
| 再武装 | re-arm | chronos 回调后再武装 |
| sink | sink | teams_pipeline 写入目标，保留原词 |
| 幂等键 | idempotency key | sink:meeting_id |
| 防呆设计 | foolproofing / guardrail | langfuse key 前缀校验 |
| 认证方案 | auth method | dashboard_auth 四方案 |
| 认证门 | auth gate | should_require_auth |
| 卫星模块 / 卫星文件 | satellite module / satellite file | 平台插件辅助文件 |
| 内建军团 | built-in legion | 平台迁移前的内建适配器 |
| 主战场 | main battleground | 迁移主战场（意译，避免黑话直译） |
| 编排者 | orchestrator | Kanban 拆分任务的 Agent |
| 认领 | claim | claim_task() CAS 认领 |
| 幻觉验证 / 幻觉扫描 | hallucination validation / scan | created_cards 校验、散文 t_<hex> 扫描 |
| 类型化阻塞 | typed blocking | VALID_BLOCK_KINDS 四种 kind |
| 解锁循环熔断 | unblock-loop circuit breaker | block_recurrences 达上限升 triage |
| 多租户 | multi-tenant | HERMES_TENANT 命名空间 |
| 僵尸 / 僵死 Worker | zombie / stale worker | 无心跳/崩溃 Worker 检测 |
| 收割（子进程） | reap | os.waitpid 收割僵尸子进程 |
| 交接 | hand off | Worker 交出结果 |
| 目标循环 / Ralph 循环 | goal loop / Ralph loop | goal_mode Worker |
| 抖动防抖（respawn） | respawn guard | check_respawn_guard 四规则 |
| 假阻塞 / 真阻塞 | pseudo-block / real block | dependency vs needs_input 等 |
| 工作区 | workspace | scratch/dir/worktree |
| 三种面孔 / 六种跑法 | three faces / six ways to run | 10 章标题，意译保留张力 |
| 渲染管线 | rendering pipeline | _render_final_assistant_content |
| 界面分流 | interface routing | cmd_chat 分流三界面 |
| 模态状态机 | modal state machine | 已在词库；输入框语境 |
| 幻觉过滤 | hallucination filtering | Whisper 幻觉短语过滤 |
| panic hook | panic hook | tui_gateway 崩溃取证，保留原词 |
| 崩溃取证 | crash forensics | tui_gateway_crash.log |
| 瘦客户端 | thin client | TUI 附着已有 gateway |
| 目标延续 | goal continuation | _maybe_continue_goal_after_turn |
| 遮罩 / 浮层 | overlay | approval/clarify/sudo 遮罩、模态浮层 |
| 收回控制权 | reclaim control | 打断后 join |
| 兜底 | fallback / safety net | 失败模式兜底 |
| 双鉴权 | dual authentication | loopback token vs OAuth cookie |
| 安全模式库 | security-pattern library | `plugins/security-guidance/`；与「威胁模式库 threat-pattern library」是不同概念（安全≠威胁），勿混 |
| 会话四件套 | session quartet | `on_session_start/end/finalize/reset` 四个钩子；见总规则 7 |
| 看门狗 | watchdog | 监控脚本「没事就不出声」 |
| 宽限窗口 | grace window | 宕机重启后错过任务的容忍窗口 |
| 唤醒门控 | wake gate | pre-check 脚本决定要不要唤醒 LLM |
| 至多执行一次 | at-most-once | 先推进 next_run 再执行 |
| 先推进再执行 | advance-then-execute | tick 顺序：先推进 next_run_at 再跑任务 |
| 静默快进 | silent fast-forward | 超出 grace window 的任务不补跑、直接快进到下个周期 |
| 沉默信号 / [SILENT] | silence signal | `[SILENT]` 抑制投递；保留原标记不译 |
| 活性超时 / 基于活性的超时 | liveness-based timeout | 按「无活动时长」而非总运行时长判超时 |
| 心跳自检 | heartbeat self-check | ticker 每轮写心跳文件供诊断 |
| 防漂移 / 任务快照 | drift prevention / job snapshot | provider_snapshot/model_snapshot 锁定创建时的解析结果 |
| 自动化蓝图 | automation blueprint | 参数化任务模板目录 |
| 调度器 Provider | scheduler Provider | 可插拔的触发源接口 |
| 生命周期守卫 | lifecycle guard | 拦截任务在体内 restart gateway 的死循环 |
| 运行认领 / 触发认领 | run claim / fire claim | 防 mid-run 重复触发 |
| 递归守卫 | recursion guard | 禁 cronjob 工具防任务里再建任务 |
| 原子写入 | atomic write | 临时文件+fsync+rename |
| 跨进程文件锁 | cross-process file lock | flock / .tick.lock |
| 真相源 | source of truth | jobs.json 单文件真相源 |
| 热加载 | hot reload | 改 provider key 不重启 gateway 即生效 |
| 多级流水线 | multi-stage pipeline | context_from 串任务 |
| 注入扫描 | injection scan | prompt injection / 数据外泄检测 |
| 数据工厂 | data factory | 12 章：Agent 产出训练数据的流水线 |
| 轨迹压缩 | trajectory compression | trajectory_compressor.py |
| 工具集随机化 | toolset randomization | 按分布独立掷骰采样 |
| 推理过滤 | reasoning filtering | 丢弃零推理轨迹 |
| 保头保尾压中间 | protect the head and tail, compress the middle | 压缩策略口号 |
| 幻觉工具过滤 | hallucinated-tool filtering | 丢弃含幻觉工具名的轨迹 |
| 内容匹配续传 | content-matched resume | 按 prompt 文本而非行号续传 |
| 工具统计补零 | tool-stat zero-fill | 对没用到的工具填 0，对齐 Arrow schema |
| 哨兵字符串 | sentinel string | mini_swe 的 MINI_SWE_AGENT_FINAL_OUTPUT 收尾信号 |
| 摘要模型 | summarizer model | 压缩中间过程用的模型 |
| 训练窗口 | training window | 轨迹要压进的 token 窗口 |
| 微调 | fine-tuning (SFT) | SFT 保留缩写 |
| 强化学习 | reinforcement learning (RL) | RL 保留缩写 |
| 无序并行 | unordered parallel | imap_unordered，谁先跑完先收 |
| 批级并行 | batch-level parallelism | 并行粒度是 batch 而非 prompt |
| 不性感的代码 | the unsexy code | 13 章标题；基础设施 |
| 车队效应 | convoy effect | 固定退避导致的同步碰撞；官方文档原词 |
| 声明式列协调 | declarative column reconciliation | _reconcile_columns 自动补列 |
| schema 演化 | schema evolution | 声明式 + 版本链分工 |
| 全文搜索 | full-text search | FTS5 |
| 脱敏 | redaction | RedactingFormatter；secret 遮罩 |
| 会话标签 | session tag | 日志行的 [session_id] |
| 供应链硬化 | supply-chain hardening | 精确钉版 + 懒安装 + 顾问扫描 |
| 投毒 | poisoning | 供应链投毒（Shai-Hulud worm 事件） |
| 精确钉版 | exact version pinning | ==X.Y.Z |
| 懒安装 | lazy install | 首次用到才装可选依赖 |
| 供应链顾问 | supply-chain advisory | 已知投毒版本告警 |
| 免密钥发布 | keyless publishing | OIDC trusted publishing，无长期 token |
| 真边界 / 承重边界 | real boundary / load-bearing boundary | 沙箱隔离；对比启发式 |
| 启发式（非边界） | heuristic (not a boundary) | 审批/脱敏/Skills Guard，防误触 |
| 防手滑 / 防误触 | guard against slip-ups | 审批拦「不小心 rm -rf」 |
| 单租户 | single-tenant | 信任模型：单用户个人 Agent |
| 气密 / 密封 | hermetic | 测试隔离不变量 |
| 三级自愈 | three-tier self-healing | DB 损坏 FTS rebuild→去重→丢弃重建 |
| fail-open | fail-open | 锁子系统出错时跳过压缩，保留原词 |
| TTL 租约 | TTL lease | compression_locks 租约式互斥 |
| 爆炸半径 | blast radius | 懒安装：可选依赖被投毒不连累其它 |
| 结语 | Epilogue | 全书收尾 |
| kawaii | kawaii | 日语借词，源码自用（display.py/skin_engine.py），保留原词不译 |
| 引导安装器 / bootstrap 安装器 | bootstrap installer | Tauri 单文件启动器 |
| 后端保姆 | backend babysitter | 主进程管后端生命周期，14 章比喻 |
| 纯函数模块 | pure-function module | 无 require('electron') 便于单测 |
| 失败闩锁 | failure latch | 起过一次失败就重抛，防反复安装 |
| 孤儿检测 | orphan detection | served token≠spawn token 且子进程已死 |
| 后端进程池 | backend process pool | 多 Profile，LRU 淘汰 |
| LRU 淘汰 | LRU eviction | POOL_MAX_BACKENDS |
| idle reaper | idle reaper | 回收空闲后端，保留原词 |
| 自更新 | self-update | 双轨更新 |
| 双轨 | dual-track | 同一更新在不同平台的两种落地 |
| staged updater | staged updater | Tauri updater，保留原词 |
| 契约 | contract | @hermes/shared 事件契约 |
| 帧格式 | frame format | 一条 WS 跑两种帧 |
| 指数退避重连 | exponential-backoff reconnect | use-gateway-boot.ts |
| 铸 ticket / 铸票 | mint a ticket | OAuth 一次性 ws-ticket |
| 活性判断 / 活性校验 | liveness check | cookiesHaveLiveSession |
| 功能模块地图 | feature-module map | 20 模块地图 |
| Web 壳 | Web shell | Electron 包 Web Dashboard |
| 零侵入 | zero-intrusion | 桌面不 import Python |
| 星图 | Star Map | 会话星图可视化，专名 |
| 桌面宠物 / petdex | desktop pet / petdex | 保留 petdex 原词 |
| 命令面板 | command palette | |
| 系统托盘 | system tray | |
| 项目（桌面工作区） | Project | 具名工作区 projects.db，桌面/TUI 独有；专名首字母大写 |
| Profile（配置档专名） | Profile | 大写专名，与 01 章「Profile 系统」一致；但代码字段 `profile` 和 per-profile 复合修饰词保持小写 |
| 卡死循环 / stuck loop | stuck loop | `_STUCK_LOOP_THRESHOLD`，保留原词 |
| 洪泛控制 / Flood control | flood control | stream_consumer 限速降级，源码原词 |
| Deliverable Mode | Deliverable Mode | 官方特性名，MEDIA: 标签变附件，专名大写保留 |
| Team Gateway | Team Gateway | relay 团队网关，专名大写保留 |

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
