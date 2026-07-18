# Configuration Reference / 配置参考

The authoritative source is the running `~/.hermes/config.yaml` (~1,440 lines of tunable params) and the config schema in source (`config.py`, `DEFAULT_CONFIG`). This sheet catalogs the keys that matter, by section — **grep the key in the actual checkout to see its exact default and validation**. Pinned to v0.18.2.
本页按段罗列高频配置键。权威来源是本机 `config.yaml` 与源码 `config.py`;要精确默认值就 grep 键名。

---

## 0. How config loads / 配置怎么加载(先懂这个)

- File: `~/.hermes/config.yaml` (user) merged over a managed file over `DEFAULT_CONFIG`. `load_config()` in `config.py`.
- **Signature cache**: keyed by mtime_ns/size of user+managed files + a snapshot of referenced env vars (`hermes_cli/config.py:226-231`). A running gateway holds its own cache → **edit had no effect ⇒ restart the gateway**.
- **Syntax error = all overrides lost**: falls back to `DEFAULT_CONFIG`, backs up to `config.yaml.corrupt.<ts>.bak`, warns, rebuilds (`hermes_cli/config.py:42/96`).
- **Programmatic edits must use `atomic_roundtrip_yaml_update`** (ruamel roundtrip) to preserve the user's comments — a plain `yaml.dump` wipes them. `migrate_config()` (`hermes_cli/config.py:5395`) is incremental, never deletes fields.

---

## 1. Providers & models / 供应商与模型

| Key | Purpose |
|---|---|
| `providers:` | per-provider config (base_url, api_key_env_vars, models…). Add a custom provider here — no code needed (ch01). |
| `model_aliases:` | short names → full model IDs. |
| `fallback_model` | cross-provider automatic fallback chain (ch02). |
| `moa.presets` | Mixture-of-Agents: reference-model list + aggregator + sampling + fanout. Managed by `hermes moa`. Appears as virtual provider `moa://local`. |
| `auxiliary.background_review.{provider,model}` | which model runs the background memory/skill self-improvement review (ch04). |

Auth: API keys live in `~/.hermes/.env` (var names must match `api_key_env_vars` in `PROVIDER_REGISTRY`). `provider=auto` is an **8-level precedence chain** — an exported API key preempts an OAuth login. Commands: `hermes login`, `hermes auth status`. Debug OAuth with `HERMES_OAUTH_TRACE=1`.

---

## 2. Agent behavior / Agent 行为

| Key | Purpose |
|---|---|
| `agent.max_turns` / `max_turns` | max tool-iteration rounds per turn. |
| `agent.max_verify_nudges` | hard cap on `pre_verify` re-runs (default 3, `hermes_cli/config.py:1027`) — beyond it the turn ends regardless. |
| `agent.api_max_retries` | API retry count. |
| `agent.restart_drain_timeout` | graceful-drain window on gateway restart. |
| `delegation.max_iterations` | subagent iteration budget (default 50). |
| `delegation.max_spawn_depth` | how deep subagents can nest. |
| `delegation.child_timeout_seconds` | subagent wall-clock timeout. |
| `compression.abort_on_summary_failure` | on compression failure: freeze-and-wait (true) vs static-summary fallback that may drop middle messages (false, default). |
| `reasoning.*` | reasoning-model timeout floors (`agent/reasoning_timeouts.py`). |

---

## 3. Tools, security & approval / 工具·安全·审批

| Key | Purpose |
|---|---|
| `terminal.backend` | execution backend: local / docker / modal / ssh / … (the 7 environments, ch03). |
| `terminal.timeout` | command timeout (default 180s). |
| `command_allowlist` | pre-approve specific command patterns. |
| `approvals.mode` / `approvals.cron_mode` / `approvals.timeout` | approval policy; gateway approval times out at 300s. |
| `write_approval` | (v0.17+) gate persistent memory/skill writes, incl. background self-improvement (`tools/write_approval.py`). |
| `edit_approval_policy` | ACP file edits: `ask` / `workspace_session` / `session` (ch06). |
| `security.allow_lazy_installs` | allow on-demand optional-dependency install (set false in restricted envs). |
| `mcp_servers:` | external MCP server configs (extends tool capabilities). |

**Invariant**: the hardline blacklist (`HARDLINE_PATTERNS`, `tools/approval.py:366`) rejects irreversible ops unconditionally — no config, not even `--yolo`, bypasses it. Approval/redaction are heuristics, not security boundaries (ch13).

---

## 4. Interface, skins, voice / 界面·皮肤·语音 (ch10)

| Key | Purpose |
|---|---|
| `display.interface` | default `tui` (Ink) vs `cli` (classic). |
| `display.skin` | skin: default/ares/mono/slate/daylight/poseidon/sisyphus/charizard/warm-lightmode or custom. |
| `display.personality` | tone (orthogonal to skin). `personalities:` defines custom ones. |
| `display.busy_input_mode` | enter while busy: `interrupt` / `queue` / `steer`. |
| `display.final_response_markdown` | `render` / `strip` (actual default) / `raw`. |
| `display.tui_status_indicator` | `kaomoji` / `emoji` / `unicode` / `ascii`. |
| `display.details_mode` | Ink panels: `hidden` / `collapsed` / `expanded`. |
| `display.mouse_tracking` | `off` / `wheel` / `buttons` / `all` (use `wheel` under tmux). |
| `voice.record_key`, `stt:`, `tts:` | voice mode; STT/TTS providers (local Whisper + Edge TTS = zero-key). |
| `quick_commands:` | slash commands that run shell directly, no LLM. |

Custom skin: `~/.hermes/skins/<name>.yaml` (only the keys to change; `tool_emojis` is wholesale-replaced, not merged).

---

## 5. Subsystems / 子系统

| Key | Purpose |
|---|---|
| `cron.wrap_response` / `cron.script_timeout_seconds` / `cron.mirror_delivery` | cron output wrapper / pre-run script timeout (3600s) / mirror cron output back to source session (ch11). |
| `memory.provider` | which external memory backend (ch08). |
| `image_gen.provider` | image backend; if set, no auto-fallback (reports exact missing key); if unset, implicit fallback (ch08). |
| `skills.creation_nudge_interval` | auto-skill review frequency (default 10 tool iters). |
| `skills.disabled` / `skills.platform_disabled` / `skills.external_dirs` | disable skills / per-platform / extra skill dirs. |
| `gateway.allowed_users` | messaging allowlist. |
| `session_reset` / `SessionResetPolicy` | gateway idle/daily context reset (`gateway/config.py:347`). |
| `plugins.enabled` / `plugins.disabled` | plugin allowlist / denylist (ch07). |

---

## 6. Environment variables / 环境变量(高频)

| Var | Effect |
|---|---|
| `HERMES_HOME` | root dir; the basis of Profile isolation. |
| `HERMES_PROFILE` | active profile (→ `~/.hermes/profiles/<name>/`). |
| `HERMES_MANAGED` / `HERMES_TENANT` | managed/multi-tenant mode. |
| `HERMES_TUI` / `HERMES_TUI_RESUME` / `HERMES_TUI_DIR` / `HERMES_TUI_GATEWAY_URL` | force Ink TUI / auto-resume / external bundle / attach to gateway. |
| `HERMES_YOLO_MODE` | bypass command approval (hardline still applies). |
| `HERMES_STREAM_STALE_TIMEOUT` | stream stall → retry (default 180s). |
| `HERMES_SIGTERM_GRACE` | SIGTERM cleanup window (default 1.5s). |
| `HERMES_CRON_TIMEOUT` / `HERMES_CRON_SCRIPT_TIMEOUT` / `HERMES_CRON_MAX_PARALLEL` | cron liveness timeout (600s) / script timeout (3600s) / force-serial (=1). |
| `HERMES_LOCAL_STT_COMMAND` | custom local speech-to-text command. |
| `HERMES_OAUTH_TRACE` / `HERMES_PLUGINS_DEBUG` / `HERMES_LANGFUSE_DEBUG` | debug traces (see debugging.md). |
| `HERMES_DESKTOP*` | desktop mode switches (ch14). |
| `HERMES_KANBAN_*` | Kanban board/branch/db/task/workspace context (ch09). |
| `HERMES_ENABLE_PROJECT_PLUGINS` | enable project-scoped plugins. |
| `HERMES_REDACT_SECRETS` | snapshotted at import — a mid-session change can't turn redaction off (anti-jailbreak, ch13). |

---

## 7. Profiles / 多配置档
Each Profile is a fully isolated `~/.hermes/profiles/<name>/` with its own `config.yaml`, `state.db`, `cron/jobs.json`, skins. `hermes profile list`. If launched oddly and `HERMES_HOME` is unset, `get_hermes_home()` reveals the actual path.
- **Selecting a profile — prefer the `--profile <name>` flag for subcommands** (`hermes --profile alice cron list --all`). The `HERMES_PROFILE` env var is fragile: `_apply_profile_override()` (`hermes_cli/main.py:340`) must run **before imports**, so for some subcommands (cron/skills) `HERMES_PROFILE=alice hermes cron list --all` silently falls back to the default profile. Set the env var before the process starts, or just use `--profile`.

---

## Where to read the real source / 去哪读真源码
Config schema & loading: `config.py` (grep the key). Auth/providers: `auth.py`, `PROVIDER_REGISTRY`. For the exhaustive per-key default and comment, the running `~/.hermes/config.yaml` is itself the reference (managed section carries inline docs). Deep dive: fetch `docs/en/01-infrastructure.md` (config/auth) and the relevant subsystem chapter.
