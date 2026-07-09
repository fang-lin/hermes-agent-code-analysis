# 09 章 diff 侦察报告（3bace071b → v2026.7.7.2）

> 侦察 agent 输出的工作底稿。**行号/数字未经主线核实，修改时逐条验证。**

## 工作量评估：中高（行号大漂移 + 12 个新机制 + watcher 迁移新文件）

## A. 过期断言要点

- **行数**：总计 12,723→13,240；kanban_db.py 6,579→8,723；kanban.py 2,762→2,845；kanban_tools.py 1,297→1,672
- **行号大漂移**：Task 类 603→839（范围 839-917）；Run 类 734→1005；dispatch_once 4993→6932；_default_spawn 5560→7662；build_worker_context 5790→7898
- **Task 字段 30→37**（agent 报告旧版数出 32 与我们上轮核实的 30 矛盾——更新时重数两版）
- **watcher 迁移新文件**：notifier gateway/run.py:4609 → **gateway/kanban_watchers.py:115**；dispatcher run.py:5113 → kanban_watchers.py:744（GatewayKanbanWatchersMixin 混入，与 05 章 mixin 重组同源）
- **数据库 6→7 张表**：新增 task_attachments（kanban_db.py:1239-1246）

## B. 新增机制要点（12 项）

优先级高：
1. **Goal Mode**：Task.goal_mode/goal_max_turns（:900-903）——Worker 跑 Ralph 式目标循环，judge 模型评估进度
2. **类型化阻塞**：block_kind ∈ {dependency, needs_input, capability, transient} + block_recurrences 计数，超 BLOCK_RECURRENCE_LIMIT=2 自动升回 triage（:100-101/:913/:916）——两种 blocked 的叙事要扩成带语义分类的版本
3. **per-profile 并发限制**：dispatch_once 新参数 max_in_progress_per_profile（:6944/:7104-7123），超限标记 skipped_per_profile_capped
4. **task_attachments 附件表**
5. **workspace 继承**：子任务默认继承父 workspace（原默认 scratch），kanban_tools.py:857-910

优先级中：session_id（按会话过滤看板）、project_id（多项目隔离+子任务继承）、idempotency_key（幂等创建）、max_retries（覆盖全局 failure_limit）、result 字段、workflow_template_id/current_step_key

## C. 交叉核对项

- kanban_watchers.py 与 05 章的 mixin 重组是同一次架构调整——两章表述要一致
- Task 字段数两版本都重数（30 vs 32 的矛盾要查清）
