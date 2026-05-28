# 09-Kanban 系统：让多个 Agent 协作完成复杂任务

中文 | [English](../en/09-kanban.md)

> **本章定位**：`hermes_cli/kanban_db.py`（6,579 行）+ `hermes_cli/kanban.py`（2,762 行）+ `tools/kanban_tools.py`（1,297 行）+ `gateway/run.py` 中的 `_kanban_dispatcher_watcher()`（`run.py:5113`）+ `plugins/kanban/`（Dashboard 插件）。总计约 12,723 行核心代码。
> **关键类**：`Task`（`kanban_db.py:603`）、`Run`（`kanban_db.py:734`）、`dispatch_once()`（`kanban_db.py:4993`）、`_default_spawn()`（`kanban_db.py:5560`）。

> **本章基于 hermes-agent commit [`3bace071b`](https://github.com/NousResearch/hermes-agent/commit/3bace071b)（2026-05-24）**

---

## 为什么需要 Kanban？

单个 Agent 能完成的任务有上限——上下文窗口有限、单线程执行、一个模型不擅长所有事。当任务复杂到需要"前端工程师写 UI、后端工程师写 API、QA 做测试"时，你需要**多个 Agent 各司其职、协调工作**。

hermes-agent 的 Kanban 系统就是为此设计的。它不是简单的任务队列——它是一个完整的项目管理系统，支持任务依赖、自动调度、失败恢复、审查流程和多租户隔离。一个编排者 Agent 把大任务拆成子任务卡片，分配给不同 Profile 的 Worker Agent，Dispatcher 自动在后台调度执行。

这和 02 章讲的 `delegate_task` 子 Agent 有本质区别：`delegate_task` 是同步的（父 Agent 等待子 Agent 完成），Kanban 是异步的（任务创建后立即返回，Worker 在后台独立执行）。`delegate_task` 适合简单的"帮我查个东西"，Kanban 适合"帮我完成一个需要多人协作的项目"。

---

## 使用指南

### 基本用法

```bash
# 初始化看板
hermes kanban init

# 创建任务
hermes kanban create --title "实现用户登录 API" --assignee backend-dev

# 查看看板
hermes kanban list
hermes kanban show t_abc123

# 手动完成/阻塞
hermes kanban complete t_abc123 --summary "API 已实现并通过测试"
hermes kanban block t_abc123 --reason "需要数据库 schema 确认"
```

在对话中，Agent 通过 `kanban_*` 工具操作看板：

```
kanban_create(title="...", assignee="backend-dev", body="任务规格...")
kanban_show(task_id="t_abc123")
kanban_complete(task_id="t_abc123", summary="...", metadata={...})
```

### 配置

```yaml
# config.yaml
kanban:
  dispatch_in_gateway: true              # 在 Gateway 进程内运行调度器（默认）
  dispatch_interval_seconds: 60          # 调度间隔（秒，最小 1.0）
  max_spawn: null                        # 并发 Worker 数上限（null = 不限）
  max_in_progress: null                  # 运行中任务上限（节流慢机器）
  failure_limit: 2                       # 连续失败 N 次后自动阻塞
  dispatch_stale_timeout_seconds: 0      # 检测无心跳的僵死 Worker（0 = 禁用）
```

### 常见场景

**场景一：编排者拆分任务。** 一个配置了 `toolsets: [kanban]` 的 Profile 充当编排者——它用 `kanban_create` 创建子任务，用 `parents=[...]` 设置依赖关系，Dispatcher 自动按依赖顺序调度。编排者不执行工作，只负责拆分和分配。

**场景二：Worker 执行并交接。** Dispatcher 为每个 ready 任务 spawn 一个 Worker Agent（`hermes -p <assignee> chat -q "work kanban task <id>"`）。Worker 调用 `kanban_show` 读取任务上下文（包含前次尝试的 summary、comment 线程、父任务结果），执行工作，然后 `kanban_complete` 交出结果。

**场景三：阻塞与恢复。** Worker 遇到需要人工决策的情况（以"数据库 schema 需要确认"为例），调用 `kanban_block(reason="...")`。任务暂停，等待人类通过 Dashboard 或 CLI `kanban unblock` 恢复。恢复后 Dispatcher 重新 spawn 同一 Profile 的 Worker，新 Worker 能看到完整的 comment 线程了解上下文。

### 排错指引

| 问题 | 排查方向 |
|------|---------|
| 任务一直停在 todo | 检查是否有未完成的父任务（`kanban show` 看 parents）；`recompute_ready()` 只有父任务全部 done 才提升 |
| Worker 一直不 spawn | 检查 `dispatch_in_gateway: true`；确认 assignee 是有效的 Profile（`hermes profile list`） |
| Worker 反复失败 | 检查 `consecutive_failures` 和 `last_failure_error`（`kanban show`）；超过 `failure_limit`（默认 2）会自动阻塞 |
| 任务卡在 running | Worker 可能崩溃但 PID 还在——`kanban reclaim` 强制释放；或等 `detect_crashed_workers()` 自动检测 |
| 心跳超时 | Worker 长时间未调用 `kanban_heartbeat`——检查 `dispatch_stale_timeout_seconds` 配置 |

> 📖 **延伸阅读（官方文档）：**
> - [Kanban 系统](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban)
> - [多 Agent 协作](https://hermes-agent.nousresearch.com/docs/guides/multi-agent)

---

## 架构与实现

### 一个任务的完整旅程

```mermaid
%%{init: {"theme": "neutral", "themeVariables": {"fontSize": "14px"}, "flowchart": {"nodeSpacing": 15, "rankSpacing": 25}}}%%
flowchart TD
    CREATE["kanban_create#40;#41;<br/>创建任务"] --> TRIAGE{{"triage？"}}
    TRIAGE -->|是| TRI["triage<br/>等待人工规格化"]
    TRIAGE -->|否| TODO["todo<br/>等待依赖完成"]
    TRI -->|specify/decompose| TODO
    TODO -->|"recompute_ready#40;#41;<br/>父任务全部 done"| READY["ready<br/>等待调度"]
    READY -->|"claim_task#40;#41;<br/>CAS 原子操作"| RUNNING["running<br/>Worker 执行中"]
    RUNNING -->|"kanban_complete#40;#41;"| DONE["done"]
    RUNNING -->|"kanban_block#40;#41;"| BLOCKED["blocked<br/>等待人工"]
    BLOCKED -->|"unblock_task#40;#41;"| READY
    RUNNING -->|崩溃/超时| BLOCKED
    DONE -->|"archive_task#40;#41;"| ARCHIVED["archived"]
    RUNNING -->|"promote → review"| REVIEW["review<br/>审查中"]
    REVIEW -->|审查通过| DONE
```

**图：Kanban 任务状态机（9 种状态）**

任务的 9 种状态（`kanban_db.py:99`）：`triage`（待规格化）→ `todo`（有依赖未完成）→ `scheduled`（预约）→ `ready`（可调度）→ `running`（执行中）→ `blocked`（阻塞）↔ `review`（审查中）→ `done`（完成）→ `archived`（归档）。

### Dispatcher：调度引擎

Dispatcher 是 Kanban 系统的心脏，嵌入在 Gateway 进程内作为 asyncio task 运行（`gateway/run.py:5113`，`_kanban_dispatcher_watcher()`）。每隔 `dispatch_interval_seconds`（默认 60 秒）执行一次 `dispatch_once()`。

**每一轮 dispatch_once()（`kanban_db.py:4993`）做七件事：**

1. **收割僵尸子进程**（Unix only，`os.waitpid(-1, WNOHANG)`）——清理已退出但未被 wait 的 Worker 进程
2. **释放过期 claim**（`release_stale_claims()`）——claim TTL 过期的任务回到 ready
3. **检测无心跳的 Worker**（`detect_stale_running()`）——长时间未发心跳的任务回到 ready
4. **检测崩溃的 Worker**（`detect_crashed_workers()`）——PID 已不存在的任务自动阻塞
5. **超时强制终止**（`enforce_max_runtime()`）——超过 `max_runtime_seconds` 的 Worker 收到 SIGTERM
6. **提升就绪任务**（`recompute_ready()`）——父任务全部 done 时，todo → ready
7. **调度 ready 任务**——按 `priority DESC, created_at ASC` 排序，对每个 ready 任务：claim（CAS 原子操作）→ 解析 workspace → spawn Worker 子进程

第 7 步还有一个 **review lane**：status=review 的任务也会被调度，Dispatcher 为 review Worker 强制加载 `sdlc-review` 技能。

**Spawn Worker 的具体命令**（`_default_spawn()`，`kanban_db.py:5560`）：

```bash
hermes -p <assignee> --accept-hooks --skills kanban-worker [--skills ...] [-m model] chat -q "work kanban task <task_id>"
```

Dispatcher 为 Worker 设置一组环境变量：`HERMES_KANBAN_TASK`（任务 ID）、`HERMES_KANBAN_WORKSPACE`（工作目录）、`HERMES_KANBAN_RUN_ID`（当前 run 编号）、`HERMES_KANBAN_CLAIM_LOCK`（claim 标识）、`HERMES_KANBAN_DB`（数据库路径）、`HERMES_PROFILE`（Worker 的 Profile 名）。

**防抖机制**：连续失败的任务有 respawn guard——`consecutive_failures` 达到 `failure_limit`（默认 2）后自动阻塞，防止 crash-loop。

### Task 数据结构

`Task`（`kanban_db.py:603-731`）是一个 30+ 字段的 dataclass。核心字段：

| 字段 | 用途 |
|------|------|
| `id` | 唯一标识（`t_<hex>` 格式） |
| `title` / `body` | 任务标题和规格描述 |
| `assignee` | 指定执行的 Profile 名 |
| `status` | 9 种状态之一 |
| `priority` | 调度优先级（越大越优先） |
| `workspace_kind` | `scratch`（临时目录，归档时清理）/ `dir`（持久目录）/ `worktree`（git worktree） |
| `claim_lock` / `claim_expires` | CAS 锁和 TTL（默认 15 分钟） |
| `consecutive_failures` | 连续失败计数（spawn 失败/超时/崩溃统一计数） |
| `worker_pid` | Worker 进程 PID（用于崩溃检测） |
| `current_run_id` | 指向当前 `task_runs` 行 |
| `skills` | 强制加载的技能列表 |
| `model_override` | 单任务 LLM 模型覆盖 |

### Run：每次尝试的记录

每次 Worker 被 dispatch 执行一个任务，都会创建一条 `Run` 记录（`kanban_db.py:734-784`）。Run 的 `outcome` 字段记录结果：`completed`（成功）、`blocked`（主动阻塞）、`timed_out`（超时）、`crashed`（崩溃）、`spawn_failed`（spawn 失败）、`reclaimed`（被强制释放）。

Run 的 `summary`（1-3 句话描述做了什么）和 `metadata`（结构化数据，如 `changed_files`、`tests_run`）是**跨 run 上下文传递的核心机制**——下一个 Worker 通过 `build_worker_context()` 看到前次 run 的 summary 和 metadata，能接续工作。

### 数据库：SQLite + WAL

Kanban 数据存储在 SQLite 数据库中（`~/.hermes/kanban/<board>/kanban.db`），使用 WAL 模式允许 Dispatcher 写入时 Dashboard 仍可读取。

6 张表：

| 表 | 用途 |
|-----|------|
| `tasks` | 任务主表 |
| `task_runs` | 每次执行尝试的历史 |
| `task_links` | 父→子依赖关系（复合主键：parent_id, child_id）|
| `task_comments` | 评论线程（作者从 `HERMES_PROFILE` 取） |
| `task_events` | 追加式审计日志（Dashboard WebSocket 尾随此表） |
| `kanban_notify_subs` | 通知订阅 |

### Worker 上下文：build_worker_context()

当 Worker 调用 `kanban_show()` 时，`build_worker_context()`（`kanban_db.py:5790`）构建一个格式化的文本块，包含：

- 任务的 title、body、assignee、status
- 父任务的最新 summary（Worker 能看到上游任务的结果）
- 前 N 次 Run 的 summary、metadata、error（最多 10 次，`_CTX_MAX_PRIOR_ATTEMPTS`）
- 评论线程（最多 30 条，`_CTX_MAX_COMMENTS`）
- 各字段有大小上限（body 8KB、summary/metadata 4KB、comment 2KB）防止上下文爆炸

这是 Kanban 异步协作的关键设计——Worker 不需要和编排者对话，所有上下文通过数据库传递。

### 工具权限：Worker vs 编排者

`kanban_tools.py` 通过两个检查函数区分 Worker 和编排者的权限：

- **Worker 模式**（`_check_kanban_mode()`）：`HERMES_KANBAN_TASK` 环境变量存在（Dispatcher spawn 的）。Worker 只能操作自己的任务——`_enforce_worker_task_ownership()` 确保 Worker 不能篡改其他任务
- **编排者模式**（`_check_kanban_orchestrator_mode()`）：Profile 的 `toolsets` 包含 `kanban`，但没有 `HERMES_KANBAN_TASK`。编排者能用 `kanban_list`（Worker 不能）和 `kanban_unblock`

| 工具 | Worker | 编排者 |
|------|--------|--------|
| `kanban_show` | ✅（仅自己的任务） | ✅ |
| `kanban_complete` | ✅ | ❌ |
| `kanban_block` | ✅ | ❌ |
| `kanban_heartbeat` | ✅ | ❌ |
| `kanban_comment` | ✅ | ✅ |
| `kanban_create` | ✅（创建子任务） | ✅ |
| `kanban_list` | ❌ | ✅ |
| `kanban_unblock` | ❌ | ✅ |

### 技能引导

Dispatcher 为每个 Worker 自动加载 `kanban-worker` 技能（`skills/devops/kanban-worker/SKILL.md`），引导 Worker 正确使用 workspace、写好 summary、处理心跳、避免常见陷阱。编排者使用 `kanban-orchestrator` 技能（`skills/devops/kanban-orchestrator/SKILL.md`），引导分解策略和"不要自己动手"的原则。

Review 任务的 Worker 还会额外加载 `sdlc-review` 技能。

### Dashboard 插件

`plugins/kanban/` 提供 Web Dashboard UI（08 章已经讲过它不是调度器）。Dashboard 通过 FastAPI 路由挂载在 `/api/plugins/kanban/`，使用 session token 认证。核心能力：

- 看板视图（8 列：triage → done，archived 可选显示）
- WebSocket 实时更新（尾随 `task_events` 表）
- 任务详情抽屉（runs 历史、评论线程、事件日志）
- WAL 模式允许 Dashboard 在 Dispatcher 写入时并发读取

### 代码组织

```
hermes_cli/kanban_db.py       — 核心数据库层（Task/Run/Comment/Event + dispatch_once）（6,579 行）
hermes_cli/kanban.py          — CLI 命令入口（init/create/list/show/complete/block 等 25+ 子命令）（2,762 行）
hermes_cli/kanban_diagnostics.py — 诊断工具（1,058 行）
hermes_cli/kanban_decompose.py — 任务分解工具（477 行）
hermes_cli/kanban_swarm.py    — Swarm 编排辅助（279 行）
hermes_cli/kanban_specify.py  — 任务规格化工具（271 行）
tools/kanban_tools.py         — Agent 工具接口（9 个工具）（1,297 行）
gateway/run.py                — Dispatcher watcher（嵌入在 Gateway 的 asyncio task）
plugins/kanban/               — Dashboard 插件（Web UI + FastAPI 路由）
skills/devops/kanban-worker/  — Worker 行为指南技能
skills/devops/kanban-orchestrator/ — 编排者分解策略技能
```

### 设计决策

#### 为什么嵌入 Gateway 而不是独立守护进程？

Dispatcher 嵌入 Gateway 进程（`dispatch_in_gateway: true`）而不是独立运行，是因为 Gateway 已经是一个长期运行的进程——不需要用户额外管理一个守护进程。但如果你不用 Gateway（以纯 CLI 场景为例），可以用 `hermes kanban daemon` 或 systemd service（`plugins/kanban/systemd/hermes-kanban-dispatcher.service`）独立运行。

#### 为什么用 SQLite 而不是 Redis/PostgreSQL？

零依赖。Kanban 系统的用户是个人开发者和小团队——不需要分布式数据库。SQLite + WAL 模式在单机上提供了足够的并发能力（一个 Dispatcher 写 + Dashboard 读 + Worker 读写），且数据库文件可以直接复制备份。

#### CAS 和 claim TTL 解决了什么问题？

`claim_task()` 使用 CAS（Compare-And-Swap）原子操作确保同一任务不会被两个 Dispatcher tick 同时认领。`claim_expires`（默认 15 分钟）是安全网——如果 Worker 进程崩溃且 PID 检测失败（以容器化环境为例），TTL 过期后任务自动释放回 ready。

---

## 与其他章节的关系

| 关联章节 | 关系 |
|---------|------|
| 01 — 基础设施层 | `hermes_cli/kanban.py` 是 CLI 子命令 |
| 02 — Agent 核心 | Worker 是完整的 `AIAgent` 实例，有独立的对话循环 |
| 04 — 技能系统 | `kanban-worker` / `kanban-orchestrator` 技能引导 Agent 行为 |
| 05 — 网关层 | Dispatcher 嵌入 Gateway 的 asyncio 事件循环 |
| 08 — 内置插件 | Dashboard 是插件，提供 Web UI |

---

*本文基于 hermes-agent v0.14.0 源码分析。所有代码引用均经过独立验证。*
