# 02 章 diff 侦察报告（3bace071b → v2026.7.7.2）

> 侦察 agent 输出的工作底稿。**行号/数字未经主线核实，修改时逐条验证。**

## 工作量评估：高（全书最重——行号全漂移 + agent/ 新增约 40 个文件、28 个新机制要选材）

## A. 过期断言要点

- run_agent.py 4,309→6,013；agent/ 约 102→126+ 文件；conversation_loop.py 4,231→5,312
- 行号全漂移：run_conversation run_agent.py:4053→5745（且改为轻量转发器，真身 conversation_loop.py:232→523）；interrupt 1627→2619；steer 1728→2720；switch_model 599→792；close 2099→3433；__init__ 349→416；预飞压缩 conversation_loop.py:474→~1092
- 不变项 ✓：max_iterations=90（:427）；DEFAULT_MAX_ITERATIONS=50/MAX_DEPTH=1（delegate_tool.py:586 区域）；系统提示三层概念仍在（但 build_system_prompt_parts :113，构建路径改为 _restore_or_build_system_prompt，conversation_loop.py:282-405）
- LSP：ServerDef **26→27**；_maybe_lsp_diagnostics 1443→~1892；_lsp_local_only 1342→~1791

## B. 新增机制要点（28 项，必须选材——不能全写）

**结构性（必写）**：
1. **turn_finalizer.py（507 行，新文件）**：对话循环后处理独立成文件（预算耗尽总结/轨迹保存/持久化/记忆技能审查触发）——14 步生命周期的后几步引用要迁移，"上帝文件分解"叙事
2. **turn_context.py（565 行）**：每轮独立上下文容器（中断/重试/记忆注入状态）——并发场景关键数据结构
3. **MoA 循环**（moa_loop.py 1,073 行 + moa_trace.py）：/moa 多模型聚合推理——与 12 章 moa 工具集移除相呼应（moa 从"工具"变成了"agent 循环模式"？更新时查清这层关系）

**值得成段**：计费/积分追踪（billing_view+credits_tracker 1,089 行）、凭证持久化+秘密管理框架（credential_persistence/secret_scope/secret_sources，对接 1Password/Bitwarden）、TTS/转录 provider 注册框架（agent 侧 4 文件，对应 07 章新注册方法）、推理超时（reasoning_timeouts.py）、验证流程（verification_*/pre_verify 钩子的 agent 侧）、turn_retry_state、context_breakdown（上下文占用分析）

**提及即可/可略**：learning_graph/learning_mutations、PET 目录（~3,000 行提示词演化树）、coding_context.py（883 行）、message_content/sanitization、bounded_response、vertex_adapter、runtime_cwd、ssl_guard、shell_hooks、oneshot、jiter_preload、replay_cleanup、trace_upload、stream_diag

## C. 交叉核对项

- turn_finalizer.py ↔ 04 章（技能触发迁移）已互相印证
- MoA：12 章分布删 moa、06 章 _POLISHED_TOOLS 删 mixture_of_agents、02 章新增 moa_loop——三处指向"moa 工具 → MoA 循环"的重构，更新前先把这条线查实
- 计费/凭证/秘密管理与 01 章（auth 扩展）、05 章（多租户）有边界要划
