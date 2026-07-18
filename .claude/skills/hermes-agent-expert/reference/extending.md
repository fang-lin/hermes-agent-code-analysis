# Extension & Customization Recipes / 扩展与二开配方

hermes-agent has formal extension points — **add capability without editing the core** (`run_agent.py`/`gateway/`). Each recipe: interface → where it lives → how to register → gotcha → where to read the real source. Pinned to v0.18.2; grep symbols to confirm.
本页是二开配方。总原则:靠插件/技能/工具扩展,别改核心。**优先做 Skill,不够再做 Tool**(控制 `tools/` 膨胀,`CONTRIBUTING.md`)。

**Extension surfaces at a glance / 扩展面一览:**
Plugins (entry-point Python: tools/hooks/commands/providers/platforms) · Skills (SKILL.md, no code) · Tools (registry) · Terminal backends (BaseEnvironment) · MCP servers (config) · Config sections (providers/aliases/personalities/quick_commands).

---

## 1. A Skill (prefer this) / 加技能(首选)
No code. A skill is a `SKILL.md` (frontmatter + markdown body) that teaches the agent a workflow.
- **Where**: `~/.hermes/skills/<category>/<name>/SKILL.md`, or `hermes skills install <name>` from the Hub.
- **Frontmatter**: `name`, `description`, optional `conditions`, `required_environment_variables`, `required_credential_files`.
- **Gotchas**: frontmatter >4000 chars is truncated (name degrades to the directory name); `conditions`/`fallback_for_toolsets` can silently hide it; two cache layers (disk mtime + in-process) — restart the agent or `clear_skills_system_prompt_cache()` after edits; the Curator may archive long-unused built-ins to `.archive/`.
- **Source**: `skills_tool.py`, `skills/`, `optional-skills/`. Deep: `docs/en/04-skill-system.md`.

## 2. A Tool / 加工具
- **Built-in**: create `tools/<name>.py` → define schema + handler → `registry.register(...)` declaring the schema, handler, and owning **toolset**.
- **Via plugin** (no core edit): `ctx.register_tool(...)` — same interface.
- **Gotchas**: `check_fn` gates visibility (30s TTL cache, `tools/registry.py:134`); the tool must be in the current platform's toolset; with `tool_search` on, non-core tools must be retrieved first to become visible.
- **Source**: `tools/registry.py`, `model_tools.py` (`handle_function_call` dispatch), `toolsets.py`. Deep: `docs/en/03-tool-system.md`.

## 3. A plugin + lifecycle hook / 加插件与钩子
- **Where**: `~/.hermes/plugins/<name>/` with a `plugin.yaml` + Python module (or a pip entry-point package).
- **Register in the plugin**: `ctx.register_hook(event, fn)` — 23 events in `VALID_HOOKS` (`hermes_cli/plugins.py:135`). Declare them in `plugin.yaml`'s `provides_hooks`.
- **Middleware** (heavier): `register_middleware("llm_execution"/"tool_execution")` wraps actual execution (onion model, ch07).
- **Gotchas**: enable via `plugins.enabled` (denylist `plugins.disabled`); one plugin failing is isolated (each register call is try-except'd); `HERMES_PLUGINS_DEBUG=1` shows discovery/rejection; **discovery timing** — plugins load later than the first env read (`hermes_cli/plugins.py:812`), so a custom secret source only affects subprocess/cron/subagents on first launch, or call `reset_secret_source_cache()`; `pre_verify` has a hard cap `agent.max_verify_nudges` (default 3).
- **Source**: `hermes_cli/plugins.py` (PluginContext, VALID_HOOKS). Deep: `docs/en/07-plugin-framework.md`.

## 4. A messaging platform / 加消息平台
Platforms are **plugins** now (since v0.15), not gateway built-ins.
- **Base class**: `class BasePlatformAdapter(ABC)` — `gateway/platforms/base.py:2253` (a ~3,375-line class). It has **4 `@abstractmethod`** you MUST implement: `connect()`, `disconnect()`, `send()` (clustered ~`:2863-2888`) and **`get_chat_info()` (`:5475`)**. ⚠️ The 4th sits ~2,600 lines below the other three — a capped grep will show only 3 and you'll ship a class that won't instantiate. **Scan the whole class** (`grep -n "@abstractmethod" gateway/platforms/base.py`). Everything else (`send_image`/`edit_message`/`send_draft`/`send_typing`/capability properties) has sensible defaults — override only what your platform supports.
- **Template**: copy an existing plugin, e.g. `plugins/platforms/telegram/` — `adapter.py` (the `BasePlatformAdapter` subclass) + `plugin.yaml` + a `register(ctx)` that calls `ctx.register_platform(...)`.
- **Gotchas**: bundled platforms are **deferred-loaded** (import on first use: gateway start / cron delivery / setup) → a missing optional SDK makes it silently drop from the registry (`Deferred load of platform '<name>' failed` in `agent.log`). Don't add platform logic to gateway core.
- **Source**: `gateway/platforms/base.py` (the ABC), `gateway/platform_registry.py`, `plugins/platforms/<name>/`. Deep: `docs/en/05-gateway.md`, `08-builtin-plugins.md`.

## 5. A model Provider / 加模型供应商
- Drop a plugin under `plugins/model-providers/` → it auto-expands `PROVIDER_REGISTRY` (`hermes_cli/auth.py:447`).
- For a simple provider, no plugin needed — just add to the `providers:` section of `config.yaml`.
- **Source**: `auth.py`, `PROVIDER_REGISTRY`. Deep: `docs/en/08-builtin-plugins.md`.

## 6. A memory / context engine / 加记忆·上下文引擎
- **Memory**: implement the `MemoryProvider` ABC (19 methods) and inject via a plugin. `MemoryManager` accepts **one** external provider (conflict-avoidance). Set `memory.provider`. Injection is conversation-level (per API call), not session-persisted (ch02/ch08).
- **Context engine**: implement the `ContextEngine` ABC to replace the default compression strategy.
- **Source**: `agent/` (ContextEngine), memory plugins. Deep: `docs/en/07-plugin-framework.md`, `08-builtin-plugins.md`.

## 7. An execution (terminal) backend / 加执行后端
- Implement the `BaseEnvironment` interface under `tools/environments/` (the 7 backends: local/docker/ssh/daytona/singularity/modal/…). Select via `terminal.backend`.
- **Source**: `tools/environments/`. Deep: `docs/en/03-tool-system.md`.

## 8. Image / video generation / 加图像·视频生成
- `ctx.register_image_gen_provider(...)` in a plugin. `image_gen.provider` selects; if set it won't auto-fallback (reports exact missing key).
- **Source**: `agent/image_gen_registry.py`. Deep: `docs/en/08-builtin-plugins.md`.

## 9. A Provider transport / 加 Provider 传输层
- Implement the 4 methods of `ProviderTransport` to support a new wire protocol/provider.
- **Source**: transports layer under `agent/`. Deep: `docs/en/02-agent-core.md`.

## 10. A slash command / CLI subcommand / 加命令
- `ctx.register_command(...)` in a plugin — supports both slash commands and CLI subcommands.
- No-LLM shell shortcut: `quick_commands:` in `config.yaml`.
- **Source**: `hermes_cli/commands.py` (COMMAND_REGISTRY). Deep: `docs/en/01-infrastructure.md`, `10-interfaces-and-run-modes.md`.

## 11. Cron delivery / scheduler provider / 加定时投递·外部调度
- A platform adapter can self-register a cron delivery target.
- External scheduler: implement the scheduler-Provider interface (`cron/scheduler_provider.py`) — trigger jobs without a resident gateway; `run_one_job()` is the shared execution body.
- **Source**: `cron/scheduler.py`, `cron/scheduler_provider.py`. Deep: `docs/en/11-cron-scheduling.md`.

## 12. Config-only extensions / 纯配置扩展
`providers:` (custom provider) · `model_aliases:` · `personalities:` · `quick_commands:` · `moa.presets` · `mcp_servers:` · custom skin `~/.hermes/skins/<name>.yaml`. No code — ch01/ch10.

---

## Golden rules / 铁律
1. **Extend, don't edit core.** New logic goes in a plugin/skill/tool, not into `run_agent.py`/`cli.py`/`gateway/run.py` (the god files — the decomposition direction is *extract*, not grow).
2. **Skill > Tool.** Prefer a Skill; add a Tool only when you truly need new executable capability.
3. **Register, then verify.** After adding, confirm with `hermes plugins list` / `hermes tools` / `hermes skills list` — the `error` field explains rejections.
4. **Read the real interface before implementing.** Grep the ABC (`BasePlatformAdapter`, `MemoryProvider`, `ContextEngine`, `BaseEnvironment`, `ProviderTransport`) in the actual checkout — the method signatures are the contract, and line numbers here may have drifted.
