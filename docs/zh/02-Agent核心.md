# 02-Agent 核心：对话协调器的内部运作

中文 | [English](../en/02-agent-core.md)

> **本章定位**：`run_agent.py`（4,309 行）+ `agent/` 子目录（含子目录共 102 个 .py，63,679 行）。这是 Agent 核心模块，系统的心脏。
> **关键类**：`AIAgent`（`run_agent.py:326`）——有状态的对话协调器。核心循环在 `agent/conversation_loop.py`（4,231 行）。

> **本章基于 hermes-agent commit [`3bace071b`](https://github.com/NousResearch/hermes-agent/commit/3bace071b)（2026-05-24）**

---

## 为什么要深入 AIAgent？

上一章分析了 hermes_cli——Agent 运行之前的基础设施。但当配置就位、凭证准备好之后，真正的工作从 `AIAgent` 开始。

00 章的"一条消息的旅程"已经走过了 Agent 的主线路径：构建提示词 → 调用模型 → 执行工具 → 循环。但那只是表面。`run_agent.py` + `agent/` 加起来近 68,000 行代码里，藏着大量影响性能、成本和可靠性的机制：Prompt Caching 如何节省 token 费用？被限流了怎么办？多个 API Key 怎么轮转？整个 Provider 挂了怎么自动切换？对话轨迹怎么存成训练数据？

这些不是"高级特性"——它们是让 Hermes 能在生产环境 7x24 稳定运行的基础设施。

---

## 使用指南

### 基本用法

大多数情况下，用户不需要直接和 AIAgent 打交道——CLI 和 Gateway 会自动创建和管理它。但以下几个参数影响 Agent 的行为，值得了解：

```yaml
# config.yaml 中与 Agent 核心相关的配置
agent:
  max_turns: 90           # 单次对话最大迭代次数（工具调用轮数）
  gateway_timeout: 1800   # 网关模式下的空闲超时（秒）

model:
  fallback_model:         # 主力模型挂了自动切换到哪
    provider: "openrouter"
    model: "deepseek/deepseek-r1"

credential_pool_strategies:
  openrouter: "round_robin"  # 多 Key 轮转策略

prompt_caching:
  cache_ttl: "5m"         # Prompt 缓存 TTL（"5m" 或 "1h"）
```

### 常见场景

**场景一：配置 Fallback Chain。** 主力 Provider 偶尔会限流或故障。在 `config.yaml` 中设置 `fallback_model`，Agent 会在主力耗尽重试后自动切换——用户可能只注意到回复风格略有变化，而不是聊天完全断掉。

**场景二：多 API Key 轮转。** 团队共享多把 Key 分摊配额。在 `.env` 中写多个 Key（逗号分隔），配置 `credential_pool_strategies` 选择轮转策略（fill_first / round_robin / random / least_used）。

**场景三：编程式调用。** 从 Python 代码直接使用 Agent：

```python
from run_agent import AIAgent
agent = AIAgent(base_url="https://openrouter.ai/api/v1", model="anthropic/claude-opus-4.6")
result = agent.run_conversation("分析这段代码的安全漏洞")
print(result["response"])
agent.close()
```

### 排错指引

| 问题 | 排查方向 |
|------|---------|
| Agent 循环不停止 | 检查 `max_turns` 设置；子 Agent 共享父的 `iteration_budget` |
| 频繁 429 限流 | 配置 Credential Pool 多 Key 轮转；或设置 fallback_model |
| 上下文溢出错误 | 上下文压缩器应自动处理；检查 `compression` 配置项 |
| 流式响应卡住 | 180 秒无新 token 会自动重试（`HERMES_STREAM_STALE_TIMEOUT` 可调） |

> 📖 **延伸阅读（官方文档）：**
> - [Agent Loop 内部](https://hermes-agent.nousresearch.com/docs/developer-guide/agent-loop)
> - [Fallback Provider](https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers)
> - [Credential Pool](https://hermes-agent.nousresearch.com/docs/user-guide/features/credential-pools)
> - [上下文压缩](https://hermes-agent.nousresearch.com/docs/developer-guide/context-compression-and-caching)

---

## 架构与实现

### AIAgent 是什么？

`AIAgent`（`run_agent.py:326`）本质上是一个**有状态的对话协调器**。它不是模型本身，也不是工具本身——如果把整个系统比作一个项目团队，LLM 是做决策的核心，工具是实际干活的执行者，那 AIAgent 就是项目经理——把任务分解成指令，发出去，收集结果，判断是否完成，决定下一步。

#### 四个协作方向

AIAgent 和四个方向的组件交互：

```mermaid
flowchart TD
    CALLER["调用者<br/>CLI / Gateway / 父 Agent"]
    AGENT["AIAgent<br/>───────────────<br/>状态：会话历史、系统提示缓存、<br/>迭代预算、当前 Provider、<br/>rate limit 计数器"]
    LLM["LLM API<br/>───────────────<br/>Anthropic / OpenAI / Bedrock /<br/>Gemini / 本地引擎 ...<br/>#40;Transport 抽象层#41;"]
    TOOLS["工具层<br/>───────────────<br/>72 个工具<br/>含 delegate_tool<br/>→ 创建子 AIAgent"]
    PERSIST["持久化<br/>───────────────<br/>SQLite 会话存储<br/>MEMORY.md / USER.md<br/>trajectory.jsonl<br/>checkpoint 快照"]

    CALLER -->|"run_conversation#40;#41; / interrupt#40;#41;<br/>steer#40;#41; / switch_model#40;#41; / close#40;#41;"| AGENT
    AGENT --> LLM
    AGENT --> TOOLS
    AGENT --> PERSIST
```

**图：AIAgent 与调用者、LLM API、工具层、持久化层的四向协作关系**

1. **向上（调用者）**：CLI、Gateway 或父 Agent 通过少数几个方法和 Agent 交互——`run_conversation()` 发消息拿回复（`run_agent.py:4053`）、`interrupt()` 中断（`run_agent.py:1627`）、`steer()` 温和重定向（`run_agent.py:1728`）、`switch_model()` 热切换模型（`run_agent.py:599`）、`close()` 释放资源（`run_agent.py:2099`）
2. **向左（LLM API）**：通过 Transport 抽象层调用模型。Agent 不直接和 API 打交道——Transport 负责格式转换和协议适配
3. **向下（工具层）**：通过 `model_tools.handle_function_call()` 调度 72 个工具。特殊的是 `delegate_tool`——它会反向创建新的 AIAgent，形成递归结构
4. **向右（持久化）**：SQLite 存会话、MEMORY.md/USER.md 存跨会话记忆、trajectory 存训练数据、checkpoint 存文件系统快照

#### AIAgent 的参数设计

AIAgent 的 `__init__`（`run_agent.py:349`）接收超过 60 个参数，大致分为四组：

| 组 | 典型参数 | 用途 |
|---|---------|------|
| 模型连接 | `base_url`、`api_key`、`provider`、`api_mode`、`model`、`fallback_model` | 连接哪个 LLM |
| 回调接口 | `tool_*_callback`、`thinking_callback`、`reasoning_callback`、`clarify_callback`、`stream_delta_callback`、`status_callback` | Agent 运行时怎么通知调用者 |
| 会话控制 | `session_id`、`max_iterations`、`iteration_budget`、`save_trajectories`、`checkpoints_enabled`、`prefill_messages` | 控制对话的行为和边界 |
| Gateway 身份 | `platform`、`user_id`、`user_name`、`chat_id`、`gateway_session_key` | 消息来自哪个平台的哪个用户 |

为什么这么多参数？因为 AIAgent 被三个完全不同的入口使用——CLI 需要流式回调和中断支持，Gateway 需要平台身份和会话隔离，批量运行器需要轨迹保存和预算控制。与其拆成三个子类（引入继承复杂度），不如用大参数列表配合合理的默认值，让调用方只传自己关心的部分。实际的初始化逻辑委托给 `agent/agent_init.py`（1,637 行，`run_agent.py:416-417`）。

#### AIAgent 实例的生命周期

Agent 实例是**长生命周期的**。在 Gateway 模式下，一个 Agent 实例可能服务同一个用户几小时甚至几天，中间处理几十次 `run_conversation()` 调用。

```mermaid
flowchart LR
    INIT["创建 #40;__init__#41;<br/>初始化客户端、工具集、<br/>记忆管理器、压缩器"]
    ACTIVE["活跃<br/>#40;可被反复调用#41;"]
    RUN["run_conversation#40;#41; × N<br/>switch_model#40;#41;<br/>interrupt#40;#41; / steer#40;#41;"]
    CLOSE["关闭 #40;close#41;<br/>终止后台进程<br/>关闭沙箱环境<br/>关闭浏览器会话<br/>中断子 Agent<br/>关闭 HTTP 客户端"]

    INIT --> ACTIVE
    ACTIVE --> RUN
    RUN --> ACTIVE
    ACTIVE --> CLOSE
```

**图：AIAgent 实例的生命周期——创建后可被反复调用，close() 释放所有资源**

`close()`（`run_agent.py:2099`）按五个步骤释放资源：终止后台进程（ProcessRegistry）→ 清理终端沙箱 → 关闭浏览器会话 → 关闭子 Agent → 关闭 HTTP 客户端。每步独立 try-except，一步失败不影响后续清理。

#### v0.14.0 的架构重构

v0.14.0 相比 v0.11.0 有一个重大变化：`run_agent.py` 从 13,293 行缩减到 4,309 行。核心循环被拆到了 `agent/conversation_loop.py`（4,231 行），系统提示构建拆到了 `agent/system_prompt.py`（380 行）和 `agent/prompt_builder.py`（1,465 行），Agent 初始化拆到了 `agent/agent_init.py`（1,637 行）。`run_agent.py` 里剩下的大多是 forwarder 函数——保持了向后兼容的 API 表面，但实现委托给各子模块。

### 一次完整对话的生命周期

当调用者（CLI、Gateway 或父 Agent）调用 `run_conversation()`（`conversation_loop.py:232`）时，一次对话按以下顺序展开：

```mermaid
flowchart TD
    subgraph BEFORE ["循环之前"]
        R["恢复主力 Provider<br/>#40;如果上轮 Fallback 了#41;"]
        S["构建/复用系统提示<br/>#40;会话内只构建一次#41;"]
        C["预飞压缩检查<br/>#40;历史消息超阈值？#41;"]
        M["记忆预取<br/>#40;外部 memory provider#41;"]
        P["插件 pre_llm_call 钩子"]
    end

    subgraph LOOP ["核心循环（最多 max_iterations 次）"]
        CHK["检查中断标志"]
        API["构建 API 参数 → Transport 转换<br/>→ 流式调用模型"]
        PARSE{{"响应类型？"}}
        TOOL["执行工具<br/>#40;串行或并行#41;"]
        TEXT["最终文本回复"]
        CHK --> API --> PARSE
        PARSE -->|工具调用| TOOL
        TOOL -->|结果放回消息| CHK
        PARSE -->|纯文本| TEXT
    end

    subgraph AFTER ["循环之后"]
        SAVE["保存会话到 SessionDB"]
        TRAJ["写 Trajectory #40;如开启#41;"]
        MEM["记忆审查 #40;定期触发#41;"]
        SKILL["技能自改进 #40;定期触发#41;"]
    end

    BEFORE --> LOOP --> AFTER
```

**图：`run_conversation()` 的完整生命周期——循环前准备、核心循环、循环后收尾**

**循环之前**做五件事：

1. **恢复主力 Provider**（`conversation_loop.py:297`）——如果上一轮触发了 Fallback，这一轮先尝试恢复主力模型
2. **构建/复用系统提示**——会话内只构建一次，后续复用缓存（保证 Prompt Caching 命中）。Gateway 续接会话时从 SessionDB 加载旧提示，避免重建导致缓存失效
3. **预飞压缩**（`conversation_loop.py:474`）——进入循环前就检查历史消息是否超过上下文阈值，超过则最多做 3 轮压缩。这防止了"带着超长历史调 API，直到 Provider 报错才压缩"的问题
4. **记忆预取**——从外部 memory provider（以向量数据库为例）检索和当前消息相关的记忆片段，结果缓存到整个 turn 内复用（10 次工具调用不会查 10 次）
5. **插件 pre_llm_call 钩子**——插件可以在这里注入额外上下文到用户消息中（不是系统提示——那会破坏缓存）

**核心循环**（`conversation_loop.py:644`）的每一轮做以下事情：

1. **检查中断标志**（`conversation_loop.py:649`）——如果用户按了 Ctrl+C 或发了新消息，`_interrupt_requested` 为 True，立即 break
2. **组装 API 消息**（`conversation_loop.py:788-831`）——把内部的 `messages` 列表转换为 `api_messages`：注入外部记忆检索结果到当前用户消息、拷贝推理内容、清理内部标记字段、标准化 JSON（`sort_keys=True`）
3. **拼接系统提示**——把缓存的系统提示放在 `api_messages` 最前面，作为 `system` 角色消息
4. **应用 Prompt Caching 标记**——如果启用了 Anthropic prompt caching，注入 `cache_control` breakpoint
5. **消毒和修复**——清理孤立的工具结果、合并相邻用户消息、修复消息交替违规
6. **Transport 转换 → 流式 API 调用**——Transport 把 OpenAI 格式的消息转成 Provider 原生格式，发起流式请求
7. **解析响应**：
   - 如果是**工具调用** → 执行工具（串行或并行）→ 把 `assistant`（含 tool_call）和 `tool`（含结果）消息追加到 `messages` → 下一轮
   - 如果是**纯文本**（`finish_reason == "stop"`）→ 退出循环
   - 如果是**异常** → 交给 `error_classifier` 分类 → 决定重试/压缩/轮转/Fallback

循环受两道限制约束：`max_iterations`（默认 90，单次会话上限）和 `iteration_budget`（父子 Agent 共享的预算池，`conversation_loop.py:362`）。两者取更严的那个生效。当预算耗尽时，`_budget_grace_call` 允许最后一次调用让模型生成总结性回复，而不是在工具调用中途突然断掉。

**循环之后**做四件事：

1. 保存会话到 SQLite（`hermes_state.py`）
2. 写 Trajectory（如果 `save_trajectories=True`）
3. 记忆审查——根据 `memory.nudge_interval` 配置，每 N 轮触发一次自动记忆整理
4. 技能自改进——根据工具调用次数，定期触发技能创建/优化

这就是一次完整对话从头到尾发生的事情。但有一个关键问题还没有回答：LLM 实际看到的是什么？

### LLM 看到了什么？—— 每次 API 调用的完整消息结构

理解 Agent 如何利用 LLM 的智能，关键在于理解**每次 API 调用时 LLM 实际收到了什么**。这不是一条简单的用户消息——它是一个精心构造的消息序列：

```
┌─ system message ─────────────────────────────────────────────┐
│                                                               │
│  [stable 层]                                                  │
│  ├── SOUL.md（Agent 人格："你是 Hermes，一个 AI 助手..."）      │
│  ├── 工具行为引导（"当你需要搜索时调用 web_search..."）        │
│  ├── 技能系统提示（已安装技能的简介和触发条件）                 │
│  ├── 环境提示（"你在 WSL2 上运行" / "你在 Docker 容器里"）     │
│  └── 平台提示（"用户在 Telegram 上，回复用 Markdown"）         │
│                                                               │
│  [context 层]                                                 │
│  ├── 用户项目的 AGENTS.md / .cursorrules（项目级指令）         │
│  └── 调用者传入的 system_message（如有）                       │
│                                                               │
│  [volatile 层]                                                │
│  ├── MEMORY.md 快照（"用户是后端开发者，偏好 Python..."）      │
│  ├── USER.md 快照（"习惯用 vim，不喜欢 TypeScript"）           │
│  └── "Conversation started: Saturday, May 24, 2026"           │
│       "Model: anthropic/claude-opus-4.6"                      │
│                                                               │
└───────────────────────────────────────────────────────────────┘

┌─ tools（JSON schema 数组）────────────────────────────────────┐
│  [72 个工具的 function-calling schema]                         │
│  ├── {"name": "terminal", "parameters": {...}}                │
│  ├── {"name": "read_file", "parameters": {...}}               │
│  ├── {"name": "web_search", "parameters": {...}}              │
│  └── ...                                                      │
└───────────────────────────────────────────────────────────────┘

┌─ messages（对话历史 + 当前消息）──────────────────────────────┐
│                                                               │
│  [历史轮次]                                                   │
│  ├── user: "帮我搜索 Python 安全漏洞"                         │
│  ├── assistant: [tool_call: web_search("Python CVE 2026")]    │
│  ├── tool: [web_search 结果: "CVE-2026-25645..."]             │
│  ├── assistant: "找到了以下漏洞：..."                          │
│                                                               │
│  [当前轮次的用户消息]                                          │
│  ├── user: "把这些整理成表格"                                  │
│  │   + [外部 memory provider 检索结果]（注入，不持久化）       │
│  │   + [插件 pre_llm_call 上下文]（注入，不持久化）            │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**图：一次 API 调用中 LLM 收到的完整消息结构**

几个关键设计决策隐藏在这个结构里：

**为什么系统提示这么复杂？** 因为 LLM 本身不知道自己运行在什么环境里——它不知道用户在 Telegram 上还是终端里，不知道有哪些工具可用，不知道用户的偏好。系统提示的作用是**给 LLM 提供做决策所需的全部上下文**。没有环境提示，LLM 可能给出 Windows 命令而实际在 Linux 上运行；没有工具引导，LLM 可能描述要做什么而不是真的调用工具。

**为什么记忆分两路注入？** MEMORY.md 快照在系统提示的 volatile 层（会话内不变），外部 memory provider 的检索结果注入到用户消息中（每轮不同）。这样设计是因为系统提示只构建一次且被缓存——如果每轮都往系统提示里塞新的检索结果，缓存就失效了。用户消息本来每轮就不同，在里面加东西不影响缓存。

**为什么工具调用历史也在消息里？** LLM 需要看到之前的工具调用和结果，才能理解对话的上下文。如果它上一轮搜索了网页，这一轮被要求"整理成表格"，它需要看到搜索结果才知道整理什么。这就是为什么 `tool_call` 和 `tool` 类型的消息都保留在历史中。

**工具 schema 有多大？** 72 个工具的 JSON schema 可能占 20,000-30,000+ token。这也是为什么 Prompt Caching 很重要——工具 schema 每次都一样，不缓存就每轮都付费。

理解了 LLM 看到什么之后，后面的各节就有了明确的上下文——它们各自影响上面这个消息结构的哪个部分。

### Prompt Caching：让重复的 token 不再重复付费

每次调用模型 API，完整的消息序列（系统提示 + 历史对话 + 当前消息）都要从头发送。一个 Hermes 会话中，系统提示可能占 5,000-10,000 token，但它在 20 轮对话中几乎不变——等于同样的内容付了 20 次钱。

Prompt Caching 是对这个浪费的应对。`agent/prompt_caching.py`（79 行）实现了一个跨 Provider 通用的缓存标记策略。以 Anthropic 为例，它允许最多 4 个 `cache_control` breakpoint，Hermes 的 "system_and_3" 策略这样分配：

```mermaid
flowchart TD
    SP["system prompt ← breakpoint 1（最稳定）"]
    MID["中间消息（命中缓存前缀）"]
    UN2["user message N-2 ← breakpoint 2"]
    AN2["assistant response N-2 ← breakpoint 3"]
    UN1["user message N-1 ← breakpoint 4"]
    SP --> MID --> UN2 --> AN2 --> UN1
```

**图：Prompt Caching 的 breakpoint 分配——系统提示占一个，最近三条各占一个**

系统提示是最稳定的前缀——会话内不变，命中率接近 100%。Hermes 在多个层面守护前缀稳定性：系统提示只构建一次（`_cached_system_prompt`）、JSON 工具参数做 `sort_keys=True` 标准化（防序列化顺序差异导致 cache miss）、消息内容 `.strip()` 消除空白差异。

缓存 TTL 可通过 `prompt_caching.cache_ttl` 配置：5 分钟（默认，写入成本 1.25 倍）或 1 小时（写入成本 2 倍，适合消息间隔较长的 Gateway 场景）。如果缓存完全失效——不会崩溃，只是退回到正常的全量计费。这是一个"有则更好，无则不损"的优化。

### 重试与退避：优雅地处理 API 失败

调用外部 API 必然会遇到失败。对一个可能运行几小时的 Gateway 会话来说，零失败是不现实的，关键是**失败后怎么恢复**。

重试逻辑在 `agent/conversation_loop.py` 的核心循环中，每次 API 调用失败后触发。退避算法是经典的**带抖动的指数退避**（`agent/retry_utils.py:19-57`）：

```
delay = min(base × 2^(attempt-1), max_delay) + jitter
```

基础延迟 5 秒，每次翻倍，上限 120 秒。为什么加 jitter？假设 Gateway 同时服务 50 个用户，Provider 返回 429 后所有会话同时等 5 秒再重试——50 个请求同时砸过去，再次限流。Jitter 给每个会话的重试时间加随机偏移，让请求在时间上分散开。

v0.14.0 新增了 `agent/error_classifier.py`（1,134 行）——一个专门的错误分类器。它的输入是异常对象，输出是结构化的 `ClassifiedError`（包含 `reason: FailoverReason` 枚举——限流、上下文溢出、OAuth 过期等触发 failover 的原因，以及 `retryable`、`should_compress`、`should_rotate_credential`、`should_fallback` 等布尔标记）。核心循环不再需要理解每种错误的语义——它只需要问分类器"该怎么做"。这比 v0.11.0 用 if-else 硬编码错误处理是一个质的进步。

429（限流）有分层处理逻辑：

```mermaid
flowchart TD
    API["API 调用失败"]
    CLS["error_classifier 分类"]
    R429["429 限流"]
    FIRST["第一次 429 → 不切凭证，等待重试"]
    SECOND["第二次 429 → 标记凭证 exhausted，切换"]
    ALLX["所有凭证 exhausted → fallback"]
    OTHER["其他错误 → 指数退避重试"]

    API --> CLS
    CLS --> R429
    CLS --> OTHER
    R429 --> FIRST
    R429 --> SECOND
    SECOND --> ALLX
```

**图：API 错误的分层处理——error_classifier 分类后决定重试、轮转还是 fallback**

第一次 429 不立刻切换凭证，是因为限流可能只是瞬时的——Provider 的限流窗口可能在几秒内重置，立刻切换反而浪费了一个本可恢复的 Key。

重试解决的是"同一个凭证下的瞬时失败"。但如果 Key 本身被限流了呢？这就需要另一层机制——凭证轮换。

### Credential Pool：多密钥的生命周期管理

早期只需要一个 API Key。但当 Hermes 支持 OAuth 登录后，凭证管理变复杂了：token 有过期时间，需要刷新；团队可能共享多个 Key 分摊配额。

`agent/credential_pool.py`（1,955 行）是一个带状态的凭证容器。每次 Agent 调用模型时，不是直接拿一个固定 Key，而是问 Credential Pool "给我一个当前可用的凭证"。

池提供四种选择策略（通过 `credential_pool_strategies` 配置）：
- **fill_first**（默认）— 优先使用最高优先级的凭证，限流才用下一个
- **round_robin** — 每次轮转到队尾，做负载均衡
- **random** — 随机选，简单的去关联策略
- **least_used** — 选使用次数最少的，确保消耗均匀

每个凭证在三种状态间流转：

```mermaid
stateDiagram-v2
    [*] --> ok
    ok --> exhausted : 429/402 限流
    exhausted --> ok : 冷却到期（默认 1 小时）
    ok --> refreshing : OAuth token 接近过期
    refreshing --> ok : 刷新成功
    refreshing --> exhausted : 刷新失败
```

**图：单个凭证的三种状态转换**

一个常见的误解是 Credential Pool 由 Agent 管理。实际上，**池的创建由 CLI/Gateway 层完成**（`hermes_cli/auth.py`），在 Agent 创建之前就准备好，通过 `credential_pool=pool` 参数注入。Agent 只是消费者——它从池中选凭证、标记限流状态、触发 token 刷新，但不负责凭证从哪里来。

### Fallback Chain：跨 Provider 的自动 Fallback

重试和凭证轮转解决的是"同一个 Provider 内部的恢复"。但如果整个 Provider 都挂了——Fallback Chain 解决更上一层的问题：**自动切换到完全不同的 Provider 和模型**。

`_try_activate_fallback()`（`run_agent.py:3151`）在重试和凭证轮换都耗尽后触发。`fallback_model` 可以是单个 dict 或有序列表（链式备用）：

```yaml
# config.yaml 示例
model:
  default: "anthropic/claude-opus-4.6"
  fallback_model:
    - provider: "openrouter"
      model: "deepseek/deepseek-r1"
    - provider: "openai"
      model: "gpt-4.1"
```

主力 → 备用 1 → 备用 2，链式尝试。切换是临时的——`_restore_primary_runtime()`（`run_agent.py:3158`）会在后续请求中尝试恢复主力，成功就自动切回，用户无感知。

在 CLI 场景，用户可以用 `/model` 手动切换；但在 Gateway 场景（多用户共享同一服务），无法依赖手动干预。Fallback Chain 让 Gateway 在 Provider 故障时自动保持服务，无需任何用户介入。

如果没有配置 `fallback_model`，连续失败最终会返回错误给用户——这是最坏的情况，但也是明确的失败，不会静默丢消息。

#### 错误恢复的三层递进

重试、凭证轮转、Fallback 不是平行的三个机制——它们是**递进的三层防线**，每层解决前一层无法处理的问题：

```mermaid
flowchart TD
    FAIL["API 调用失败"]
    L1["第一层：重试 + 退避<br/>同一凭证、同一 Provider<br/>解决瞬时故障"]
    L1OK["恢复 → 继续对话"]
    L2["第二层：凭证轮转<br/>切换到池中另一个 Key<br/>解决单 Key 限流"]
    L2OK["恢复 → 继续对话"]
    L3["第三层：Fallback<br/>切换到另一个 Provider<br/>解决整体 Provider 故障"]
    L3OK["恢复 → 继续对话"]
    ERR["返回错误给用户"]

    FAIL --> L1
    L1 -->|成功| L1OK
    L1 -->|耗尽| L2
    L2 -->|成功| L2OK
    L2 -->|所有 Key exhausted| L3
    L3 -->|成功| L3OK
    L3 -->|所有 fallback 耗尽| ERR
```

**图：错误恢复的三层递进——重试 → 凭证轮转 → Fallback，每层解决上一层无法处理的问题**

排查 API 错误时，按这个顺序定位：先看日志中的重试次数（是否触发了退避？），再看凭证状态（有没有 Key 被标记为 exhausted？），最后看 Fallback 是否激活（`_fallback_activated` 标志）。

### 流式响应：让等待变得可以忍受

等模型生成完整响应后再一次性返回，用户体验很糟——几秒的空白等待，然后突然冒出一大段文字。流式响应让 token 在生成的同时就送达用户。

但 Hermes 面临一个额外挑战：模型响应分两种——**纯文本回复**和**工具调用**。只有前者应该流式展示给用户，后者是给 Agent 自己看的内部调度指令。

`_fire_stream_delta()`（`run_agent.py:3060`）是流式分发的核心。每个文本 token 到达时，它先经过两个 scrubber 过滤：`_stream_think_scrubber` 去掉推理/思考块（以 `<think>` 标签为例，不应泄露到用户界面）、`_stream_context_scrubber` 去掉内部记忆上下文标记。过滤后分发给两个回调：
- `stream_callback`（CLI 用它驱动终端输出）
- `stream_delta_callback`（TTS 语音合成管线用它在生成文本的同时开始朗读）

**工具调用轮次完全静默**——用户不会看到"我要搜索一下网页"这样的中间文字逐字蹦出来。Hermes 用工具进度回调（`tool_progress_callback`）和 `KawaiiSpinner` 动画替代，保持输出区干净。

流式传输中如果连续 180 秒没有收到新 token（`HERMES_STREAM_STALE_TIMEOUT` 环境变量可调，定义在 `agent/chat_completion_helpers.py:1986`），会被判定为 stale stream 并触发重试——这是为了应对 Provider 侧的 SSE 连接假死（连接未断但不再推送数据）。本地引擎（以 Ollama 为例）默认不启用超时检测（`chat_completion_helpers.py:1991`），因为本地推理速度取决于硬件，可能合理地比 180 秒更慢。

到目前为止讨论的机制——缓存、流式、重试、凭证轮换、Fallback——都在处理"做同一件事但遇到了阻碍"或"怎么把结果交付给用户"。接下来要讲的子 Agent 处理的是另一类问题：任务本身太大，一个 Agent 不够用了。

### 子 Agent：横向分拆任务

用户说"分析这三个文件然后写一份报告"——分析可以并行，写报告要等分析完成。如果单个 Agent 串行做，时间是三倍。`tools/delegate_tool.py` 让 Agent 能 spawn 子 Agent 并行处理子任务。

```mermaid
flowchart TD
    PARENT["父 Agent #40;depth=0#41;<br/>模型输出: delegate_task#40;tasks=[...]#41;"]
    A["子 Agent A #40;depth=1#41;<br/>分析文件 X"]
    B["子 Agent B #40;depth=1#41;<br/>分析文件 Y"]
    C["子 Agent C #40;depth=1#41;<br/>分析文件 Z"]
    MERGE["全部完成，结果汇总返回父 Agent"]
    CONT["父 Agent 继续：根据分析结果写报告"]

    PARENT -->|并行，最多 3 个| A
    PARENT --> B
    PARENT --> C
    A --> MERGE
    B --> MERGE
    C --> MERGE
    MERGE --> CONT
```

**图：父 Agent 并行分拆三个子 Agent，汇总后继续执行**

子 Agent 运行在 `ThreadPoolExecutor` 中，默认最多 3 个并发（`_DEFAULT_MAX_CONCURRENT_CHILDREN = 3`，`delegate_tool.py:132`），共享父的 `iteration_budget`——如果父预算 90 次迭代，三个子 Agent 加起来也只能用这 90 次中剩下的部分。

#### 安全隔离

子 Agent 不是父的完整克隆。它的工具集是父的**子集**（取交集，`delegate_tool.py:891-930`），且五个工具被强制禁用（`DELEGATE_BLOCKED_TOOLS`，`delegate_tool.py:45`）：

| 禁用的工具 | 原因 |
|-----------|------|
| `delegate_task` | 防止无限递归（除非 role 是 `orchestrator`）|
| `clarify` | 子 Agent 在后台线程，没有 stdin，无法交互 |
| `memory` | 避免多个子 Agent 并发写 MEMORY.md 导致冲突 |
| `send_message` | 防止子 Agent 擅自给用户发消息 |
| `execute_code` | 强制逐步推理，不走捷径 |

嵌套深度默认 1 层（`MAX_DEPTH = 1`，`delegate_tool.py:133`）——父 spawn 子，但子不能再 spawn 孙。可通过 `delegation.max_spawn_depth` 放宽到最多 3 层。如果需要更深嵌套，给子 Agent 设置 `role: "orchestrator"` 让它保留 `delegate_task` 工具。

#### 审批和错误处理

子 Agent 运行在独立线程中，缺少 CLI 的交互上下文。如果子 Agent 要执行危险命令（以 `rm -rf` 为例），父 Agent 的审批回调对它不可见。默认行为是 `_subagent_auto_deny`（`delegate_tool.py:69`）——自动拒绝所有需要审批的操作。对于 cron 任务或批量运行场景，可以配置 `delegation.subagent_auto_approve` 放开限制。

如果子 Agent 崩溃（异常退出），`ThreadPoolExecutor` 会捕获异常，父 Agent 收到一个包含错误信息的结果——不会导致父 Agent 崩溃。`_active_subagents` 注册表（`delegate_tool.py:151`）让 TUI 界面可以实时显示当前有多少子 Agent 在运行、各自在做什么，并支持单独中断某个子 Agent。

无论是单 Agent 还是多层子 Agent，每次对话运行结束时，系统都可以把完整的执行轨迹保存下来——这就是 Trajectory 机制存在的原因。

### Trajectory：从运行时到训练数据

`agent/trajectory.py`（56 行）是 Agent 核心里最简单也最独立的模块。它在 `run_conversation()` 正常返回后，把完整对话序列追加写入 JSONL（ShareGPT 兼容格式）。它不影响任何核心逻辑，和主流程之间是单向依赖——移除它不破坏任何功能。

成功的写入 `trajectory_samples.jsonl`，失败的写入 `failed_trajectories.jsonl`——失败案例对研究者同样有价值，甚至更有价值（"模型在哪里犯错"和"做对了什么"一样重要）。Nous Research 用这些轨迹训练下一代工具调用模型，这是 Hermes "research-ready" 定位的基础设施之一。默认关闭，主要被 `batch_runner.py` 和 RL 研究流程使用。

上面讨论的几个机制——缓存、重试、凭证轮换、Fallback——都在底层默默运作。但还有两个问题需要在 Agent 运行之前解决：模型的上下文窗口有多大？Agent 是否健康、花了多少钱？

### Model Metadata：在混乱的生态中找到模型的真实参数

`agent/model_metadata.py`（1,828 行）解决一个看似简单的问题：当前模型的上下文窗口有多大？

同一个模型通过不同路径访问，参数可能完全不同——以 GPT-5.5 为例，通过 Codex OAuth 是 272K 上下文，直连 OpenAI API 是 1.05M。本地模型的上下文取决于 GPU 显存分配。有些 Provider 的 API 根本不返回元数据。

`get_model_context_length()`（`model_metadata.py:1430`）实现了一条十余级 fallback 链：

```
0.  config.yaml 显式覆盖 → 用户设了就用这个，不再往下查
0b. custom_providers 逐模型配置
1.  持久化缓存 (~/.hermes/context_length_cache.yaml) → 命中则跳过网络查询
1b. AWS Bedrock 静态表 → 紧跟缓存，不走网络探测
2.  自定义端点 /models API 探测
3.  本地服务器（Ollama /api/show、LM Studio、llama.cpp /v1/props）
4.  Anthropic /v1/models API
5.  Provider 感知查询（Copilot /models、Nous 后缀匹配、Codex OAuth）
6.  OpenRouter API + models.dev 注册表
8.  硬编码默认值表（模糊匹配，最长 key 优先）
9.  本地服务器最后兜底（再试一次）
10. 最终 fallback → 256K
```

查到的结果会被缓存：OpenRouter 元数据缓存 1 小时，自定义端点缓存 5 分钟。如果所有级别都没命中，兜底到 256K（`DEFAULT_FALLBACK_CONTEXT = CONTEXT_PROBE_TIERS[0]`，`model_metadata.py:128`）——这个值足够大多数模型工作，但如果实际上下文比 256K 小，压缩器会在运行时自动修正。

过度设计了吗？考虑到 Hermes 支持 35 种 Provider 和本地引擎，每个都有自己的元数据查询方式（或者根本没有），这条 fallback 链是实际需求驱动的。排查"上下文长度不对"的问题时，从这条链的第 0 级往下检查即可定位是哪个数据源返回了错误值。

### Display 和 Insights：可观测性

**`agent/display.py`**（1,037 行）处理**实时可观测性**——Agent 执行工具时终端显示什么。工具执行预览、完成行（emoji + 动词 + 耗时）、内联 diff 展示、`KawaiiSpinner` 思考动画。Spinner 不只是装饰——在长等待中给用户"系统还活着"的信号。

**`agent/insights.py`**（930 行）处理**事后可观测性**——`/insights` 命令查看使用统计：token 消耗、预估成本、按模型/平台/工具的分组统计。

两个模块都不影响 Agent 核心逻辑——完全移除它们 Agent 照常工作。它们是单向依赖的可观测性层。

### 代码组织

```
run_agent.py                  — AIAgent 类 + forwarder 函数（4,309 行）
agent/
├── conversation_loop.py      — 核心对话循环（4,231 行）
├── auxiliary_client.py       — 辅助 LLM 客户端（5,319 行）
├── agent_init.py             — Agent 初始化（1,637 行）
├── credential_pool.py        — 凭证池管理（1,955 行）
├── model_metadata.py         — 模型元数据解析（1,828 行）
├── context_compressor.py     — 上下文压缩（1,749 行）
├── prompt_builder.py         — 提示词构建（1,465 行）
├── error_classifier.py       — API 错误分类（1,134 行）
├── display.py                — 实时可观测性（1,037 行）
├── insights.py               — 事后统计（930 行）
├── system_prompt.py          — 系统提示三层组装（380 行）
├── prompt_caching.py         — Prompt Cache 标记（79 行）
├── retry_utils.py            — 退避算法（57 行）
├── trajectory.py             — 轨迹保存（56 行）
├── transports/               — Provider 适配层（已在 00 章覆盖）
│   ├── base.py               — ProviderTransport ABC
│   ├── chat_completions.py   — OpenAI 兼容
│   ├── anthropic.py          — Anthropic 原生
│   ├── bedrock.py            — AWS Bedrock
│   └── codex.py              — OpenAI Codex Responses
└── ...（另 ~60 个文件）
```

### 设计决策

#### 从上帝文件到模块化

v0.11.0 的 `run_agent.py` 有 13,293 行。v0.14.0 缩减到 4,309 行——9,000 行被拆到 `agent/` 子目录。核心循环去了 `conversation_loop.py`，初始化去了 `agent_init.py`，系统提示去了 `system_prompt.py`。`run_agent.py` 变成了一个 forwarder 壳——保持 `AIAgent` 的 API 表面不变，但实现委托给各子模块。

这不是一步到位的重构，而是渐进式的。`agent/` 目录会继续增长，但 `AIAgent` 作为外部 API 的稳定性不受影响。

#### 错误分类器的引入

v0.11.0 的错误处理是 if-else 硬编码。v0.14.0 引入了 `error_classifier.py`——一个专门的分类器，输入是异常对象，输出是结构化的 `ClassifiedError`（包含 `reason`、`retryable`、`should_compress`、`should_rotate_credential`、`should_fallback` 等布尔标记）。核心循环不再需要理解每种错误的语义——它只需要问分类器"该怎么做"。

### 扩展点

1. **自定义 Transport**：实现 `ProviderTransport` 的四个方法即可支持新 Provider
2. **自定义 ContextEngine**：实现 `ContextEngine` ABC 替换默认的压缩策略
3. **自定义 MemoryProvider**：通过插件注入外部记忆后端
4. **Fallback Chain**：通过 `fallback_model` 配置链式备用

---

## 与其他章节的关系

| 关联章节 | 关系 |
|---------|------|
| 00 — 项目全景 | Agent 核心循环和 Transport 层的概览已在 00 章给出 |
| 01 — 基础设施层 | hermes_cli 负责创建 AIAgent 并注入凭证和配置 |
| 03 — 工具系统 | Agent 通过 model_tools.py 调度工具，工具层是 Agent 的"手脚" |
| 04 — 网关层 | Gateway 创建并缓存 AIAgent 实例（≤128 个） |
| 06 — 插件框架 | 插件通过 PluginContext 注入钩子，在 Agent 循环的多个节点介入 |

---

*本文基于 hermes-agent v0.14.0 源码分析。所有代码引用均经过独立验证。*
