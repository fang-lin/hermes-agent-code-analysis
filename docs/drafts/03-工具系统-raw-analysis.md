# 03-工具系统 — 分析 Agent 原始数据（待审核）

> 暂存分析结果防止上下文压缩丢失。关键行号和数据见此文件。

## 关键行号索引

- registry.register() 示例: file_tools.py:1118-1121
- READ_FILE_SCHEMA: file_tools.py:1025-1037
- handler 签名: file_tools.py:1089-1091
- tool_error/tool_result: registry.py:456-482
- 工具结果放回消息: run_agent.py:9413-9418 (顺序), 9049-9054 (并行)
- _HERMES_CORE_TOOLS: toolsets.py:31-63, 35 个工具
- 平台 toolset 定义: toolsets.py:327-477
- toolset_distributions.py:1-19, 14 种分布
- resolve_toolset() DFS: toolsets.py:529-579
- HARDLINE_PATTERNS: approval.py:143-165, 9 类
- DANGEROUS_PATTERNS: approval.py:201-267, 35+ 正则
- check_all_command_guards: approval.py:880
- smart 模式 LLM 判断: approval.py:703-747
- CLI 交互审批: approval.py:594-645
- Gateway 异步审批: approval.py:1085-1107, 300s 超时
- 审批持久化: approval.py:523-529 (always → command_allowlist)
- path_security.py:15-34
- url_safety.py:1-231, SSRF 防护, fail-closed
- tirith_security.py:1-692, 外部 Rust 二进制, cosign 签名验证
- MCP 后台事件循环: mcp_tool.py:55-69
- MCP 传输方式: mcp_tool.py:174-220
- MCP 工具注册: mcp_tool.py:2792-2838, toolset=mcp-{server_name}
- MCP 重名保护: registry.py:194-213
- terminal 6 种后端: terminal_tool.py:783-788, 1023-1074
- _get_env_config: terminal_tool.py:905-981
- skills 渐进式披露: skills_tool.py:1-79
- delegate_task 特殊调度: run_agent.py:8617-8634
- 工具结果三层防御: tool_result_storage.py:1-23
- per-result 持久化: tool_result_storage.py:116-172
- per-turn 总预算: tool_result_storage.py:175-226, DEFAULT_TURN_BUDGET_CHARS=200000
- 工具输出限制: tool_output_limits.py:39-41, DEFAULT_MAX_BYTES=50000
- budget_config.py:17, DEFAULT_RESULT_SIZE_CHARS=100000
- budget_config.py:38-49, PINNED_THRESHOLDS
