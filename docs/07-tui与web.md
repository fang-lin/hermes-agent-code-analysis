# 07 - TUI 与 Web：Agent 的三张面孔

## 同一个 Agent，三种界面

Hermes 有三种用户界面，它们背后连接的是同一个 Agent 核心：

```
┌─────────────────────────────────────────────────────────────┐
│  面孔 1: prompt_toolkit TUI                                  │
│  cli.py → 直连 AIAgent                                      │
│  纯 Python，启动最快                                         │
├─────────────────────────────────────────────────────────────┤
│  面孔 2: React/Ink TUI                                       │
│  ui-tui/ (Node.js) → tui_gateway/ (JSON-RPC) → AIAgent     │
│  更丰富的 UI，但多一层进程间通信                              │
├─────────────────────────────────────────────────────────────┤
│  面孔 3: Web Dashboard                                       │
│  web/ (React SPA) → FastAPI → PTY → Ink TUI → AIAgent      │
│  浏览器访问，最灵活但链路最长                                 │
└─────────────────────────────────────────────────────────────┘
```

这三种界面不是渐进替换的关系——它们并存，各有适用场景。prompt_toolkit TUI 是默认模式（`hermes` 直接启动），适合轻量快速的终端交互。Ink TUI 是 v0.11.0 新增的（`hermes --tui`），提供更现代的界面（React 组件、sticky composer、streaming 动画）。Web Dashboard（`hermes web`）通过浏览器访问，适合远程管理和可视化。

## 面孔 1：prompt_toolkit TUI

`cli.py`（11,395 行）是 Hermes 最早的界面。它用 Python 的 `prompt_toolkit` 库（`cli.py:44-65`）构建了一个固定底部输入区的 REPL：上方是滚动输出区，中间是 spinner 状态行，下方是文本输入区。

`HermesCLI` 类（`cli.py:1887`）是这个界面的控制器。它直接持有一个 `AIAgent` 实例——没有中间层、没有进程间通信，Python 函数调用直达。这是它启动最快的原因，也是它的限制——UI 能力受限于终端能做的事情。

斜杠命令（如 `/model`、`/personality`、`/insights`、`/skin`）在一个大型 elif 链中分发（`cli.py:6197-6333`），所有命令定义集中在 `hermes_cli/commands.py:59-179` 的 `COMMAND_REGISTRY` 中——这是唯一的数据源，CLI 补全、Gateway 命令分发、Telegram slash commands 都从它派生。

## 面孔 2：React/Ink TUI

v0.11.0 引入了一个完全重写的终端界面：基于 React/Ink 的 Node.js 应用（`ui-tui/` 目录）。Ink 是 "React for CLI"——用 React 组件模型构建终端 UI，支持 flexbox 布局、状态管理、流式渲染。

但 Hermes 的 Agent 核心是 Python 写的——Node.js 怎么调用它？答案是 `tui_gateway/`，一个 Python 侧的 JSON-RPC 服务器，作为桥接层：

```
Node.js (ui-tui/)                     Python (tui_gateway/)
┌──────────────┐                     ┌──────────────────┐
│ Ink/React    │                     │ JSON-RPC Server  │
│ 组件树       │  stdio JSON-RPC     │                  │
│              │ ←──────────────→   │ → AIAgent        │
│ GatewayClient│                     │ → HermesCLI      │
│              │                     │   (slash_worker)  │
└──────────────┘                     └──────────────────┘
```

启动时，`GatewayClient`（`ui-tui/src/gatewayClient.ts:91-124`）spawn 一个 Python 子进程运行 `tui_gateway.entry`，通过 stdio 交换 JSON-RPC 帧。Python 侧把真实 stdout 替换为 stderr（`tui_gateway/server.py:158-167`），防止 print 语句污染协议通道。

慢操作（如 `cli.exec`、`session.branch`）被路由到 ThreadPoolExecutor（`server.py:141-155`），避免阻塞 RPC 分发循环——如果 Agent 执行一个长命令时 RPC 被阻塞，用户连 Ctrl+C 都按不了。

斜杠命令的处理有一个有趣的设计：`slash_worker.py` 维护一个持久化的 `HermesCLI` 子进程来执行斜杠命令。为什么不直接在 tui_gateway 里处理？因为很多斜杠命令（如 `/model`、`/tools`）的实现深度依赖 `HermesCLI` 的内部状态，抽离出来的成本太高。

## 面孔 3：Web Dashboard

Web Dashboard（`hermes web` 或 `hermes dashboard`）是一个完整的管理界面，让用户通过浏览器查看会话、管理配置、监控使用量。

**后端**是 FastAPI 应用（`hermes_cli/web_server.py`），默认绑定 `http://127.0.0.1:9119`。安全机制包括：每次启动生成随机 session token（`web_server.py:73-147`）、CORS 仅允许 localhost、Host 头校验防 DNS rebinding。

API 端点覆盖了几乎所有管理需求（`web_server.py:484-3050`）——从会话浏览、配置修改到 Cron 任务管理，基本上 CLI 能做的事，Dashboard 也能做。

**前端**是 Vite/React SPA（`web/` 目录），使用 React Router v7、`@xterm/xterm`（终端模拟器）、i18n 国际化（英语 + 中文）、插件系统（`PluginSlot`/`PluginPage`）。

最有趣的是 **Chat 页面**——它在浏览器里嵌入了完整的终端体验：

```
浏览器 xterm.js (WebGL 渲染)
  → WebSocket /api/pty
  → FastAPI PtyBridge
  → POSIX PTY
  → node ui-tui/dist/entry.js
  → tui_gateway → AIAgent
```

Chat 嵌入功能默认关闭，需要 `hermes dashboard --tui` 或 `HERMES_DASHBOARD_TUI=1` 显式启用。启用后，在浏览器里和 Agent 对话的体验和在终端里完全一样——因为它底层就是运行了一个真实的终端 TUI，然后把终端输出通过 WebSocket 流到浏览器的 xterm.js 渲染器。

## 皮肤系统：统一的视觉主题

三种界面需要统一的视觉风格——用户在 CLI 里设了一个暗色主题，不应该在 Web Dashboard 里变回亮色。

`hermes_cli/skin_engine.py` 定义了皮肤配置（`SkinConfig`，`skin_engine.py:129`），包含 20+ 色槽（banner、UI 元素、状态栏等）、spinner 表情/动词自定义、品牌文本（Agent 名称、欢迎/告别语）。内置 6 套皮肤：default（金色 kawaii）、ares（战神红铜）、mono（灰度）、slate（冷蓝）、daylight（亮色）、warm-lightmode。

用户可以自定义皮肤：把 YAML 文件放到 `~/.hermes/skins/<name>.yaml`，通过 `/skin <name>` 激活。皮肤变更同步到 Ink TUI——`tui_gateway` 通过 `GatewaySkin` 事件将 Python 侧的皮肤配置推送到 Node.js 侧（`ui-tui/src/theme.ts` 的 `ThemeColors` 镜像了 Python 的色槽定义）。

`KawaiiSpinner`（`agent/display.py:573`）是视觉系统中最有辨识度的元素：9 种动画风格，每种有一组 kawaii 表情脸和思考动词。皮肤可以自定义这些表情和动词，覆盖默认的 `(｡◕‿◕｡)` 和 `(◔_◔)` 等。

## hermes CLI 子命令系统

`hermes_cli/main.py` 是 `hermes` 命令的入口，使用 `argparse` 分发子命令：

| 子命令 | 功能 |
|--------|------|
| `hermes`（无参数） | 启动交互式 TUI |
| `hermes gateway start/stop/status` | 管理消息网关服务 |
| `hermes setup` | 交互式安装向导 |
| `hermes web` / `dashboard` | 启动 Web UI |
| `hermes acp` | ACP server（编辑器集成） |
| `hermes cron list/add/...` | Cron 任务管理 |
| `hermes sessions browse` | 交互式会话选择器 |
| `hermes doctor` | 依赖检查和诊断 |
| `hermes update` / `version` | 版本管理 |

`--profile` / `-p` 标志在所有子命令之前预处理（`main.py:100-161`），在模块导入前就设好 `HERMES_HOME` 环境变量——这意味着你可以在同一台机器上运行多个 Hermes 实例，各自用独立的配置和数据目录。

## 接下来

这篇覆盖了 Hermes 的三种用户界面。下一篇 **08-Cron 调度与 ACP 适配** 会深入定时任务系统和编辑器集成协议。

---

*本文基于 hermes-agent v0.11.0 源码分析。所有代码引用均经过独立验证。*
