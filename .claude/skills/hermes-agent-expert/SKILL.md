---
name: hermes-agent-expert
description: Expert architectural knowledge of NousResearch/hermes-agent internals (analyzed at v0.18.2) — the layered mental model, config, debugging playbooks, safe extension points, and the non-obvious design invariants that prevent wrong changes. Use when setting up, configuring, debugging, customizing, or doing secondary development on hermes-agent, to give architecturally-grounded guidance and avoid known pitfalls. 用于搭建/配置/调试/定制/二次开发 hermes-agent 时,提供有源码依据的专业判断。
---

# Hermes Agent Expert / Hermes Agent 专家

Grounded in a full 15-chapter source teardown of `NousResearch/hermes-agent`, pinned to **v0.18.2** (tag `v2026.7.7.2`, commit `9de9c25f6`, 2026-07-07). This file is self-contained: the mental model, invariants, and routing below work offline. For deep detail, fetch the full chapter on demand (see "Getting depth").

本文件自足:下面的心智地图、不变量、路由离线可用。需要精确细节时按需取全文。所有知识钉在 v0.18.2——**行号会漂移,先 grep 确认再依赖**。

---

## Operating rules / 使用纪律

1. **Orient first, then act.** Use the mental model + routing table to locate the right subsystem before grepping blindly.
2. **Anchors are a map, not scripture.** File paths are stable; **line numbers drift across versions**. Always `grep` the symbol in the *actual checkout* to confirm the current location before quoting or editing. 行号是地图不是圣经,动手前先 grep 核实。
3. **Verify version-sensitive claims.** A feature's presence/behavior differs across versions (this analysis = v0.18.2). If the target checkout is a different version, confirm against its own source. 断言前确认目标 checkout 的版本。
4. **Never violate the invariants below** — they are the rules that keep the system correct and secure.

---

## Mental model — the layered map / 心智地图(分层)

Hermes is an MIT-licensed self-improving agent framework. One `hermes` command fans out to many run modes; underneath, everything connects to the same `AIAgent` core.

```
Interfaces (ch10)   classic TUI (cli.py 16,184) / Ink TUI+tui_gateway / Web Dashboard   ─┐
Desktop    (ch14)   Electron+Tauri client, ZERO Python import, talks only via web API    ─┤
                                                                                          │  all reach
Protocols  (ch06)   ACP adapter (editors) · MCP serve (expose agent as MCP tools)         ─┤─►  AIAgent
Gateway    (ch05)   one process, 20 plugin + 9 built-in platforms (gateway/run.py 20,719) ─┤     core
Subsystems Kanban (ch09 multi-agent) · Cron (ch11 scheduling) · Batch (ch12 data-gen)     ─┤   (ch02)
Plugins    (ch07 framework: 23 hooks + middleware onion) · (ch08 18 categories built-in)   ─┤
Capability Tools (ch03: 69 tools, approval, 7 exec backends) · Skills (ch04: Curator)      ─┤
Core       (ch02) AIAgent = conversation orchestrator: 15-step loop, MoA, credential pool ─┤
Infra      (ch01) hermes_cli: config, auth, subcommands, Profiles (203 files)              ─┘
Engineering(ch13) SQLite session storage · 4-way logging · atomic writes · supply-chain · security model
```

Key files (grep to confirm lines): `run_agent.py` (AIAgent, 6,013 lines — was 13,293 in v0.11, decomposed into `agent/`), `cli.py` (classic TUI, 16,184), `gateway/run.py` (20,719), `model_tools.py` (tool dispatch), `hermes_state.py` (session DB), `cron/scheduler.py` (tick engine), `utils.py` (atomic writes).

Runtime footprint: `~/.hermes/` holds `config.yaml`, `state.db` (sessions, SQLite+WAL), `cron/jobs.json`, `logs/`, `skins/`, `scripts/`. CLI and desktop **share the same `~/.hermes`** — a session started in one is `--resume`-able in the other.

---

## Progressive workflow — scale depth to the problem / 渐进式:按难度逐层深入

Do not front-load everything. Climb only as far as the problem needs — most tasks stop at Tier 1. 大多数任务停在第 1 层;越难越往下走,最深一层是**去读 hermes 真源码**。

- **Tier 0 — this file (always loaded, offline).** Mental model + task routing + invariants. Enough to orient and to avoid the big mistakes. 定向 + 不犯错。
- **Tier 1 — bundled reference sheets (this skill, `reference/`).** Read the one that matches the task:
  - `reference/configuration.md` — config.yaml keys by section, env vars, Profiles, provider/auth. → setup/config tasks.
  - `reference/debugging.md` — log-file map, diagnostic commands, the silent-failure catalog, symptom→cause→fix by subsystem. → debugging tasks.
  - `reference/extending.md` — step-by-step recipes to add a tool/skill/platform/plugin-hook/provider/backend. → customization / secondary development.
  - `reference/architecture.md` — request path, agent loop, caching invariant, subsystem→source map. → "how does it actually work" / where to look.
  - `scripts/orient.sh [hermes-root]` — prints the installed version + key-file line-count drift vs the pinned anchors, so you know how much to distrust the line numbers. Run this first when working in an unfamiliar checkout.
- **Tier 2 — the full 15-chapter analysis (fetch on demand).** For the *why* (design rationale, alternatives considered, failure modes) the code alone won't tell you:
  - One chapter (light): `curl -fsSL https://raw.githubusercontent.com/fang-lin/hermes-agent-code-analysis/main/docs/en/NN-slug.md` (Chinese: `docs/zh/…`; en slugs are ASCII).
  - Whole repo (broad/cross-chapter): `git clone https://github.com/fang-lin/hermes-agent-code-analysis` (markdown only, ~hundreds of KB).
  - Slugs: `00-project-overview 01-infrastructure 02-agent-core 03-tool-system 04-skill-system 05-gateway 06-protocols 07-plugin-framework 08-builtin-plugins 09-kanban 10-interfaces-and-run-modes 11-cron-scheduling 12-batch-and-trajectories 13-engineering-practices 14-desktop-app`.
- **Tier 3 — read the actual hermes source (the goal).** For anything the analysis doesn't fully answer, or when the checkout differs from v0.18.2: the routing table + subsystem→source map (in `architecture.md`) point you to the exact file/symbol/directory. `grep -n "def <symbol>\|class <symbol>"` to find the current line, read the function with its callers/callees, and solve from the ground truth. **The analysis is the map; the real source is the territory — this skill exists to get you to the right region of it fast.** 分析是地图,真源码是实地——这个 skill 的终点就是带你快速定位到该读的那段真源码。

No network / restricted: stay at Tier 0–1 (bundled); they carry the essentials.

---

## Task routing — where to look / 任务路由

For operational depth, read the matching Tier-1 sheet first (config→`reference/configuration.md`, debug→`reference/debugging.md`, extend→`reference/extending.md`, how-it-works→`reference/architecture.md`). The table below gives the deep chapter + the exact source symbol to grep in the actual checkout.

| Task / 任务 | Chapter | Start by grepping (in the actual checkout) |
|---|---|---|
| Install / first-run / providers / auth | 01, 10 | `hermes_cli/main.py`, `hermes_cli/setup.py`, `auth.py` |
| Configure (`config.yaml` keys) | subsystem ch + 01 | grep the key in source; `display.*`→10, `cron.*`→11, `stt/tts/voice.*`→10, `security.*`→03/13 |
| Profiles / `HERMES_HOME` | 01 | `hermes_cli/` profile resolution |
| Debug an agent hang / interrupt | 02, 10 | `agent.interrupt`, `~/.hermes/logs/interrupt_debug.log` |
| Which log, what's wrong | 13 | `~/.hermes/logs/{agent,errors,gateway,gui}.log`; `hermes_logging.py` |
| Cron job not firing | 11 | `cron/scheduler.py` (`tick`), `cron/jobs.py`; gateway must run |
| Session / DB errors (`database is locked`, malformed) | 13 | `hermes_state.py` (`_execute_write`, `repair_state_db_schema`) |
| TUI crash / Ink TUI exits | 10 | `~/.hermes/logs/tui_gateway_crash.log`; `tui_gateway/server.py` |
| Add a tool | 03 | `tools/registry.py`, `model_tools.py`, `toolsets.py` |
| Add / edit a skill | 04 | `skills/`, `optional-skills/`, SKILL.md format; Curator |
| Add a messaging platform | 05, 08 | `gateway/platform_registry.py`, `plugins/platforms/` |
| Add a plugin / lifecycle hook | 07, 08 | `hermes_cli/plugins.py` (`VALID_HOOKS`), PluginContext |
| Custom interface / skin / voice | 10 | `hermes_cli/skin_engine.py`, `tools/voice_mode.py` |
| Editor / MCP integration | 06 | `acp_adapter/`, `mcp_serve.py` |
| Multi-agent orchestration | 09 | `kanban/` (dispatcher/worker/orchestrator) |
| Generate training data | 12 | `batch_runner.py`, `trajectory_compressor.py` |
| Desktop app internals | 14 | `apps/desktop/electron/main.cjs`, `apps/shared/` |
| Testing / security / supply chain | 13 | `tests/conftest.py`, `pyproject.toml`, `SECURITY.md` |

---

## Core invariants — DO NOT violate / 核心不变量(不可违反)

These are the non-obvious rules where a plausible-looking change quietly breaks correctness, cost, or security. Each has a *why* and a source anchor (grep to confirm).

1. **Prompt caching is an architectural constraint, not a cost trick.** Static content (system prompt, injected memory) must stay byte-stable across turns to hit the cache; dynamic/timestamped content goes in **user** messages, never the system prompt. Injecting dynamic content into the system prompt busts the cache for the whole session. Memory uses *dual injection* (static→system prompt, dynamic→user message). — `run_agent.py` (system-prompt assembly), ch02. 中文:动态内容进 system prompt 会打破整会话缓存。

2. **The hardline blacklist always applies — even under `--yolo`.** Irreversible ops (`rm -rf /`, fork bomb, `dd` to a raw disk) are unconditionally rejected; even "always allow" can't bypass them. Don't rely on approval to catch these, and don't assume `--yolo` disables them. — `HARDLINE_PATTERNS`, ch03/ch13. 中文:hardline 黑名单 --yolo 也绕不过。

3. **Approval / output redaction / Skills Guard are HEURISTICS, not security boundaries.** They guard against fat-fingering and accidents, not a determined adversary. The *real* boundaries are terminal-backend isolation (Docker/Modal/sandbox) and whole-process wrapping. Prompt injection and heuristic bypass are explicitly **out of scope** (`SECURITY.md`, no bug bounty). Never present approval as a security control when designing. — ch13. 中文:审批是防手滑,不是安全边界;真边界是沙箱隔离。

4. **State files must be written atomically.** `cron/jobs.json`, OAuth creds, batch checkpoints go through `atomic_replace` (temp → fsync → rename). User-edited `config.yaml` MUST use `atomic_roundtrip_yaml_update` (ruamel roundtrip) — a plain `yaml.dump` wipes the user's comments. Never hand-write these non-atomically. Edge case: cross-device rename falls back to a non-atomic copy. — `utils.py`, ch13/ch11. 中文:改 config.yaml 用 roundtrip,否则注释被清光。

5. **Cron is at-most-once: it advances `next_run_at` BEFORE executing.** A run that crashes mid-flight is **not** auto-retried (side-effect safety — repeated "send message"/"mutate data" is worse than a miss). Missed runs beyond the grace window are silently fast-forwarded, not backfilled. Don't expect missed jobs to catch up. — `cron/scheduler.py` (`advance_next_run`, `tick`), ch11. 中文:cron 不补跑、崩溃不自动重试。

6. **Session storage is single-writer SQLite under multi-process load.** WAL + `BEGIN IMMEDIATE` + jittered retry (15×). On NFS/SMB it degrades to `journal_mode=DELETE`. A write that exhausts retries **silently drops the message** (logged as a warning) — the conversation continues in memory but that message isn't persisted. Don't assume every message reaches disk. — `hermes_state.py` (`_execute_write`), ch13. 中文:写重试耗尽会静默丢消息。

7. **Extend without touching core.** New capabilities go in as entry-point **plugins** (memory/model providers, platform adapters, cron providers), **skills** (SKILL.md), or **tools** — not edits to `run_agent.py`/`gateway/`. Contribution priority: **Skill > Tool** (keep `tools/` from bloating). Prefer a Skill unless you truly need a new Tool. — ch07/ch08/ch13. 中文:能力靠插件/技能/工具扩展,别改核心;优先做 Skill。

8. **Platforms are plugins now (since v0.15), not gateway built-ins.** 20 plugin + 9 built-in. To add/modify a platform, write a plugin under `plugins/platforms/`; deferred loading keeps heavy SDKs out of startup. Don't add platform logic to gateway core. — `gateway/platform_registry.py`, ch05/ch08. 中文:平台已插件化,别往 gateway 核心塞。

9. **The god-file decomposition direction is EXTRACT, not grow.** `run_agent.py` shrank 13,293→6,013 by pulling logic into `agent/`. New logic belongs in focused modules, not back into the giants (`cli.py` 16,184, `gateway/run.py` 20,719). — ch00/ch13. 中文:新逻辑进独立模块,别喂胖上帝文件。

10. **RL training infra left the main repo (v0.14).** `batch_runner.py` → `trajectory_compressor.py` produce ShareGPT training data, but the RL *environments* (Atropos, `rl_cli`, `tool_call_parsers`) were moved to a separate repo. Don't hunt for RL training code in the main repo. — ch12. 中文:RL 训练环境已移出主仓,别在主仓找。

11. **MoA (Mixture of Agents) is fail-open; memory injection is conversation-level.** If the advisor/reference model fails, MoA degrades to a labeled opinion without interrupting the main path. `MemoryManager` injects at API-call time into the current message and does **not** mutate the original message or persist to the session. — `moa_loop.py`, ch02/ch08. 中文:MoA 失败降级不中断;记忆是对话级注入、不进会话持久化。

---

## Verification discipline (recap) / 验证纪律(重申)

- Pinned to **v0.18.2 / `9de9c25f6`**. Before quoting or editing at a line number, `grep` the symbol in the actual checkout — line numbers drift.
- A claim about "when a feature appeared" is version-sensitive; confirm against the target checkout's own history if it matters.
- When unsure, read the relevant chapter (fetch on demand) rather than guessing — the chapters carry the full file:line-anchored reasoning.
- Calibrate drift fast: run `scripts/orient.sh [hermes-root]` — it prints the installed version and the key-file line-count drift vs the pinned anchors, so you know upfront how much to distrust the line numbers.
