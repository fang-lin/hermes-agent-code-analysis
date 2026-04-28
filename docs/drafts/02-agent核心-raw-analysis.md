# 02-Agent 核心 — 分析 Agent 原始数据（待审核、待重写）

> 此文件是分析 Agent 的原始输出，尚未经过审核验证和文档撰写。
> 仅作为数据暂存，防止上下文压缩丢失。

---

## 1. AIAgent 类完整接口

### __init__() 参数（run_agent.py:840-902）

核心参数：
- base_url, api_key, provider, api_mode — 模型连接
- model (默认 ""), max_iterations (默认 90) — 模型和迭代控制
- tool_delay (1.0s) — 工具调用间延迟
- enabled_toolsets / disabled_toolsets — 工具集过滤
- save_trajectories (False) — RL 轨迹记录
- iteration_budget — IterationBudget 对象，父子 agent 共享 (run_agent.py:951)
- fallback_model — 备用模型配置
- credential_pool — 多 API key 轮转
- session_id — 唯一会话 ID（自动生成格式 YYYYMMDD_HHMMSS_xxxxxx）

回调参数：
- stream_callback, stream_delta_callback — 流��输出
- tool_progress_callback, tool_start_callback, tool_complete_callback — 工具生命周期
- thinking_callback, reasoning_callback — 思考/推理状态
- clarify_callback — 交互式问答（None 则 clarify 工具报错）
- step_callback — 每次 API 调用前钩��
- status_callback — 状态消息（gateway 平台用）

Gateway 参数：
- platform, user_id, user_name, chat_id, chat_name, chat_type, thread_id
- gateway_session_key — 稳定 per-chat key

### Public 方法

- run_conversation() → run_agent.py:9627 — 主入口
- chat() → run_agent.py:13063 — 单轮简化接口
- interrupt(message) → run_agent.py:4050
- clear_interrupt() → run_agent.py:4118
- steer(text) → run_agent.py:4151 — 不中断，注入到下一工具结果
- is_interrupted() → run_agent.py:4530
- get_rate_limit_state() → run_agent.py:4290
- get_activity_summary() → run_agent.py:4294
- reset_session_state() → run_agent.py:2058
- switch_model() → run_agent.py:2097
- close() → run_agent.py:4441

### 关键内部方法

- _build_system_prompt() → run_agent.py:4543
- _build_api_kwargs() → run_agent.py:7790
- _interruptible_streaming_api_call() → run_agent.py:6154
- _execute_tool_calls() → run_agent.py:8594
- _compress_context() → run_agent.py:8447
- _try_activate_fallback() → run_agent.py:6997
- _capture_rate_limits() → run_agent.py:4271

---

## 2. 对话生命周期管理

### 会话历史
- run_conversation() 做 list(conversation_history) 浅拷贝 (run_agent.py:9738-9779)
- messages 在 while 循环内持续增长
- 修剪通过 _compress_context() (run_agent.py:8447)，LLM 摘要压缩，保护头尾
- pre-flight 压缩 (run_agent.py:9846-9905)：开始前最多 3 轮压缩
- api_messages 是 messages 的逐条 .copy() (run_agent.py:10122-10165)，不污染原始

### 系统提示缓存
- _cached_system_prompt 首轮构建后复用 (run_agent.py:9798-9835)
- Gateway：从 SQLite 加载上次的 system_prompt 保持 byte-identical

### 流式响应
- stream_callback 在 run_conversation 入口赋给 self._stream_callback (run_agent.py:9678)
- _fire_stream_delta(text) (run_agent.py:6081)：经 StreamingContextScrubber 过滤后调用回调
- 工具调用 turn 静默（只有 text-only 最终响应才流式传递）

### 中断机制
- interrupt(message) 设置 _interrupt_requested=True (run_agent.py:4074)
- 信号绑定到执行线程 + fan-out 到工具工作线程 + 递归传播到子 agent
- 主循环每次迭代检查 (run_agent.py:9997-10003)
- steer(text) 不中断，缓存于 _pending_steer (run_agent.py:4151-4205)

### 错误恢复
- agent/retry_utils.py:1-57 — jittered_backoff(attempt, base=5.0, max=120.0, jitter=0.5)
- 最多 _api_max_retries (默认 3) 次重试 (run_agent.py:10280-10648)
- 429 首次不 rotate credential，第二次才切换 (run_agent.py:5761-5843)

---

## 3. API 调用细节

### _build_api_kwargs() (run_agent.py:7790-7956)
四条路径：anthropic_messages / bedrock_converse / codex_responses / chat_completions
每条路径调用对应 Transport 的 build_kwargs()

### _interruptible_streaming_api_call() (run_agent.py:6154-6996)
三条分支：
- codex_responses → 委托 _interruptible_api_call()
- bedrock_converse → 后台线程 converse_stream()，主线程 0.3s poll
- chat_completions/anthropic → 后台线程 SSE 流，90s stale 检测

### NormalizedResponse
各 transport 的 normalize_response() 返回统一结构：content, tool_calls, finish_reason

---

## 4. Prompt Caching

### 决策 (run_agent.py:2685-2759)
- anthropic_messages → native_cache_layout=True
- Claude via OpenRouter → use_prompt_caching=True, native=False

### apply_anthropic_cache_control() (agent/prompt_caching.py:41-72)
system_and_3 策略：system prompt 1 个 breakpoint + 最后 3 条消息 3 个 = 合计 4 个（Anthropic 最大值）

### TTL (run_agent.py:1154-1167)
从 config.yaml 读取，支持 "5m" (默认) 或 "1h"

### 优化策略 (run_agent.py:10207-10239)
- 系统提示稳定性（plugin context 走 user message 而非 system prompt）
- JSON sort_keys=True 标准化
- 空白 .strip() 标准化

---

## 5. Rate Limiting

### agent/rate_limit_tracker.py:1-247
- RateLimitBucket (rate_limit_tracker.py:31)：limit, remaining, reset_seconds
- RateLimitState (rate_limit_tracker.py:57)：4 个 bucket (requests_min/hour, tokens_min/hour)
- parse_rate_limit_headers() 从 12 个 x-ratelimit-* 头解析
- format_rate_limit_display() — ASCII 进度条，80% 触发警告

### 429 处理 (run_agent.py:5761-5843)
首次 429 不 rotate，再次才 mark_exhausted_and_rotate()
EXHAUSTED_TTL_429_SECONDS = 3600 (credential_pool.py:73)

---

## 6. Credential Pool (agent/credential_pool.py:364-1000)

### PooledCredential (credential_pool.py:91)
provider, id, auth_type (oauth/api_key), priority, access_token, refresh_token

### 4 种选择策略 (credential_pool.py:59-68)
fill_first (默认) / round_robin / random / least_used

### 刷新机制 (credential_pool.py:575-735)
Anthropic/Nous/Codex 各有独立 OAuth refresh 逻辑

### Seed 来源 (credential_pool.py:1074-1341)
环境变量 / singleton 存储 / custom providers 配置

---

## 7. Trajectory (agent/trajectory.py:1-57)

- save_trajectory() (trajectory.py:30)
- 成功 → trajectory_samples.jsonl，失败 → failed_trajectories.jsonl
- 格式：{"conversations": [...ShareGPT], "timestamp": ISO, "model": str, "completed": bool}
- convert_scratchpad_to_think() — <REASONING_SCRATCHPAD> → <think> 标准化

---

## 8. Model Metadata (agent/model_metadata.py:1-1467)

### 上下文长度解析优先级 (model_metadata.py:1229-1426) — 9 级 fallback：
1. config.yaml 显式覆盖
2. custom_providers 逐模型配置
3. 持久化缓存 (~/.hermes/context_length_cache.yaml)
4. Bedrock 静态表
5. /models API 探测
6. 本地服务器 (Ollama/LM Studio/llama.cpp)
7. Anthropic /v1/models API
8. Codex OAuth models 端点
9. OpenRouter + models.dev 注册表
10. 硬编码默认值 + fallback 128K

### OpenRouter 缓存 (model_metadata.py:526-559)
1 小时 TTL，缓存 context_length/max_completion_tokens/pricing

---

## 9. Display (agent/display.py:1-1003)

- build_tool_preview() (display.py:170-276) — 工具参数预览
- get_cute_tool_message() (display.py:837-995) — 工具完成行 (emoji + verb + detail + duration)
- extract_edit_diff() / render_edit_diff_with_delta() (display.py:413-566) — 内联 diff 展示
- KawaiiSpinner (display.py:573-797) — 9 种动画思考 spinner

---

## 10. Insights (agent/insights.py:93-930)

InsightsEngine.generate(days=30) 分析 SQLite 会话数据：
- overview：会话数/消息数/工具调用数/token/成本/活跃时长
- models：按模型分组统计
- platforms：按来源分组
- tools：工具调用排行
- activity：按星期/小时/日期分布
- format_terminal() — ASCII 表格 (CLI /insights)
- format_gateway() — Markdown (聊天平台)
