# 种子测试文档：Agent 核心机制（节选）

> 基于 hermes-agent commit: `874c2b1f`

## 凭证池：多密钥轮换的生命周期管理

当一个 LLM Provider 只有一把 API Key 时，一切都很简单。但现实中，团队往往持有同一 Provider 的多把 Key——有的是为了分摊配额，有的是为了故障切换。hermes-agent 用 `CredentialPool`（定义在 `agent/credential_pool.py:250`）来管理这种"一对多"的关系。

CredentialPool 的核心是一个线程安全的轮换调度器。它维护了每把 Key 的状态（健康、冷却中、已禁用），当某把 Key 遭遇 429 限流时，自动将其标记为冷却并切换到下一把可用 Key。冷却时长采用指数退避策略，从 30 秒起步，每次翻倍直到上限 15 分钟。这套机制解决的问题很明确：在不中断用户对话的前提下，最大化多密钥的可用性。

## 子代理委托

delegate_tool.py 实现了 hermes-agent 的子代理架构。子代理是完全隔离的 AIAgent 实例，拥有独立的上下文窗口和工具集。为了安全，`DELEGATE_BLOCKED_TOOLS` 定义了 6 个禁止授予子代理的工具：`delegate_task`（防递归）、`clarify`（禁用户交互）、`memory`（禁共享写入）、`send_message`（禁跨平台副作用）、`execute_code`（禁脚本执行）和 `web_search`（禁外部搜索）。

当父代理调用 delegate_task 时，子代理在 ThreadPoolExecutor 中启动。子代理的审批回调由 `delegation.subagent_auto_approve` 配置控制：默认为 false，此时所有危险命令自动拒绝；设为 true 则自动批准，适用于无人值守的批量场景。

## 上下文压缩

对话越长，上下文窗口越容易溢出。context_compressor.py 采用"保头保尾压中间"的策略：保留系统提示（头部）和最近的对话（尾部），将中间的历史对话交给一个辅助 LLM 做摘要压缩。摘要预算按压缩内容量的 15% 分配（`_SUMMARY_RATIO = 0.15`），下限 2000 token，上限 12000 token。压缩后的摘要以 `[CONTEXT COMPACTION]` 前缀标记，明确告知模型这是历史参考而非当前指令。

认证池、子代理委托和上下文压缩，加上 Prompt Caching、Rate Limiting、Trajectory 记录、Model Metadata 查询、Display/Insights 可视化、Fallback Chain 故障切换、LSP 集成——这些机制共同构成了 Agent 核心运行时的完整图景。每一个都是为了解决大模型 Agent 在真实生产环境中遇到的具体问题：网络不可靠、Key 有配额、上下文有上限、用户要看到过程。
