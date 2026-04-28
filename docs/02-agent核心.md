# 02 - Agent 核心：13,000 行上帝文件的内部运作

## 为什么要单独分析 AIAgent？

上一篇架构分析追踪了一条消息从输入到输出的完整路径。但在 Agent 核心那一站，我们只看了表面——主循环、工具执行、Transport 适配。实际上，`run_agent.py` 这个 13,293 行的单文件里藏着大量影响性能、成本和可靠性的机制：Prompt Caching 如何节省 75% 的 token 费用？被限流了怎么办？多个 API key 怎么轮转？对话轨迹怎么存？

这些机制不是"高级特性"——它们是让 Hermes 能在生产环境稳定运行的基础设施。

## AIAgent 的角色与协作关系

在深入内部机制之前，先搞清楚一个根本问题：**AIAgent 在整个系统中扮演什么角色？它和哪些组件交互？**

### 概念模型

`AIAgent` 本质上是一个**有状态的对话协调器**。它不是模型本身，也不是工具本身——它是坐在中间的调度员，负责把用户的意图翻译成"模型调用 + 工具执行"的序列，直到任务完成。

用一个比喻：如果 LLM 是大脑，工具是手脚，那 AIAgent 就是神经系统——接收感觉输入（用户消息），把大脑的决策（模型响应）变成动作（工具调用），再把动作的结果反馈给大脑。

### 谁创建 Agent？

```
┌─────────────┐     ┌──────────────┐     ┌───────────────┐
│   CLI        │     │   Gateway     │     │  delegate_tool │
│  (cli.py)    │     │ (gateway/     │     │ (子代理创建)    │
│              │     │  run.py)      │     │               │
└──────┬───────┘     └──────┬────────┘     └───────┬───────┘
       │                    │                      │
       │  创建 1 个         │  创建 ≤128 个         │  创建 N 个
       │  AIAgent           │  AIAgent (缓存)       │  子 AIAgent
       │                    │                      │
       └────────────────────┼──────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   AIAgent     │
                    └───────────────┘
```

三个创建者，三种场景：
- **CLI** 创建 1 个 Agent，用户直接交互，生命周期 = 整个会话
- **Gateway** 为每个聊天会话创建 1 个 Agent，最多缓存 128 个，空闲 1 小时回收
- **delegate_tool** 创建子 Agent，生命周期 = 单个委托任务

### Agent 的四个协作方向

```
                    ┌──────────────────────────────────┐
                    │           调用者                  │
                    │  CLI / Gateway / 父 Agent         │
                    └──────────┬───────────────────────┘
                               │
              run_conversation(message, history, stream_cb)
              interrupt(message) / steer(text)
              switch_model() / reset_session_state()
              close()
                               │
                    ┌──────────▼───────────────────────┐
                    │          AIAgent                  │
                    │                                   │
    ┌───────────────┤  状态:                            ├──────────────┐
    │               │  · 会话历史 (messages list)        │              │
    │               │  · 系统提示 (cached)               │              │
    │               │  · 迭代预算 (共享)                  │              │
    │               │  · 当前模型/provider                │              │
    │               │  · rate limit 状态                 │              │
    │               └──────────┬───────────────────────┘              │
    │                          │                                      │
    ▼                          ▼                                      ▼
┌──────────┐      ┌────────────────────┐               ┌──────────────────┐
│ LLM API  │      │    工具层           │               │  持久化            │
│          │      │                    │               │                  │
│ Anthropic│      │ 66 个工具          │               │ SQLite 会话存储   │
│ OpenAI   │      │ (terminal, file,   │               │ MEMORY.md        │
│ Bedrock  │      │  web, browser,     │               │ USER.md          │
│ Gemini   │      │  skills, ...)      │               │ trajectory.jsonl │
│ 本地引擎 │      │                    │               │ checkpoint 快照   │
│ ...      │      │ 包括子代理:         │               │                  │
│          │      │ delegate_tool      │               │                  │
│(Transport│      │ → 创建新 AIAgent   │               │                  │
│ 抽象层)  │      │                    │               │                  │
└──────────┘      └────────────────────┘               └──────────────────┘
```

Agent 与四个方向的组件交互：

1. **向上：调用者接口**。调用者（CLI、Gateway、父 Agent）通过少数几个方法和 Agent 交互：
   - `run_conversation()` — 发一条消息，拿到完整回复（`run_agent.py:9627`）
   - `chat()` — 简化接口，只返回文本（`run_agent.py:13063`）
   - `interrupt()` / `steer()` — 运行时干预（`run_agent.py:4050` / `4151`）
   - `switch_model()` — 热切换模型（`run_agent.py:2097`）
   - `close()` — 释放所有资源（`run_agent.py:4441`）

2. **向左：LLM API**。通过 Transport 抽象层调用各种模型 Provider。Agent 不直接和 API 打交道——它调用 `_build_api_kwargs()` 构建参数，Transport 负责格式转换和协议适配。

3. **向下：工具层**。通过 `model_tools.handle_function_call()` 调用 66 个工具。特殊的是 `delegate_tool`——它会反过来创建新的 AIAgent，形成父子关系。

4. **向右：持久化层**。SQLite 存储会话历史和搜索索引，MEMORY.md/USER.md 存储跨会话记忆，trajectory 文件存储训练数据，checkpoint 存储文件系统快照。

### Agent 的生命周期

```
创建 (__init__)
  │
  ├─ 初始化客户端（OpenAI/Anthropic SDK）
  ├─ 初始化工具集（discover + register）
  ├─ 初始化记忆管理器
  ├─ 初始化上下文压缩器
  │
  ▼
活跃（可被反复调用）
  │
  ├─ run_conversation() ← 可调用多次
  │    ├─ 构建/复用系统提示
  │    ├─ 核心循环（调模型 → 执行工具 → 循环）
  │    └─ 持久化会话
  │
  ├─ interrupt() ← 随时可从另一线程调用
  ├─ steer() ← 随时可从另一线程调用
  ├─ switch_model() ← 热切换，不中断会话
  ├─ reset_session_state() ← 清零计数器，开始新会话
  │
  ▼
关闭 (close)
  │
  ├─ 终止后台进程
  ├─ 关闭沙箱环境
  ├─ 关闭浏览器会话
  ├─ 中断所有子代理
  └─ 关闭 HTTP 客户端
```

关键点：**Agent 是长生命周期的**。在 Gateway 模式下，一个 Agent 实例可能服务同一个用户几小时甚至几天，中间处理几十次 `run_conversation()` 调用。这就是为什么它需要 session reset、model switch、rate limit tracking 这些"运维"能力——它不是一次性的函数调用，而是一个需要持续运行和维护的有状态服务。

## AIAgent 的参数设计

理解了 Agent 的角色和协作关系，再看它的参数就有上下文了。它的 `__init__`（`run_agent.py:840-902`）接收超过 50 个参数，大致分为四类：

```
┌─────────────────────────────────────────────────────────┐
│                    AIAgent.__init__()                     │
│                                                          │
│  模型连接           回调接口           会话控制            │
│  ├ base_url        ├ stream_callback  ├ session_id       │
│  ├ api_key         ├ tool_*_callback  ├ max_iterations   │
│  ├ provider        ├ thinking_cb      ├ iteration_budget │
│  ├ api_mode        ├ reasoning_cb     ├ save_trajectories│
│  ├ model           ├ clarify_cb       ├ checkpoints      │
│  └ fallback_model  └ status_cb        └ prefill_messages │
│                                                          │
│  Gateway 身份                                             │
│  ├ platform (cli/telegram/discord/...)                   │
│  ├ user_id, user_name, chat_id                           │
│  └ gateway_session_key                                   │
└─────────────────────────────────────────────────────────┘
```

为什么这么多参数？因为 `AIAgent` 是一个被**三个完全不同的入口**使用的类——CLI 需要流式回调和中断支持，Gateway 需要平台身份和会话隔离，批量运行器需要轨迹保存和预算控制。与其拆成三个子类（引入继承复杂度），不如用一个大参数列表（配合合理的默认值）让调用方只传自己关心的部分。

## Prompt Caching：省 75% 的钱

### 问题

每次调用模型 API，系统提示词都要随消息一起发送。一个典型的 Hermes 会话，系统提示可能有 5,000-10,000 token（包含身份、记忆、技能指南、上下文文件等）。如果一个会话有 20 轮对话，这些 token 被重复发送 20 次——但每次内容都一样。

部分 Provider 支持 Prompt Caching 来解决这个问题。以 Anthropic 为例，它允许标记消息的某些部分为"可缓存"。服务端会缓存这些前缀，后续请求如果前缀完全相同（byte-identical），就直接复用 KV cache，输入 token 按缓存价格计费（便宜 ~90%）。Claude 经 OpenRouter 调用时也支持类似的缓存机制。

### Hermes 的 system_and_3 策略

`agent/prompt_caching.py` 实现了一个叫 "system_and_3" 的策略（`prompt_caching.py:1-8`）。以 Anthropic 的原生 API 为例，它允许最多 4 个 `cache_control` breakpoint，Hermes 这样分配：

```
消息序列:
┌─────────────────────────┐
│ system prompt            │ ← breakpoint 1（最稳定，几乎不变）
├─────────────────────────┤
│ user message #1          │
│ assistant response #1    │
│ user message #2          │
│ assistant response #2    │
│ ...                      │
│ user message #N-2        │ ← breakpoint 2
│ assistant response #N-2  │ ← breakpoint 3
│ user message #N-1        │ ← breakpoint 4（最新消息）
└─────────────────────────┘
```

核心代码只有 30 行（`prompt_caching.py:41-72`）：找到 system message 放一个 breakpoint，再找最后 3 条非 system 消息各放一个。效果是：系统提示 + 绝大部分历史对话都命中缓存，只有最新的一两条消息需要重新处理。

### 缓存命中率的守护

光有 caching 标记不够——如果系统提示每次都变，缓存就是摆设。Hermes 做了几件事来守护命中率（`run_agent.py:10207-10239`）：

1. **系统提示只构建一次**。`_cached_system_prompt` 在会话内不变（`run_agent.py:9814`），除非上下文被压缩（压缩会改变消息结构，不得不重建）。动态信息（如记忆检索结果）注入到**用户消息**而非系统提示，保持前缀稳定。

2. **JSON 标准化**。工具调用参数做 `sort_keys=True, separators=(",", ":")`——同样的参数不同序列化顺序会导致缓存 miss。

3. **空白清理**。消息内容 `.strip()`，消除无意义的空白差异。

### TTL 选择

缓存有两种 TTL（`run_agent.py:1154-1167`）：5 分钟（默认）和 1 小时。1 小时 TTL 写入成本是 5 分钟的 1.6 倍，但对于间隔较长的会话（比如 Gateway 上的消息聊天），长 TTL 可以跨多次请求摊销缓存成本。用户通过 `config.yaml` 的 `prompt_caching.cache_ttl` 配置。

## 当 API 出错了：重试与退避

### 问题

调用外部 API 会失败——网络抖动、服务过载、被限流、余额不足。一个生产级 agent 不能因为一次 API 错误就崩溃。

### 带抖动的指数退避

`agent/retry_utils.py` 实现了一个经典但细心的退避算法（`retry_utils.py:19-57`）：

```
delay = min(base × 2^(attempt-1), max_delay) + jitter
```

- 基础延迟 5 秒，每次翻倍，上限 120 秒
- 关键是 **jitter**（随机抖动）：取 `[0, 0.5 × delay]` 范围的随机值叠加

为什么要 jitter？想象一个 Gateway 同时服务 50 个用户（比如通过 Telegram 或 Discord），Provider 返回 429（限流）。如果所有会话都在 5 秒后重试，就会产生"雷暴群"效应——50 个请求同时砸向 API，再次触发限流。Jitter 让每个会话的重试时间错开，分散压力。

jitter 的 seed 用 `time_ns ^ (counter × 0x9E3779B9)`（`retry_utils.py:53`），即时间戳和单调计数器的异或——确保即使在同一毫秒内创建的多个重试也有不同的随机数。

### 429 的特殊处理

429（限流）错误有特殊逻辑（`run_agent.py:5761-5843`）：

```
第一次 429 → 不切换 credential，只等待重试
  ↓ （给 Provider 时间重置限流窗口）
第二次 429 → 标记当前 credential 为 exhausted，切换到下一个
  ↓
exhausted credential 冷却 1 小时后自动恢复 (credential_pool.py:73)
```

为什么第一次不立刻切换？因为 429 可能只是瞬时的——Provider 的限流窗口可能在几秒内就重置。立刻切换 credential 反而浪费了一个本可以恢复的 key。

## Credential Pool：多把钥匙的管理

### 问题

如果你有多个 API key（比如一个 OpenRouter key 和一个 Anthropic 直连 key，或者团队共享多个 key 做负载均衡），怎么管理它们？

### 四种轮转策略

`agent/credential_pool.py` 实现了一个完整的凭证池（`credential_pool.py:59-68`）：

```
┌─────────────────────────────────────────┐
│              Credential Pool             │
│                                          │
│  策略:                                   │
│  ├ fill_first (默认) — 优先用高优先级的  │
│  ├ round_robin — 每次选后轮转到队尾      │
│  ├ random — 随机选可用凭证               │
│  └ least_used — 选使用次数最少的         │
│                                          │
│  凭证状态:                               │
│  ├ ok — 可用                             │
│  ├ exhausted — 被限流，冷却中            │
│  └ refreshing — OAuth token 刷新中       │
│                                          │
│  凭证来源:                               │
│  ├ 环境变量 (OPENROUTER_API_KEY 等)      │
│  ├ OAuth 存储 (Nous/Anthropic/Codex)     │
│  └ 自定义 Provider 配置                  │
└─────────────────────────────────────────┘
```

每个凭证是一个 `PooledCredential` 对象（`credential_pool.py:91`），携带 provider、auth_type（`api_key` 或 `oauth`）、priority、access_token、refresh_token 等字段。OAuth 凭证（如 Nous Portal、Anthropic OAuth、Codex OAuth）会在接近过期时自动刷新（`credential_pool.py:575-735`）。

`fill_first` 是默认策略——它总是优先使用最高优先级的可用凭证，只有在被限流后才 fallback 到下一个。这适合"有一个主力 key，几个备用 key"的场景。`round_robin` 适合负载均衡——让多个 key 均匀分摊请求。

## 流式响应：token 一个一个地流出来

### 为什么要流式

如果等模型生成完整响应后再一次性返回，用户会看到一段漫长的"思考中..."等待，然后突然冒出一大段文字。流式响应让用户在模型生成的同时就看到输出，体验更像"对话"。

### 实现细节

流式调用在 `_interruptible_streaming_api_call()`（`run_agent.py:6154`）中实现，根据 `api_mode` 分三条路径：

| api_mode | 流式实现 | 特殊处理 |
|----------|---------|---------|
| `codex_responses` | 委托给非流式调用（Codex 内部已是流式） | 无 |
| `bedrock_converse` | 后台线程 `converse_stream()`，主线程 0.3s poll | AWS SDK 特有的事件流格式 |
| `chat_completions` / `anthropic` | 后台线程 SSE 流 | 90 秒 stale stream 检测 |

每个文本 token 到达时触发 `_fire_stream_delta()`（`run_agent.py:6081`），它做两件事：
1. 经过 `StreamingContextScrubber` 过滤——清除 memory-context 标签（`<hermes-memory>...</hermes-memory>`），防止内部标记泄露到用户界面
2. 调用 `stream_callback` 和 `stream_delta_callback`

一个重要的设计：**工具调用 turn 静默**。如果模型响应包含工具调用，流式回调不会触发——用户只看到最终的纯文本回复被流式传输，中间的"我要搜索一下"不会逐字显示。

## Fallback Chain：当主力模型倒下了

### 问题

假设你正在用某个模型和 Hermes 对话（比如 Claude Opus 4.6 via Anthropic），突然 API 返回 500 错误。等待恢复？还是切到备用模型？

### 自动降级

`AIAgent` 支持配置 `fallback_model`——一个备用模型链（`run_agent.py:6997`，`_try_activate_fallback()`）。当主力模型连续失败时，Agent 自动切换到备用模型：

```
主力模型 (claude-opus-4-6)
    │ 连续失败
    ▼
备用模型 1 (claude-sonnet-4-6)
    │ 也失败了
    ▼
备用模型 2 (gpt-4o via OpenRouter)
    │ 成功
    ▼
继续对话（用户看到模型切换提示）
```

当主力模型恢复后，`_restore_primary_runtime()`（`run_agent.py:7192`）自动切回。这个机制对 Gateway 场景特别重要——你不希望因为一个 Provider 的临时故障就让所有用户的聊天断掉。

## Trajectory：为研究留下痕迹

Hermes 的定位之一是"research-ready"。`agent/trajectory.py` 让 Agent 在运行时记录完整的对话轨迹，用于训练下一代工具调用模型。

设置 `save_trajectories=True` 后（`run_agent.py:855`），每次 turn 结束时调用 `_save_trajectory()`（`run_agent.py:3723`）：

- 成功的轨迹写入 `trajectory_samples.jsonl`
- 失败的写入 `failed_trajectories.jsonl`
- 格式是 ShareGPT 兼容的 JSON：`{"conversations": [...], "timestamp": ISO, "model": str, "completed": bool}`

一个有意思的细节：`convert_scratchpad_to_think()`（`trajectory.py:16`）把内部的 `<REASONING_SCRATCHPAD>` 标签替换为 `<think>` 标签。这是为了和 Nous 训练框架的标准化格式对齐——不同模型用不同的推理标签名，但训练时需要统一。

## Model Metadata：一个模型的上下文窗口到底是多少？

### 问题比你想象的复杂

你可能觉得"查一下模型名就知道上下文长度了"。但实际情况是：

- 同一个模型通过不同 Provider 可能有不同的上下文限制（GPT-5.5 在 Codex 是 272K，直连 API 是 1.05M）
- 本地模型的上下文长度取决于用户分配了多少 KV cache
- 有些 Provider 不返回模型元数据
- 用户可能在配置里覆盖了默认值

### 多级 Fallback 链

`agent/model_metadata.py`（1,467 行）实现了一个十余级 fallback 来解析上下文长度（`model_metadata.py:1229-1426`，源码编号从 0 到 10，含多个子级）：

```
1. config.yaml 显式覆盖
   ↓ 没有？
2. custom_providers 逐模型配置
   ↓ 没有？
3. 持久化缓存 (~/.hermes/context_length_cache.yaml)
   ↓ 没有或过期？
4. AWS Bedrock 静态表
   ↓ 不是 Bedrock？
5. 自定义端点 /models API 探测
   ↓ 没有 /models？
6. 本地服务器（Ollama /api/show、LM Studio /api/v1/models、llama.cpp /v1/props）
   ↓ 不是本地？
7. Anthropic /v1/models API
   ↓ 不是 Anthropic？
8. Codex OAuth models 端点
   ↓ 不是 Codex？
9. OpenRouter API + models.dev 注册表
   ↓ 都查不到？
10. 硬编码默认值表 → 最终 fallback 128K
```

查到的结果会被缓存：OpenRouter 元数据缓存 1 小时（`model_metadata.py:526`），自定义端点缓存 5 分钟（`model_metadata.py:562`）。

这个系统看起来过度设计了吗？考虑到 Hermes 支持 20+ Provider 和本地引擎，每个都有自己的元数据查询方式（或者根本没有），这个 fallback 链是实际需求驱动的。

## Display 和 Insights：Agent 的"仪表盘"

最后两个模块不涉及核心逻辑，但影响用户体验：

**`agent/display.py`**（约 1,000 行）负责终端输出的"视觉糖衣"：
- 工具执行预览（"🔍 Searching: Python security vulnerabilities"）
- 工具完成行（"| 📖 read_file  src/main.py  0.3s"）
- 内联 diff 展示（最多 6 个文件、80 行）
- `KawaiiSpinner`——9 种动画风格的思考转圈（dots/bounce/grow/arrows/star/moon/pulse/brain/sparkle）

**`agent/insights.py`**（`InsightsEngine`，约 930 行）分析 SQLite 会话数据，生成使用报告：
- 总 token 消耗、预估成本
- 按模型/平台/工具的分组统计
- 按星期/小时的活跃分布
- 最长/最多消息/最多工具调用的 session

两种输出格式：ASCII 表格（CLI 的 `/insights` 命令）和 Markdown（Gateway 聊天平台）。

## 回顾：一个单文件怎么管理这么多职责？

`run_agent.py` 13,293 行、50+ 个 init 参数、10+ 个核心方法——这是一个典型的"上帝对象"。为什么不拆分？

实际上 Hermes 一直在拆分。`agent/` 子目录（约 29,200 行）就是从 `run_agent.py` 逐步抽离出去的：Transport 层、上下文压缩、记忆管理、提示词构建、rate limit tracking、credential pool……这些都曾经是 `run_agent.py` 的一部分。

但核心循环——"调用模型 → 解析响应 → 执行工具 → 循环"——以及所有这些子系统之间的协调逻辑，仍然需要一个地方来编排。这就是 `run_agent.py` 的角色：**不是做所有事情的类，而是把所有子系统串在一起的胶水**。只是胶水本身也有 13,000 行——这说明编排复杂系统本身就是一个复杂任务。

## 接下来

这篇深入了 Agent 核心的内部机制。接下来的 **03-工具系统** 会聚焦 Agent 的"手脚"——66 个工具是如何注册、调度和执行的，工具集如何配置，以及安全审批机制怎么工作。

---

*本文基于 hermes-agent v0.11.0 源码分析。所有代码引用均经过独立验证。*
