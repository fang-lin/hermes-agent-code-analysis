# apps/ 与 optional-mcps/ 摸底报告（v2026.7.7.2 新增）

> 侦察 agent 输出的工作底稿。**数字未经主线核实**（agent 报告内部有少量数字不一致，如 desktop 合计 158,766 与 apps 总体 146,579 并存，正式写作前须重测）。
> 侦察时间：2026-07-09

## apps/desktop —— 桌面应用（主体）

- **是什么**：Electron + React 19 的跨平台桌面客户端。不是轻量壳，是完整应用（DMG/NSIS/MSI/AppImage/deb/rpm 全平台分发）。
- **规模**：TS/TSX 约 14.1 万行 + Electron 主进程 .cjs 约 1.75 万行；src/app/ 下 20 个功能模块、157 个 .tsx（chat 模块最大，约 2.1 万行；session 9.6K；settings 8.9K）。
- **架构**：Electron 主进程（`electron/main.cjs`，~4.5K 行）启动/管理 headless 的 `hermes serve` Python 后端；渲染器（React）通过 `@hermes/shared` 的 `JsonRpcGatewayClient` 走 tui_gateway JSON-RPC/WebSocket API。
- **对接**：与 CLI 共享同一 HERMES_HOME（配置/会话/技能/凭证全通用，desktop 会话和 CLI 会话可互相切换）；可连远程后端（basic-auth/OAuth）。
- **独立性**：独立版本号（package.json v0.17.0）、独立构建发行；对核心 Python 代码零侵入，纯 API 耦合。
- **官方文档**：仅 `website/docs/user-guide/desktop.md` 一页（300 行，用户指南级），与 CLI/TUI 平级。

## apps/bootstrap-installer —— 引导安装器

- Tauri 2 + Rust（3,566 行 Rust + 1,264 行 TS/TSX）。Windows/macOS 的带签名单文件启动程序：驱动 install.ps1 等脚本，初始化 Python venv/Git/ripgrep，再拉起完整 desktop 应用。

## apps/shared —— 共享客户端库

- 526 行纯 TS：`JsonRpcGatewayClient` + WebSocket URL/认证（OAuth PKCE、basic-auth）。被 desktop 和 web dashboard 共用。

## optional-mcps/ —— 官方认证 MCP 目录

- 3 个 manifest.yaml：Linear（HTTP+OAuth）、n8n（stdio+API key）、Unreal Engine（HTTP localhost）。主仓只收 manifest 指针不含实现；`hermes mcp install official/<name>` 时用于工具探测。归属 03 章（工具系统/MCP）顺带一段即可。

## 与我们文档体系的关系（供决策）

**关键联动（来自 10 章侦察的交叉证据）**：web_server.py 从 4,671 行暴涨到 16,926 行，主要就是为 desktop 提供后端（HERMES_DESKTOP=1、PTY WebSocket、插件管理 API、desktop 内嵌 cron ticker）；tui_gateway 也从 8 文件涨到 11（git_probe/project_tree 都是为 desktop 侧边栏服务）。**desktop 不是孤立的新目录，它拉动了 10 章原有内容的重构。**

**归属选项的事实依据**：
- 支持"并入 10 章"：它本质是又一种交互界面（官方也归在 user-guide 与 CLI/TUI 平级）；后端路径（web_server/tui_gateway）本来就是 10 章的内容。
- 支持"单独成章"：14 万行代码规模超过任何现有章节的源码范围；技术栈独立（TS/Electron/Rust）；独立版本与发行周期；20 个功能模块的内部结构值得架构分析。
- 折中：10 章讲"界面分流 + desktop 如何接入既有后端"（对接机制），新章讲 desktop 自身架构（Electron 双进程、bootstrap、update、git ops）。

**注意**：本项目 14 章分析的是 Python 主体；desktop 是 TS/Electron 客户端，读者群体和分析深度的定位（是否值得对一个前端应用做同等深度的源码分析）是决策的核心变量，交用户定。
