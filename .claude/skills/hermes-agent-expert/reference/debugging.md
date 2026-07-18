# Debugging Playbook / 调试手册

Aggregated from the troubleshooting sections of all 15 chapters, pinned to **v0.18.2** (`9de9c25f6`). Anchors are a map — `grep` the symbol in the actual checkout to confirm current lines.
本页汇总 15 章全部排错节。先定位子系统 → 查对应日志 → 症状→根因→修复。

---

## 1. Where the logs are / 日志在哪(四路 + 专用)

`~/.hermes/logs/` — four-way fan-out (`hermes_logging.py`):

| Log | Level / rotation | Contains |
|---|---|---|
| `agent.log` | INFO+, 5MB×3 | **Everyday workhorse** — full activity. First place to look for almost anything. |
| `errors.log` | WARNING+, 2MB×2 | Only problems — fast triage. |
| `gateway.log` | gateway mode only | Records whose logger name starts with `gateway`/`hermes_plugins`/`plugins.platforms`. |
| `gui.log` | `MODE=gui`, 10MiB×5 | Desktop side: web_server / pty_bridge / tui_gateway / uvicorn (Chapter 14). |

Each line carries a ` [session_id]` tag → `grep '\[<id>\]' agent.log` pulls one conversation. Secrets are auto-redacted (safe to share).

**Dedicated debug logs / trace switches** (turn on only when chasing a specific bug):

| Trigger | Output | For |
|---|---|---|
| always on | `~/.hermes/interrupt_debug.log` | interrupt/steer chain — enqueue (`cli.py:13448`) + actual `agent.interrupt()` (`:12361`) |
| always on | `~/.hermes/logs/tui_gateway_crash.log` | Ink TUI panic-hook full stack + `[gateway-crash]` summary in the Activity panel |
| `HERMES_OAUTH_TRACE=1` | structured JSON in log (`hermes_cli/auth.py:861`) | every OAuth event — device-code / token-refresh issues |
| `HERMES_PLUGINS_DEBUG=1` | stderr + agent.log | full plugin discovery/load log (rejection reasons) |
| `HERMES_LANGFUSE_DEBUG=true` | detailed log | Langfuse tracing not working |
| `/verbose` (in TUI) | debug log | input-preprocessing strip actions (why "sent ≠ typed") |

**Note**: ACP logs go to **stderr**, not a file (stdout is reserved for JSON-RPC) — Chapter 06.

---

## 2. Diagnostic commands / 诊断命令(先跑这些)

| Command | Shows |
|---|---|
| `hermes doctor` | dozen+ checks (version consistency, certs, gateway service, managed scope, Provider health), OK/WARN/FAIL (`hermes_cli/doctor.py`) |
| `hermes doctor --ack <id>` | dismiss a supply-chain advisory permanently |
| `hermes tools` | per-tool enable status + why a tool is unavailable. **TTY-only** — errors `requires an interactive terminal` through a pipe/cron/SSH-non-tty; in non-interactive envs use `hermes doctor` or grep `tools/registry.py` directly. |
| `hermes plugins list` | discovered / enabled / **deferred**; the `error` field = rejection reason |
| `hermes gateway status` | gateway process status, orphan-reap / PID-mismatch notices |
| `hermes auth status` | each Provider's auth status |
| `hermes cron list --all` | per-task `last_status` / `last_error` / `last_delivery_error` (no `cron get` subcommand) |
| `hermes kanban show / tail <id> / log <task_id>` | task state, event stream (`respawn_guarded` etc.), Worker output |

---

## 3. The silent-failure catalog / 静默失败清单(最容易踩)

These fail **without an obvious error** — the #1 source of "it just doesn't work." Check these first when behavior is wrong but nothing crashed:

- **A message vanished from history.** state.db write retried 15× all hit the lock → message **silently dropped** (still in memory, gone after restart/resume). Search `agent.log` for `Session DB append_message failed`. (ch13)
- **Cron ran but no message.** Reply contained `[SILENT]` (line-level match, case-insensitive) → delivery suppressed. Failed tasks always deliver regardless. (ch11)
- **`last_status=ok` but no message.** Execution succeeded, **delivery** failed — separate field `last_delivery_error`. (ch11)
- **A platform is configured but dead.** Deferred load failed (optional SDK missing) → platform silently drops from the registry. Search `agent.log` for `Deferred load of platform '<name>' failed`. (ch08)
- **Cron target never receives.** Dead-target registry marked it dead on a prior delivery failure (self-heals on success). (ch05)
- **MCP `events_poll` always empty.** `hermes_state` unavailable → EventBridge exits silently. Check stderr for `EventBridge: SessionDB unavailable`. (ch06)
- **MCP approval tools see nothing.** `permissions_list_open`/`permissions_respond` event source isn't wired in this version — always empty by design, not a config issue. (ch06)
- **Config change had no effect.** `load_config()` caches by file signature; a running gateway holds a stale cache — restart it. (ch01)
- **Skill silently hidden.** `conditions`/`fallback_for_toolsets` can hide a skill when the current toolset exists; or frontmatter >4000 chars truncated → name degrades to the directory name. (ch04)
- **`config.yaml` syntax error → all overrides lost.** Falls back to `DEFAULT_CONFIG`, backs up to `config.yaml.corrupt.<ts>.bak`, rebuilds. Any lost field after `migrate_config` usually means the whole file was skipped for a YAML error. (ch01)

---

## 4. Symptom → cause → fix, by subsystem / 症状→根因→修复(按子系统)

### Startup / config / auth (ch01, ch00)
- **`hermes` starts very slowly** — Android/Termux has fast-launch tiers; else check Python version.
- **Config change ignored** — signature cache; confirm saved; restart gateway if it holds a stale cache.
- **`config.yaml` syntax error** — see silent-failure catalog; read `hermes logs`/stderr for the YAML parse error.
- **`auth.json` corrupted / operation stuck** — reads/writes serialized via `_auth_store_lock()` (advisory flock, `hermes_cli/auth.py:1048`); a leftover `auth.json.lock` file ≠ held lock. Real stall = a process holds it; wait 15s (`AUTH_LOCK_TIMEOUT_SECONDS`) for `TimeoutError`, use `fuser`/`lsof`. Corrupt JSON → delete `~/.hermes/auth.json`, `hermes login` again.
- **Provider auth failure** — `hermes auth status`; expired OAuth → `hermes login`; API-key var name must match `api_key_env_vars` in `PROVIDER_REGISTRY`; `HERMES_OAUTH_TRACE=1` for OAuth flow.
- **`hermes login` hangs then errors** — device-code flow waiting on browser; complete authorization promptly.
- **Connected to an unexpected Provider** — `provider=auto` is an 8-level precedence chain; an exported API key preempts OAuth (stderr says which var to unset).
- **Config wrong after switching Profiles** — `_apply_profile_override()` (`hermes_cli/main.py:340`) must run before imports; if launched oddly, `HERMES_HOME` may be unset — check `get_hermes_home()`.
- **Gateway restart / abnormal status** — `hermes gateway restart` = SIGUSR1 graceful drain; config drift → `hermes gateway install --force`.

### Agent core (ch02)
- **Loop won't stop** — check `max_turns`; subagents have `delegation.max_iterations` (default 50).
- **Reply very short after budget exhausted** — normal: one tool-stripped summary call after budget.
- **Frequent 429** — configure credential-pool multi-key rotation; or `fallback_model`.
- **A key keeps showing unavailable** — cooldown tiers: 401→5min, 429→1h; `dead` (revoked) doesn't self-heal, needs re-login.
- **Switched Provider without retrying** — not a bug: 402 rotates immediately; aggregator upstream rate-limits fall back directly.
- **Context overflow / forgot the middle** — compressor auto-handles; a compression failure may take the static-fallback branch (drops middle messages). Switch: `compression.abort_on_summary_failure`.
- **Streaming stuck** — 180s no-token → auto-retry (`HERMES_STREAM_STALE_TIMEOUT`); reasoning models have wider floors; local engines disable this.

### Tools (ch03)
- **Model doesn't call a tool** — `hermes tools`; `check_fn` must return True (30s TTL cache); tool must be in the current platform's toolset; with `tool_search` on, non-core tools must be retrieved first.
- **Registered but never executed** — a `pre_tool_call` hook may have intercepted it (`model_tools.py:1175`); check `_AGENT_LOOP_TOOLS`.
- **Command denied `BLOCKED`** — HARDLINE match (**cannot** be bypassed, `tools/approval.py:366`), sudo stdin guard (`tools/approval.py:448`), DANGEROUS match (`tools/approval.py:547`), or gateway approval 300s timeout. Check `command_allowlist`.
- **Result truncated** — result >100K chars persisted to `/tmp/hermes-results/`, 1,500-char preview kept; model can `read_file` the full path.
- **Memory/skill write held pending** — since v0.17 a separate `write_approval` gates persistent memory/skill writes (esp. background self-improvement).

### Skills (ch04)
- **Skill not in list** — frontmatter well-formed? `conditions`/`fallback_for_toolsets` hiding it? same-name conflict (local wins)? frontmatter >4000 chars truncated (name → directory name)?
- **`/skillname` doesn't trigger** — `skills.disabled` / `skills.platform_disabled`.
- **`SETUP_NEEDED`** — missing `required_environment_variables` / `required_credential_files`.
- **Edit had no effect** — two cache layers (disk mtime + in-process); restart agent or `clear_skills_system_prompt_cache()`.
- **Built-in skill "disappeared"** — Curator `prune_builtins` (on by default) archived it to `.archive/` (recoverable).

### Gateway / messaging (ch05)
- **Bot doesn't reply** — `hermes gateway status`; `gateway.log`; token valid?
- **Message received but no response** — user authorization (`_is_user_authorized`, DM pairing / allowlist).
- **Session context gone** — `SessionResetPolicy` (`gateway/config.py:347`) idle/daily reset.
- **Gateway restarts frequently** — stuck-loop detection: same session active on 3 consecutive restarts → auto-suspended (`gateway/run.py:5954`).
- **One platform down, others fine** — independent reconnect (`_platform_reconnect_watcher`, exponential backoff).
- **Pairing code always invalid** — pairing rate-limit/lockout; wait or clear pending records.
- **Interrupt doesn't interrupt** — active subagent / compression-in-progress auto-degrade to queue.

### Protocols (ch06)
- **ACP won't start** — valid Provider config in `.env`? ACP logs → stderr.
- **Editor can't see agent** — editor config must point to the correct `hermes-acp` command path.
- **File edit rejected** — `edit_approval_policy`: `ask` (default) / `workspace_session` / `session`.
- **MCP unresponsive** — `pip install mcp`; MCP serve needs the gateway running (depends on SessionDB).
- **No tools after MCP connect** — `hermes mcp serve` exposes gateway tools, not the 69 execution tools.

### Kanban (ch09)
- **Task stuck in todo** — incomplete parent; `recompute_ready()` promotes only when all parents done/archived.
- **Ready but doesn't spawn** — `hermes kanban tail <id>` for `respawn_guarded` (reasons in priority: `rate_limit_cooldown` / `blocker_auth` / `recent_success` <1h / `active_pr` <24h); assignee a valid Profile? `dispatch_in_gateway: true`?
- **Worker fails repeatedly** — `consecutive_failures` / `failure_limit` (default 2) → auto-block (`gave_up`, non-sticky).
- **Doesn't recover after blocked** — `blocked` (manual, needs `kanban unblock`) vs `gave_up` (auto, recovers after parent completes).
- **Stuck in running** — Worker crashed but PID lingers → `kanban reclaim`, or wait for `detect_crashed_workers()`.

### Interfaces / TUI / cron / batch / desktop / engineering
- See the per-subsystem tables in Chapters 10 / 11 / 12 / 13 / 14 — the high-frequency ones are in the silent-failure catalog above. Fetch the chapter for the full table when needed.

---

## 5. Fetch the full chapter troubleshooting table / 取全表
`curl -fsSL https://raw.githubusercontent.com/fang-lin/hermes-agent-code-analysis/main/docs/en/NN-slug.md` — each chapter's "## Troubleshooting" / "### Troubleshooting" section has the complete symptom→cause→fix table with anchors.
