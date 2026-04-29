# 08 - Cron 调度与外部协议适配

> **本章定位**：三个独立子系统——`cron/`（3 文件，2,275 行定时调度）、`acp_adapter/`（9 文件，2,354 行编辑器协议适配）、`mcp_serve.py`（867 行 MCP 服务端）。它们共同点是把 AIAgent 的能力暴露给不同的外部调用者。

## Agent 不应该只在你说话时才工作

到目前为止的所有场景都是"用户说话 → Agent 回应"。但有些任务不需要人来触发——每天早上汇总 GitHub issues、每小时检查服务器健康、每周生成周报。这些需要 Agent 能**自主唤醒、执行、投递结果**。

Cron 调度系统就是为这个场景设计的。同时，Hermes 还需要被**其他系统**调用——代码编辑器（通过 ACP 协议）和 AI 工具链（通过 MCP 协议）。这三个系统看似不同，但共享一个设计原则：**把 AIAgent 的能力暴露给不同的调用者**。

## Cron 调度：文件驱动的定时任务

### 为什么不用系统 crontab

传统做法是写一个 shell 脚本，加到系统 crontab 里。但 Hermes 的 cron 有几个特殊需求：任务用自然语言描述（"总结 GitHub issues"而非 `curl | jq`）、执行需要完整的 Agent 环境（工具、记忆、技能）、结果需要投递到聊天平台。这些都不是系统 crontab 能做的。

Hermes 的 cron 是**纯应用层实现**（`cron/` 目录），不依赖系统 crontab，也不需要 root 权限：

```
~/.hermes/cron/
  ├── jobs.json          ← 所有任务的定义（JSON，原子写入）
  ├── .tick.lock         ← 文件锁，防并发执行
  └── output/
      └── {job_id}/
          └── {timestamp}.md  ← 每次执行的输出归档
```

### Job 的生命周期

用户可以通过两种方式创建 cron 任务：在聊天中说"每天早上 9 点提醒我开会"（Agent 识别意图后调用 `cronjob` 工具），或者通过 `hermes cron add` CLI 命令。

每个 Job 包含（`cron/jobs.py:503-535`）：prompt（要执行的自然语言指令）、schedule（调度表达式）、deliver（投递目标）、可选的 skills（加载哪些技能）、model（指定模型）、script（预运行脚本）等。

调度表达式支持三种格式（`jobs.py:123-209`）：

| 输入 | 类型 | 含义 |
|------|------|------|
| `"30m"` | once | 30 分钟后执行一次 |
| `"every 2h"` | interval | 每 2 小时循环 |
| `"0 9 * * *"` | cron | 标准 cron 表达式（依赖 `croniter` 库） |

### 执行引擎

Gateway 后台每 60 秒调用 `scheduler.tick()`（`scheduler.py:1197-1354`）。tick 的设计有四个值得注意的机制，它们从不同角度保障任务执行的正确性和效率：

**At-most-once（至多执行一次）语义**。先把 `next_run_at` 推进到下一个周期，再执行任务。如果任务执行中途 Gateway 崩溃重启，`next_run_at` 已经是下一个周期了，不会重复执行。这比"先执行再推进"安全——后者在崩溃时可能导致同一任务被执行两次。

**Grace window（宽限窗口）**。如果 Gateway 宕机了 6 小时再重启，不会把这 6 小时内错过的所有任务一次性批量执行。grace window 的计算是 `min(max(period/2, 120s), 7200s)`——超出这个窗口的错过任务被静默跳过。

**Wake gate（唤醒门控）**。任务可以配一个 pre-check 脚本（`scheduler.py:797-818`），脚本输出 `{"wakeAgent": false}` 时跳过整个 Agent 运行。这适合"只在有新数据时才执行"的场景——脚本先检查是否有新 PR，没有就不唤醒 Agent，省下一次 API 调用。

**`[SILENT]` 抑制**。Agent 回复以 `[SILENT]` 开头时（`scheduler.py:115`），输出保存本地但不投递到聊天。系统提示明确告诉模型可以用这个标记："如果没有值得报告的内容，回复 [SILENT]"（`scheduler.py:720-731`）。

### 投递

结果可以投递到多个目标（逗号分隔，`scheduler.py:236`）：

- `"local"` — 只存文件，不发送
- `"origin"` — 回发到创建任务的聊天
- `"telegram:12345"` — 指定平台和 chat_id
- `"discord:#general"` — 支持人类友好的频道名

投递优先使用 Gateway 正在运行的 live adapter——对需要端到端加密的平台（如 Matrix）这很重要，只有已建立的加密 session 才能发送消息。如果 Gateway 没在跑，回退到 standalone HTTP 客户端（`scheduler.py:457`）。

### 安全

Cron 任务的 prompt 在写入前会做注入扫描（`cronjob_tools.py:40-68`）：检测不可见 Unicode 字符（零宽空格等 10 种）和 10 类威胁模式（prompt injection、数据外泄、SSH 后门等）。脚本路径被限制在 `~/.hermes/scripts/` 目录内（`cronjob_tools.py:153-189`），防止路径穿越。

## ACP 适配：让编辑器使用 Hermes

ACP（Agent Client Protocol）是一个 AI Agent 通信协议，让代码编辑器（如 Zed、VS Code、Cursor）能调用外部 Agent。Hermes 通过 `acp_adapter/` 实现了 ACP server，启动方式是 `hermes acp`。

### 架构

```
编辑器 (Zed/VS Code)
  │
  │ stdio JSON-RPC
  │
  ▼
acp_adapter/server.py (HermesACPAgent)
  │
  ├─ session 管理（多 session 并发）
  ├─ 每 session 一个 AIAgent 实例
  ├─ 工具结果转换为编辑器 diff 格式
  └─ 权限审批桥接（Agent 审批 → 编辑器确认对话框）
```

传输层是 stdio JSON-RPC——stdout 专用于协议帧，所有日志输出到 stderr。每个编辑器会话（tab/workspace）对应一个独立的 `AIAgent` 实例，有自己的对话历史、工具集和工作目录。

核心执行流程在 `prompt()` 方法（`acp_adapter/server.py:501-678`）：提取用户文本 → 拦截斜杠命令 → 在 ThreadPoolExecutor 中运行 `agent.run_conversation()` → 通过事件流推送工具进度、思考内容和回复文本给编辑器。

一个关键的适配细节：当 Agent 执行 `patch` 或 `write_file` 工具时，ACP adapter 把文件修改转换为 `tool_diff_content`（old/new text diff，`acp_adapter/tools.py:21-51`），编辑器可以直接在 diff 视图中展示和审核。权限审批也做了桥接——Agent 内部的 `approval_callback` 被映射到编辑器的确认对话框，用户可以在编辑器 UI 中 allow/deny。

### 发现机制

`acp_registry/agent.json` 是 ACP 生态的 agent 注册元数据，编辑器通过它发现如何启动 Hermes：

```json
{"type": "command", "command": "hermes", "args": ["acp"]}
```

安装了 Hermes 的机器上，支持 ACP 的编辑器可以自动发现并使用它——不需要手动配置命令行。

## MCP 服务端：让其他 AI 工具访问聊天数据

在 [05-插件系统](05-插件系统.md) 中我们看到 Hermes 作为 MCP **客户端**连接外部工具。`mcp_serve.py` 是反过来的——Hermes 作为 MCP **服务端**，把自己管理的聊天平台会话暴露给其他 AI 工具（如 Claude Code、Cursor）。

一个典型场景：你在 Claude Code 里工作，想查看 Telegram 群里同事刚才说了什么——Claude Code 通过 MCP 调用 Hermes 的 `messages_read`，读取 Telegram 会话的最新消息，不需要切换到 Telegram 客户端。

启动方式：`hermes mcp serve`（stdio 传输）。它暴露 10 个工具（`mcp_serve.py:452-809`），本质上是一套消息网关的读写 API：

| 工具 | 功能 |
|------|------|
| `conversations_list` | 列出活跃会话，支持按平台/关键词过滤 |
| `conversation_get` | 获取单个会话详情 |
| `messages_read` | 读取消息历史 |
| `messages_send` | 向指定平台发送消息 |
| `channels_list` | 列出可发消息的频道 |
| `events_poll` / `events_wait` | 轮询/长轮询新事件 |
| `attachments_fetch` | 提取附件 |
| `permissions_list_open` / `permissions_respond` | 审批管理 |

`EventBridge`（`mcp_serve.py:185-425`）是事件推送的核心：后台线程每 200ms 轮询 `state.db`，用文件 mtime 比较跳过无变化的轮询（性能开销极低），发现新消息后放入内存队列（上限 1000 条），`events_wait` 通过 `threading.Event` 实现长轮询。

## 三个协议的对比

| 维度 | Cron | ACP | MCP serve |
|------|------|-----|-----------|
| 调用者 | 定时器（自驱动） | 代码编辑器 | AI 工具链 |
| 传输 | 无（进程内调用） | stdio JSON-RPC | stdio MCP |
| Agent 实例 | 每个 job 独立实例 | 每个 session 独立实例 | 无 Agent（消息网关读写桥） |
| 暴露的能力 | 完整 Agent（工具+技能+记忆） | 完整 Agent（含 diff 适配） | 仅消息网关读写 |
| 状态持久化 | jobs.json + output/ | SessionDB (SQLite) | state.db (只读) |

共同点：三者都不修改 Agent 核心——它们是核心之外的适配层，通过各自的协议把 AIAgent 的能力暴露给不同的消费者。

## 接下来

到此为止，我们已经覆盖了 Hermes 的所有主要子系统。接下来的 **09-ACP 适配** 将被合并到本章（已覆盖）。**10-环境与部署** 会聚焦运维——Docker 构建、终端后端配置、多 Profile 管理。

---

*本文基于 hermes-agent v0.11.0 源码分析。所有代码引用均经过独立验证。*
