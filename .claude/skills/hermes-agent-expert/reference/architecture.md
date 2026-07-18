# Architecture Walkthrough / 架构走查

Turns the mental model into a source-navigable walkthrough: the request path, the agent loop, what the model sees, the reliability layer, and a subsystem→source map. Pinned to v0.18.2 (`9de9c25f6`) — **file paths are stable, line numbers drift; grep the symbol to confirm.**
本页把"地图"变成"走查",每一步都给真源码锚点,便于 agent 跳到对应代码自己读。

---

## 1. How a request enters / 请求怎么进来

`hermes` (`pyproject.toml:308` → `hermes_cli.main:main`) is a 14,624-line argparse dispatcher.
- `chat`/no-arg → `cmd_chat()` (`main.py:2216`) → `_resolve_use_tui()`: Ink TUI (Node subprocess + `tui_gateway/`) or classic TUI (`cli.py:main()`, pure Python).
- Classic `cli.py:main()` (`:15669`, Fire entry `:16184`) dispatches **six run modes** with early-return `if`s: gateway / worktree / list-tools / machine-readable (`--quiet`, tears off stream callbacks) / human single-query / interactive.
- `web`/`dashboard` → FastAPI (`web_server.py`); `gateway` → `start_gateway()`.

All paths ultimately call the same `AIAgent.run_conversation()`. Interfaces are frontends; the routing is at the entry, not inside the Agent (ch01, ch10).

## 2. The Agent core / Agent 核心 (ch02)

`AIAgent` (`run_agent.py:393`) is a **stateful conversation orchestrator** — not the model, not the tools; the "project manager" that breaks tasks into instructions, sends them, collects results, judges done-ness. Repeatedly callable; `close()` (`:3433`) releases resources in 5 try-except'd steps (processes → terminal sandbox → browser → subagents → HTTP client).

**`run_conversation()` lifecycle** (prologue/epilogue split into separate files):
1. Prologue: normalize input, resolve turn config (skill/model), image routing.
2. **❹ Memory prefetch** — relevant snippets from the external memory provider, cached in `_ext_prefetch_cache` (reused all turn — 10 tool calls ≠ 10 queries). Injected into the **user message** (step ❼), not the system prompt.
3. **❺ Plugin context** — hooks contribute context.
4. **❼❽❾ Build the API request** from the internal `messages` list — three operations: **injection** (append ❹ memory + ❺ context to the end of the current user message; `:791-808` says explicitly "injected only for the API call, original messages never mutated, never persisted to session"), **cleanup** (sanitize), **format conversion** (per-provider).
5. Agent loop: LLM call → tool calls → tool results → repeat until done or `max_turns`. Tool dispatch = `handle_function_call()` (`model_tools.py:1019`).
6. Epilogue (`turn_finalizer.py`): goal continuation, background self-improvement review trigger, trajectory save.

**What the LLM sees each call** (ch02 "Complete Message Structure"): system prompt (static — SKILL indexes, memory-static, tool defs) + conversation history + current user message (with ❹ prefetch + ❺ context appended). The static/dynamic split is deliberate — see the caching invariant.

## 3. Prompt caching — the load-bearing invariant / 提示缓存(承重不变量)

(ch02 "Prompt Caching") The system prompt must stay **byte-stable** across turns to hit the provider cache. Hence: system prompt is built **once per session**; dynamic/timestamped/retrieved content goes in **user messages** (dual injection: static memory → system prompt, dynamic retrieval → user message); JSON is normalized (`sort_keys`) so tool defs don't churn. **Putting dynamic content in the system prompt busts the cache for the whole session** — the single most common way a well-meaning change quietly triples cost. Grep the system-prompt assembly in `run_agent.py` before touching it.

## 4. The reliability layer / 可靠性层 (ch02)

- **Retry & backoff** — 4 branches: billing-type 402 rotates key immediately; aggregator upstream rate-limit falls back directly (skips the pool); transient network retries; stream-stale (180s no token, `HERMES_STREAM_STALE_TIMEOUT`) retries.
- **Credential pool** (`credential_pool.py`) — multi-key rotation with cooldown tiers: 401→5min, 429→1h (`:113-115`); `dead` (revoked token) doesn't self-heal → re-login.
- **Fallback chain** — `fallback_model` chains across providers when one is down.
- **MoA is fail-open** (`moa_loop.py`) — advisor/reference-model failure degrades to a labeled opinion, never interrupts the main path.

## 5. Beyond the single loop / 超出单循环

- **MoA (Mixture of Agents)** — reference models advise → aggregator synthesizes. Config `moa.presets`; virtual provider `moa://local`; managed by `hermes moa`. (Note: the old `moa` *tool* was removed; it's now an Agent-loop-layer mode.)
- **Subagents** (`delegate_tool.py`) — split tasks horizontally; own `iteration_budget` (default 50, `delegation.max_iterations`), spawn depth cap, child timeout. Interrupt propagates recursively.
- **Codex App-Server Runtime** (`codex_runtime.py`) — a **third** execution path: delegate a whole turn to the Codex app-server (besides the normal loop and MoA).
- **Auxiliary model** — the unified scheduler for side tasks (background review, summaries); routed via `auxiliary.*`.
- **LSP integration** (`agent/lsp/`) — after a code edit, real language-server diagnostics ("line 42: cannot find name 'foo'") come back in the tool result — editor-grade feedback without running lint.

## 6. The gateway path / 网关路径 (ch05)

`gateway/run.py` (20,719 lines) runs one process serving 20 plugin + 9 built-in platforms.
- **Deferred loading** (`platform_registry.py`) keeps heavy SDKs out of startup.
- Inbound: platform adapter → user-authorization check (`_is_user_authorized`, `authz_mixin.py`) → `pre_gateway_dispatch` hook → AIAgent.
- Resilience: independent per-platform reconnect (`_platform_reconnect_watcher`, exponential backoff); transient network errors swallowed at the event loop (`_is_transient_network_error`, `run.py:232`); stuck-loop suspension (same session active 3 restarts → suspend, `run.py:5954`).
- Outbound: streaming delivery, dead-target registry, message-length splitting.
- The cron ticker and gateway housekeeping run on **separate daemon threads** (`cron-scheduler` vs `gateway-housekeeping`).

## 7. Subsystem → source map / 子系统→源码地图

| Subsystem | Primary source | Deep chapter |
|---|---|---|
| CLI / config / auth / Profiles | `hermes_cli/` (`main.py`, `config.py`, `auth.py`, `commands.py`) | 01 |
| Agent core / loop / caching / MoA | `run_agent.py`, `agent/`, `credential_pool.py`, `moa_loop.py`, `codex_runtime.py` | 02 |
| Tools / dispatch / approval / backends | `model_tools.py`, `tools/registry.py`, `toolsets.py`, `approval.py`, `tools/environments/` | 03 |
| Skills / Curator | `skills_tool.py`, `skills/`, `optional-skills/`, `background_review.py`, `turn_finalizer.py` | 04 |
| Gateway / platforms | `gateway/run.py`, `gateway/platform_registry.py`, `plugins/platforms/` | 05 |
| Protocols (ACP/MCP) | `acp_adapter/`, `mcp_serve.py` | 06 |
| Plugin framework / hooks | `hermes_cli/plugins.py` (VALID_HOOKS, PluginContext) | 07 |
| Built-in plugins | `plugins/` (memory / model-providers / platforms / observability / kanban) | 08 |
| Kanban | `kanban/` (dispatcher / worker / orchestrator) | 09 |
| Interfaces / TUI / skins / voice | `cli.py`, `tui_gateway/`, `hermes_cli/skin_engine.py`, `web_server.py`, `tools/voice_mode.py` | 10 |
| Cron | `cron/scheduler.py`, `cron/jobs.py`, `cron/scheduler_provider.py`, `tools/cronjob_tools.py` | 11 |
| Batch / trajectories | `batch_runner.py`, `trajectory_compressor.py`, `toolset_distributions.py`, `mini_swe_runner.py` | 12 |
| Session DB / logging / atomic writes / security | `hermes_state.py`, `hermes_logging.py`, `agent/redact.py`, `utils.py`, `SECURITY.md` | 13 |
| Desktop client | `apps/desktop/electron/`, `apps/shared/`, `apps/bootstrap-installer/` | 14 |

---

## Reading the real source efficiently / 高效读真源码
1. Locate via the table above → `grep -n "def <symbol>\|class <symbol>" <file>` to find the current line (don't trust the pinned numbers).
2. Read the function + its callers/callees; for a subsystem, start at the entry symbol in the map.
3. For the *why* behind a design (not just the *what*), fetch the deep chapter — it carries the reasoning, the alternatives considered, and the failure modes that the code alone doesn't explain.
