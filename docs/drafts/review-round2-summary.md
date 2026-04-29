# 第二轮审核汇总（6 Agent 并行）

## 事实错误（已二次验证确认）
1. 00: Dockerfile "两阶段" → 三阶段（3 个 FROM）
2. 00: mcp_serve.py 功能描述"对话、记忆" → 消息网关（平台消息读写、审批）
3. 01: CodexTransport → ResponsesApiTransport
4. 02: cache_ttl 1h 写入成本 1.6x → 2x（5m 是 1.25x）
5. 02: stale stream 90s → 180s（HERMES_STREAM_STALE_TIMEOUT 默认值）
6. 02: __init__ 参数图含 stream_callback → 应删除（属于 run_conversation）
7. 02: Model Metadata fallback 链顺序有误

## 审核 Agent 误报（二次验证否决）
- extras 数量：审核 Agent 说 34，实际 26，文档正确

## 文学性 🔴 必须修改
1. 00: lazy import 未解释
2. 00: 依赖列举段过载（7 个包名）
3. 00: run_agent.py:9627 行号在概述中层次不匹配
4. 01: 网关层核心段信息密度过高（单段 7 个信息点）
5. 02: Credential Pool 章节密度过高（策略→状态转换缺呼吸）

## 缺图（高优先级）
- 01: 工具注册流程图、记忆双注入图、系统提示 7 层图
- 02: Fallback Chain 流程图、重试退避状态机、Credential Pool 状态机

## 文学性 🟡 建议修改（选择性采纳）
- 术语统一："子代理" vs "子 Agent"
- REPL/AST/LRU 首次出现补说明
- 各种过渡句和衔接优化
- dogfooding/RL 术语展开
